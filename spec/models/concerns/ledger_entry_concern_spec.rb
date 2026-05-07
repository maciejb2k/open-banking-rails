# frozen_string_literal: true

require "rails_helper"

RSpec.describe LedgerEntryConcern do
  it "returns nil from every delegator and from effective_category on a fresh BankTransaction with no enrichment" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    tx = create(:bank_transaction, bank_account: account)

    expect(tx.enrichment).to be_nil
    expect(tx.merchant).to be_nil
    expect(tx.category).to be_nil
    expect(tx.enrichment_source).to be_nil
    expect(tx.effective_category).to be_nil
  end

  it "returns nil from every delegator and from effective_category on a fresh ManualTransaction with no enrichment" do
    user = create(:user)
    cash = create(:bank_account, :cash, manual_owner: user)
    tx = create(:manual_transaction, user: user, bank_account: cash)

    tx.enrichment&.destroy
    tx.reload

    expect(tx.enrichment).to be_nil
    expect(tx.merchant).to be_nil
    expect(tx.category).to be_nil
    expect(tx.effective_category).to be_nil
  end

  it "returns the explicit category from effective_category when both override and merchant default exist" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    override = create(:category, user: user, slug: "ov", path: "ov")
    default  = create(:category, user: user, slug: "df", path: "df")
    merchant = create(:merchant, user: user, default_category: default)
    tx = create(:bank_transaction, bank_account: account)
    create(:transaction_enrichment, enrichable: tx, merchant: merchant, category: override, source: "manual", category_overridden: true)

    expect(tx.reload.effective_category).to eq(override)
  end

  it "falls back to the merchant default category when no override is set" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    default = create(:category, user: user, slug: "df", path: "df")
    merchant = create(:merchant, user: user, default_category: default)
    tx = create(:bank_transaction, bank_account: account)
    create(:transaction_enrichment, enrichable: tx, merchant: merchant, category: nil, source: "system_rule")

    expect(tx.reload.effective_category).to eq(default)
  end

  it "returns nil from effective_category when enrichment has neither category nor merchant" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    tx = create(:bank_transaction, bank_account: account)
    create(:transaction_enrichment, enrichable: tx, merchant: nil, category: nil, source: "unmatched")

    expect(tx.reload.effective_category).to be_nil
  end

  it "destroys the polymorphic enrichment when the BankTransaction source row is destroyed" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    tx = create(:bank_transaction, bank_account: account)
    enrichment = create(:transaction_enrichment, enrichable: tx, source: "system_rule")

    expect { tx.destroy }.to change { TransactionEnrichment.exists?(enrichment.id) }.from(true).to(false)
  end

  it "destroys the polymorphic enrichment when the ManualTransaction source row is destroyed" do
    user = create(:user)
    cash = create(:bank_account, :cash, manual_owner: user)
    tx = create(:manual_transaction, user: user, bank_account: cash)
    tx.enrichment&.destroy
    enrichment = create(:transaction_enrichment, enrichable: tx, source: "manual")
    tx.reload

    expect { tx.destroy }.to change { TransactionEnrichment.exists?(enrichment.id) }.from(true).to(false)
  end

  it "agrees with the LedgerEntry view's effective_category_id across the override / merchant-default / unmatched matrix" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    override = create(:category, user: user, slug: "ov", path: "ov")
    default  = create(:category, user: user, slug: "df", path: "df")
    merchant = create(:merchant, user: user, default_category: default)

    with_override = create(:bank_transaction, bank_account: account)
    create(:transaction_enrichment, enrichable: with_override, merchant: merchant, category: override, source: "manual", category_overridden: true)

    merchant_default_only = create(:bank_transaction, bank_account: account)
    create(:transaction_enrichment, enrichable: merchant_default_only, merchant: merchant, category: nil, source: "system_rule")

    unmatched = create(:bank_transaction, bank_account: account)

    [ with_override, merchant_default_only, unmatched ].each do |tx|
      tx.reload
      view_row = LedgerEntry.find_by(source_type: "BankTransaction", source_id: tx.id)
      ar_id    = tx.effective_category&.id
      view_id  = view_row.effective_category_id
      expect(ar_id).to eq(view_id), "concern's effective_category=#{ar_id.inspect} disagrees with view=#{view_id.inspect} for tx ##{tx.id}"
    end
  end
end
