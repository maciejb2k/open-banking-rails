# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionEnrichment do
  it "resolves effective_category to category > merchant.default_category > nil" do
    user = create(:user)
    explicit = create(:category, user: user, name: "Explicit", slug: "explicit_cat", path: "explicit_cat_#{SecureRandom.hex(2)}")
    fallback = create(:category, user: user, name: "Default", slug: "default_cat", path: "default_cat_#{SecureRandom.hex(2)}")
    merchant_with_default = create(:merchant, user: user, default_category: fallback)
    merchant_without_default = create(:merchant, user: user)

    wallet = create(:bank_account, :cash, manual_owner: user, currency: "PLN")
    tx_a = create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN")
    tx_b = create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN")
    tx_c = create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN")

    explicit_enrichment = create(:transaction_enrichment, enrichable: tx_a, source: "user_rule", category: explicit, merchant: merchant_with_default)
    via_merchant_default = create(:transaction_enrichment, enrichable: tx_b, source: "system_rule", category: nil, merchant: merchant_with_default)
    no_resolution = create(:transaction_enrichment, enrichable: tx_c, source: "unmatched", category: nil, merchant: merchant_without_default)

    expect(explicit_enrichment.effective_category).to eq(explicit)
    expect(via_merchant_default.effective_category).to eq(fallback)
    expect(no_resolution.effective_category).to be_nil
  end

  it "limits the rebuildable scope to non-manual rows where category_overridden is false" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user, currency: "PLN")
    txs = Array.new(4) { create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN") }

    manual_overridden        = create(:transaction_enrichment, enrichable: txs[0], source: "manual",      category_overridden: true)
    manual_not_overridden    = create(:transaction_enrichment, enrichable: txs[1], source: "manual",      category_overridden: false)
    rule_overridden          = create(:transaction_enrichment, enrichable: txs[2], source: "system_rule", category_overridden: true)
    rule_not_overridden      = create(:transaction_enrichment, enrichable: txs[3], source: "system_rule", category_overridden: false)

    rebuildable_ids = described_class.rebuildable.pluck(:id)
    expect(rebuildable_ids).to contain_exactly(rule_not_overridden.id)
    expect(rebuildable_ids).not_to include(manual_overridden.id, manual_not_overridden.id, rule_overridden.id)
  end

  it "includes both unmatched and system_fallback rows in the merchantless scope" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user, currency: "PLN")
    tx_unmatched = create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN")
    tx_fallback  = create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN")
    tx_with      = create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN")
    merchant = create(:merchant, user: user)

    unmatched = create(:transaction_enrichment, enrichable: tx_unmatched, source: "unmatched", merchant: nil)
    fallback  = create(:transaction_enrichment, enrichable: tx_fallback,  source: "system_fallback", merchant: nil)
    matched   = create(:transaction_enrichment, enrichable: tx_with,      source: "system_rule", merchant: merchant)

    ids = described_class.merchantless.pluck(:id)
    expect(ids).to contain_exactly(unmatched.id, fallback.id)
    expect(ids).not_to include(matched.id)
  end

  it "scopes for_user(user) across both polymorphic enrichable types" do
    user_a = create(:user)
    user_b = create(:user)
    tpp_a = create(:tpp_credential, user: user_a)
    account_a = create(:bank_account, tpp_credential: tpp_a, currency: "PLN")
    bank_tx_a = create(:bank_transaction, bank_account: account_a, currency: "PLN")
    enrichment_a_bank = create(:transaction_enrichment, enrichable: bank_tx_a, source: "system_rule")

    wallet_b = create(:bank_account, :cash, manual_owner: user_b, currency: "PLN")
    manual_tx_b = create(:manual_transaction, bank_account: wallet_b, created_by_user: user_b, currency: "PLN")
    enrichment_b_manual = create(:transaction_enrichment, enrichable: manual_tx_b, source: "system_rule")

    tpp_b = create(:tpp_credential, user: user_b)
    account_b = create(:bank_account, tpp_credential: tpp_b, currency: "PLN")
    bank_tx_b = create(:bank_transaction, bank_account: account_b, currency: "PLN")
    enrichment_b_bank = create(:transaction_enrichment, enrichable: bank_tx_b, source: "system_rule")

    expect(described_class.for_user(user_a).pluck(:id)).to contain_exactly(enrichment_a_bank.id)
    expect(described_class.for_user(user_b).pluck(:id)).to contain_exactly(enrichment_b_manual.id, enrichment_b_bank.id)
  end

  it "enforces DB-level uniqueness on (enrichable_type, enrichable_id)" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user, currency: "PLN")
    tx = create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN")
    create(:transaction_enrichment, enrichable: tx, source: "system_rule")

    expect {
      create(:transaction_enrichment, enrichable: tx, source: "user_rule")
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "exposes manual?, unmatched?, llm? predicates over the source field" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user, currency: "PLN")
    txs = Array.new(5) { create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN") }

    manual    = build(:transaction_enrichment, enrichable: txs[0], source: "manual")
    unmatched = build(:transaction_enrichment, enrichable: txs[1], source: "unmatched")
    llm_rule  = build(:transaction_enrichment, enrichable: txs[2], source: "llm_rule")
    llm_pend  = build(:transaction_enrichment, enrichable: txs[3], source: "llm_pending")
    rule      = build(:transaction_enrichment, enrichable: txs[4], source: "system_rule")

    expect(manual).to    be_manual
    expect(unmatched).to be_unmatched
    expect(llm_rule).to  be_llm
    expect(llm_pend).to  be_llm
    expect(rule).not_to  be_llm
    expect(rule).not_to  be_manual
    expect(rule).not_to  be_unmatched
  end
end
