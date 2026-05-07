# frozen_string_literal: true

require "rails_helper"

RSpec.describe BankAccount do
  it "rejects a wallet (manual=true) that also carries a tpp_credential_id with a friendly error" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    bad = build(:bank_account, manual: true, manual_owner: user, tpp_credential: tpp)

    expect(bad).not_to be_valid
    expect(bad.errors[:tpp_credential_id]).to include("must be blank for a cash wallet")
  end

  it "rejects a wallet (manual=true) without a manual_owner with an :manual_owner_id error" do
    bad = build(:bank_account, manual: true, manual_owner: nil, tpp_credential: nil)

    expect(bad).not_to be_valid
    expect(bad.errors[:manual_owner_id]).to include("is required for a cash wallet")
  end

  it "rejects a synced account that also carries a manual_owner with a friendly error" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    bad = build(:bank_account, manual: false, tpp_credential: tpp, manual_owner: user)

    expect(bad).not_to be_valid
    expect(bad.errors[:manual_owner_id]).to include("must be blank for a synced account")
  end

  it "rejects a synced account without a tpp_credential with a friendly error" do
    bad = build(:bank_account, manual: false, tpp_credential: nil, manual_owner: nil)

    expect(bad).not_to be_valid
    expect(bad.errors[:tpp_credential_id]).to include("is required for a synced account")
  end

  it "lets the DB check constraint reject inconsistent ownership when AR validation is bypassed" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    rogue = build(:bank_account, manual: true, manual_owner: user, tpp_credential: tpp)

    expect { rogue.save(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "falls back through the display_name chain (name → product → details → iban → uid)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)

    explicit = build(:bank_account, tpp_credential: tpp, name: "Konto Główne", product: "Personal", iban: "PL...")
    expect(explicit.display_name).to eq("Konto Główne")

    no_name = build(:bank_account, tpp_credential: tpp, name: nil, product: "Konto Premium", iban: "PL...")
    expect(no_name.display_name).to eq("Konto Premium")

    only_uid = build(:bank_account, tpp_credential: tpp, name: nil, product: nil, details: nil, iban: nil, uid: "fake-uid-9999")
    expect(only_uid.display_name).to eq("fake-uid-9999")
  end

  it "returns the manual_owner for a wallet and the tpp_credential's user for a synced account from owner" do
    wallet_owner = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: wallet_owner)
    expect(wallet.owner).to eq(wallet_owner)

    synced_owner = create(:user)
    tpp = create(:tpp_credential, user: synced_owner)
    synced = create(:bank_account, tpp_credential: tpp)
    expect(synced.owner).to eq(synced_owner)
  end

  it "returns alternate IBAN identifications excluding the primary and any non-IBAN scheme entries" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp,
                                    iban: "PL61109010140000071219812874",
                                    all_account_ids: [
                                      { "scheme_name" => "IBAN", "identification" => "PL61109010140000071219812874" },
                                      { "scheme_name" => "IBAN", "identification" => "LT123456789012345678" },
                                      { "scheme_name" => "BBAN", "identification" => "1234567890" }
                                    ])

    expect(account.alternate_ibans).to contain_exactly("LT123456789012345678")
  end

  it "extracts the BBAN payload via BankAccount.bban_from for matching shapes and nil otherwise" do
    expect(described_class.bban_from({ "other" => { "scheme_name" => "BBAN", "identification" => "1234" } })).to eq("1234")
    expect(described_class.bban_from({ "other" => { "scheme_name" => "IBAN", "identification" => "1234" } })).to be_nil
    expect(described_class.bban_from(nil)).to be_nil
    expect(described_class.bban_from({})).to be_nil
  end

  it "returns [] from parsed_balances on blank, garbage JSON, or a payload missing the balances key" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)

    blank = create(:bank_account, tpp_credential: tpp)
    expect(blank.parsed_balances).to eq([])

    garbage = create(:bank_account, tpp_credential: tpp, raw_balances: "not json")
    expect(garbage.parsed_balances).to eq([])

    no_key = create(:bank_account, tpp_credential: tpp, raw_balances: { foo: 1 }.to_json)
    expect(no_key.parsed_balances).to eq([])
  end

  it "treats needs_details_refresh? as true for blank or stale (>7d) details_fetched_at" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)

    fresh = build(:bank_account, tpp_credential: tpp, details_fetched_at: 1.day.ago)
    stale = build(:bank_account, tpp_credential: tpp, details_fetched_at: 8.days.ago)
    blank = build(:bank_account, tpp_credential: tpp, details_fetched_at: nil)

    expect(fresh.needs_details_refresh?).to be(false)
    expect(stale.needs_details_refresh?).to be(true)
    expect(blank.needs_details_refresh?).to be(true)
  end

  it "round-trips encrypted raw_balances with the raw column not containing the plaintext" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    payload = { balances: [ { balance_type: "ITAV", balance_amount: { amount: "100.00" } } ] }.to_json
    account = create(:bank_account, tpp_credential: tpp, raw_balances: payload)
    account.reload

    expect(account.raw_balances).to eq(payload)
    expect_encrypted_at_rest(account, :raw_balances, "ITAV")
  end
end
