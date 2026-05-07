# frozen_string_literal: true

require "rails_helper"

RSpec.describe BankTransaction do
  it "returns a positive Money for credits and the negation for debits in signed_amount" do
    tpp = create(:tpp_credential)
    account = create(:bank_account, tpp_credential: tpp, currency: "PLN")
    credit = create(:bank_transaction, bank_account: account, amount_cents: 50_00, currency: "PLN", direction: "credit")
    debit  = create(:bank_transaction, bank_account: account, amount_cents: 50_00, currency: "PLN", direction: "debit")

    expect(credit.signed_amount).to eq(Money.new(5000, "PLN"))
    expect(debit.signed_amount).to eq(Money.new(-5000, "PLN"))
  end

  it "parses raw_payload as JSON, returning the Hash on success and nil for blank or garbage" do
    tpp = create(:tpp_credential)
    account = create(:bank_account, tpp_credential: tpp)

    parseable = create(:bank_transaction, bank_account: account, raw_payload: { foo: 1 }.to_json)
    blank     = create(:bank_transaction, bank_account: account, raw_payload: "{}")
    garbage   = create(:bank_transaction, bank_account: account, raw_payload: "not json")

    expect(parseable.parsed_raw_payload).to eq("foo" => 1)
    expect(blank.parsed_raw_payload).to eq({})
    expect(garbage.parsed_raw_payload).to be_nil
  end

  it "scopes external_id uniqueness to bank_account_id (same id on different accounts is allowed)" do
    tpp = create(:tpp_credential)
    account_a = create(:bank_account, tpp_credential: tpp)
    account_b = create(:bank_account, tpp_credential: tpp)
    create(:bank_transaction, bank_account: account_a, external_id: "shared-id")

    duplicate_same_account = build(:bank_transaction, bank_account: account_a, external_id: "shared-id")
    expect(duplicate_same_account).not_to be_valid
    expect(duplicate_same_account.errors[:external_id]).to include("has already been taken")

    expect {
      create(:bank_transaction, bank_account: account_b, external_id: "shared-id")
    }.to change(described_class, :count).by(1)
  end

  it "isolates transactions across users via for_user(user)" do
    user_a = create(:user)
    user_b = create(:user)
    tpp_a = create(:tpp_credential, user: user_a)
    tpp_b = create(:tpp_credential, user: user_b)
    account_a = create(:bank_account, tpp_credential: tpp_a)
    account_b = create(:bank_account, tpp_credential: tpp_b)
    tx_a = create(:bank_transaction, bank_account: account_a)
    tx_b = create(:bank_transaction, bank_account: account_b)

    expect(described_class.for_user(user_a).pluck(:id)).to contain_exactly(tx_a.id)
    expect(described_class.for_user(user_b).pluck(:id)).to contain_exactly(tx_b.id)
  end

  it "filters without_enrichment to rows with no associated TransactionEnrichment" do
    tpp = create(:tpp_credential)
    account = create(:bank_account, tpp_credential: tpp)
    raw = create(:bank_transaction, bank_account: account)
    enriched = create(:bank_transaction, bank_account: account)
    create(:transaction_enrichment, enrichable: enriched, source: "system_rule")

    ids = described_class.without_enrichment.pluck(:id)
    expect(ids).to include(raw.id)
    expect(ids).not_to include(enriched.id)
  end

  it "round-trips encrypted raw_payload with the raw column not containing the plaintext" do
    tpp = create(:tpp_credential)
    account = create(:bank_account, tpp_credential: tpp)
    payload = { transaction_id: "abc", note: "secret-merchant" }.to_json
    tx = create(:bank_transaction, bank_account: account, raw_payload: payload)
    tx.reload

    expect(tx.raw_payload).to eq(payload)
    expect_encrypted_at_rest(tx, :raw_payload, "secret-merchant")
  end

  it "rejects an invalid counterparty_kind via the inclusion validator" do
    tpp = create(:tpp_credential)
    account = create(:bank_account, tpp_credential: tpp)
    bad = build(:bank_transaction, bank_account: account, counterparty_kind: "alien")

    expect(bad).not_to be_valid
    expect(bad.errors[:counterparty_kind]).to include("is not included in the list")
  end
end
