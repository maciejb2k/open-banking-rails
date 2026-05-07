# frozen_string_literal: true

require "rails_helper"

RSpec.describe Enrichment::ClassificationApplier do
  def setup_user_with_tx
    user = create(:user)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp, currency: "PLN")
    tx = create(:bank_transaction, bank_account: account, title: "BIEDRONKA 1234")
    create(:transaction_enrichment, enrichable: tx, source: "system_fallback")
    [ user, tx ]
  end

  it "applies :only_this with merchant + category, writing source manual and category_overridden true" do
    user, tx = setup_user_with_tx
    merchant = create(:merchant, user: user, name: "Biedronka", slug: "biedronka")
    category = create(:category, user: user, name: "Groceries", slug: "groceries_#{SecureRandom.hex(2)}", path: "groceries_#{SecureRandom.hex(2)}")
    input = described_class::Input.new(mode: :only_this, merchant: merchant, category: category)

    result = described_class.call(transaction: tx, input: input, actor: user)

    expect(result).to be_success
    enrichment = tx.reload.enrichment
    expect(enrichment.source).to eq("manual")
    expect(enrichment.category_overridden).to be(true)
    expect(enrichment.merchant).to eq(merchant)
    expect(enrichment.category).to eq(category)
    expect(enrichment.merchant_rule_id).to be_nil
  end

  it "applies :only_this with merchant but no category, leaving category_overridden false (follows category presence)" do
    user, tx = setup_user_with_tx
    merchant = create(:merchant, user: user, name: "Biedronka", slug: "biedronka")
    input = described_class::Input.new(mode: :only_this, merchant: merchant, category: nil)

    described_class.call(transaction: tx, input: input, actor: user)

    enrichment = tx.reload.enrichment
    expect(enrichment.source).to eq("manual")
    expect(enrichment.category_overridden).to be(false)
    expect(enrichment.category).to be_nil
  end

  it "applies :all_for_merchant: updates merchant.default_category and pivots the row to user_rule with category_overridden false" do
    user, tx = setup_user_with_tx
    merchant = create(:merchant, user: user, name: "Biedronka", slug: "biedronka", default_category: nil)
    category = create(:category, user: user, name: "Groceries", slug: "groceries_#{SecureRandom.hex(2)}", path: "groceries_#{SecureRandom.hex(2)}")
    input = described_class::Input.new(mode: :all_for_merchant, merchant: merchant, category: category)

    described_class.call(transaction: tx, input: input, actor: user)

    expect(merchant.reload.default_category).to eq(category)
    enrichment = tx.reload.enrichment
    expect(enrichment.source).to eq("user_rule")
    expect(enrichment.merchant).to eq(merchant)
    expect(enrichment.category).to be_nil
    expect(enrichment.category_overridden).to be(false)
    expect(enrichment.effective_category).to eq(category)
  end

  it "applies :create_rule: builds a user-source MerchantRule and rebuilds matching transactions retroactively" do
    user, tx = setup_user_with_tx
    merchant = create(:merchant, user: user, name: "Biedronka", slug: "biedronka")
    category = create(:category, user: user, name: "Groceries", slug: "groceries_#{SecureRandom.hex(2)}", path: "groceries_#{SecureRandom.hex(2)}")

    sibling_tx = create(:bank_transaction, bank_account: tx.bank_account, title: "BIEDRONKA Sibling")
    create(:transaction_enrichment, enrichable: sibling_tx, source: "system_fallback")

    input = described_class::Input.new(mode: :create_rule, merchant: merchant, category: category, rule_field: "title", rule_kind: "contains", rule_pattern: "BIEDRONKA")
    described_class.call(transaction: tx, input: input, actor: user)

    rule = MerchantRule.last
    expect(rule.source).to eq("user")
    expect(rule.priority).to eq(100)
    expect(rule.enabled).to be(true)
    expect(rule.approved_by).to eq(user)
    expect(merchant.reload.default_category).to eq(category)

    expect(sibling_tx.reload.enrichment.merchant).to eq(merchant)
    expect(sibling_tx.enrichment.source).to eq("user_rule")
  end

  it "fails with 'Pick a merchant' when mode is not :only_this and merchant is nil" do
    user, tx = setup_user_with_tx
    input = described_class::Input.new(mode: :all_for_merchant, merchant: nil, category: nil)

    result = described_class.call(transaction: tx, input: input, actor: user)

    expect(result).not_to be_success
    expect(result.message).to eq("Pick a merchant")
  end

  it "fails with 'Pick a pattern' when mode is :create_rule and rule_pattern is blank" do
    user, tx = setup_user_with_tx
    merchant = create(:merchant, user: user, name: "M", slug: "m_#{SecureRandom.hex(2)}")
    input = described_class::Input.new(mode: :create_rule, merchant: merchant, category: nil, rule_pattern: "")

    result = described_class.call(transaction: tx, input: input, actor: user)

    expect(result).not_to be_success
    expect(result.message).to eq("Pick a pattern")
  end

  it "fails with 'Unknown propagation mode' for an invalid mode" do
    user, tx = setup_user_with_tx
    input = described_class::Input.new(mode: :wibble, merchant: nil)

    result = described_class.call(transaction: tx, input: input, actor: user)

    expect(result).not_to be_success
    expect(result.message).to start_with("Unknown propagation mode")
  end
end
