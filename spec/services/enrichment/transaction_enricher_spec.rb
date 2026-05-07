# frozen_string_literal: true

require "rails_helper"

RSpec.describe Enrichment::TransactionEnricher do
  def setup_user_with_account
    user = create(:user)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp, currency: "PLN")
    [ user, account ]
  end

  it "ranks user-source rules above llm-source above system-source on the same matchable transaction" do
    user, account = setup_user_with_account
    merchant_user = create(:merchant, user: user, name: "User Merchant", slug: "user_m")
    merchant_llm  = create(:merchant, user: user, name: "LLM Merchant",  slug: "llm_m")
    merchant_sys  = create(:merchant, :system, user: user, name: "System Merchant", slug: "sys_m")
    create(:merchant_rule, user: user, merchant: merchant_user, kind: "contains", field: "title", pattern: "BIEDRONKA", source: "user", priority: 0)
    create(:merchant_rule, user: user, merchant: merchant_llm,  kind: "contains", field: "title", pattern: "BIEDRONKA", source: "llm",  priority: 999)
    create(:merchant_rule, user: user, merchant: merchant_sys,  kind: "contains", field: "title", pattern: "BIEDRONKA", source: "system", priority: 999)
    tx = create(:bank_transaction, bank_account: account, title: "BIEDRONKA 1234")

    enrichment = described_class.call(tx, user: user)

    expect(enrichment.merchant).to eq(merchant_user)
    expect(enrichment.source).to eq("user_rule")
  end

  it "tie-breaks within the same source tier by priority DESC then id ASC" do
    user, account = setup_user_with_account
    merchant_a = create(:merchant, :system, user: user, name: "A", slug: "a_#{SecureRandom.hex(2)}")
    merchant_b = create(:merchant, :system, user: user, name: "B", slug: "b_#{SecureRandom.hex(2)}")
    rule_a = create(:merchant_rule, user: user, merchant: merchant_a, kind: "contains", field: "title", pattern: "X", source: "system", priority: 200)
    create(:merchant_rule, user: user, merchant: merchant_b, kind: "contains", field: "title", pattern: "X", source: "system", priority: 200)
    tx = create(:bank_transaction, bank_account: account, title: "match X here")

    enrichment = described_class.call(tx, user: user)

    expect(enrichment.merchant_rule_id).to eq(rule_a.id)
  end

  it "matches an IBAN rule with whitespace stripping and case folding on both sides" do
    user, account = setup_user_with_account
    merchant = create(:merchant, user: user, name: "M", slug: "m_#{SecureRandom.hex(2)}")
    create(:merchant_rule, user: user, merchant: merchant, kind: "iban", field: "counterparty_iban", pattern: "PL61 1090 1014 0000 0712 1981 2874", source: "user")
    tx = create(:bank_transaction, bank_account: account, counterparty_iban: "pl61109010140000071219812874")

    enrichment = described_class.call(tx, user: user)

    expect(enrichment.merchant).to eq(merchant)
  end

  it "skips a rule whose field is missing on the polymorphic enrichable (ManualTransaction has no counterparty_iban field — but title fallback applies)" do
    user, account = setup_user_with_account
    merchant = create(:merchant, user: user, name: "M", slug: "m")
    create(:merchant_rule, user: user, merchant: merchant, kind: "contains", field: "counterparty_iban", pattern: "x", source: "user")
    wallet = create(:bank_account, :cash, manual_owner: user, currency: "PLN")
    manual = create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN", title: "anything")

    enrichment = described_class.call(manual, user: user)

    expect(enrichment.merchant).to be_nil
    expect(enrichment.source).not_to eq("user_rule")
  end

  it "falls back to the payment_method/direction table when no rule matches" do
    user, account = setup_user_with_account
    tx = create(:bank_transaction, bank_account: account, payment_method: "blik_atm", direction: "debit", counterparty_kind: "external", title: "ATM withdrawal")

    enrichment = described_class.call(tx, user: user)

    expect(enrichment.source).to eq("system_fallback")
    expect(enrichment.category.path.to_s).to eq("money.transfers.atm")
  end

  it "uses the identity-aware fallback (transfer + counterparty_kind) over the plain payment_method table" do
    user, account = setup_user_with_account
    tx_self     = create(:bank_transaction, bank_account: account, payment_method: "transfer", direction: "debit", counterparty_kind: "self",     title: "Own move")
    tx_external = create(:bank_transaction, bank_account: account, payment_method: "transfer", direction: "credit", counterparty_kind: "external", title: "Salary")

    enrichment_self = described_class.call(tx_self, user: user)
    enrichment_external = described_class.call(tx_external, user: user)

    expect(enrichment_self.category.path.to_s).to eq("money.transfers.own")
    expect(enrichment_external.category.path.to_s).to eq("income.work.salary")
  end

  it "marks a transaction with no rule and no fallback path as source: unmatched, category nil" do
    user, account = setup_user_with_account
    tx = create(:bank_transaction, bank_account: account, payment_method: "card_authorization", direction: "credit", counterparty_kind: "unknown", title: "?")

    enrichment = described_class.call(tx, user: user)

    expect(enrichment.source).to eq("unmatched")
    expect(enrichment.category).to be_nil
    expect(enrichment.merchant).to be_nil
  end

  it "short-circuits a manual-source enrichment even when a matching rule exists (manual decision wins)" do
    user, account = setup_user_with_account
    merchant = create(:merchant, user: user, name: "M", slug: "m")
    create(:merchant_rule, user: user, merchant: merchant, kind: "contains", field: "title", pattern: "BIEDRONKA", source: "user")
    tx = create(:bank_transaction, bank_account: account, title: "BIEDRONKA 1234")
    create(:transaction_enrichment, enrichable: tx, source: "manual", category_overridden: false, merchant: nil, category: nil)

    enrichment = described_class.call(tx, user: user)

    expect(enrichment.source).to eq("manual")
    expect(enrichment.merchant).to be_nil
  end

  it "short-circuits a category_overridden=true enrichment even when a matching rule exists" do
    user, account = setup_user_with_account
    merchant = create(:merchant, user: user, name: "M", slug: "m")
    category_a = create(:category, user: user, name: "A", slug: "a_#{SecureRandom.hex(2)}", path: "a_#{SecureRandom.hex(2)}")
    create(:merchant_rule, user: user, merchant: merchant, kind: "contains", field: "title", pattern: "BIEDRONKA", source: "user")
    tx = create(:bank_transaction, bank_account: account, title: "BIEDRONKA 1234")
    create(:transaction_enrichment, enrichable: tx, source: "user_rule", category: category_a, category_overridden: true)

    enrichment = described_class.call(tx, user: user)

    expect(enrichment.category_overridden).to be(true)
    expect(enrichment.category).to eq(category_a)
    expect(enrichment.merchant_id).to be_nil
  end

  it "rebuild! re-evaluates non-manual non-overridden rows but skips manual and overridden ones (permutation 2)" do
    user, account = setup_user_with_account
    merchant = create(:merchant, user: user, name: "M", slug: "m")
    create(:merchant_rule, user: user, merchant: merchant, kind: "contains", field: "title", pattern: "BIEDRONKA", source: "user")

    rebuildable_tx = create(:bank_transaction, bank_account: account, title: "BIEDRONKA 1")
    manual_tx      = create(:bank_transaction, bank_account: account, title: "BIEDRONKA 2")
    overridden_tx  = create(:bank_transaction, bank_account: account, title: "BIEDRONKA 3")

    create(:transaction_enrichment, enrichable: rebuildable_tx, source: "system_fallback", merchant: nil)
    create(:transaction_enrichment, enrichable: manual_tx,      source: "manual",          merchant: nil)
    create(:transaction_enrichment, enrichable: overridden_tx,  source: "system_fallback", merchant: nil, category_overridden: true)

    described_class.rebuild!(user: user)

    expect(rebuildable_tx.reload.enrichment.merchant).to eq(merchant)
    expect(rebuildable_tx.enrichment.source).to eq("user_rule")
    expect(manual_tx.reload.enrichment.merchant).to be_nil
    expect(overridden_tx.reload.enrichment.merchant).to be_nil
  end

  it "enrich_pending writes one enrichment per scoped transaction without enrichment and returns the count" do
    user, account = setup_user_with_account
    raw_one = create(:bank_transaction, bank_account: account, payment_method: "blik_atm", direction: "debit", counterparty_kind: "external", title: "ATM 1")
    raw_two = create(:bank_transaction, bank_account: account, payment_method: "blik_atm", direction: "debit", counterparty_kind: "external", title: "ATM 2")
    already_done = create(:bank_transaction, bank_account: account, title: "Done")
    create(:transaction_enrichment, enrichable: already_done, source: "system_fallback")

    count = described_class.enrich_pending(user: user)

    expect(count).to eq(2)
    expect(raw_one.reload.enrichment).to be_present
    expect(raw_two.reload.enrichment).to be_present
  end
end
