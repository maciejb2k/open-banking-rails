# frozen_string_literal: true

require "rails_helper"

RSpec.describe Seeders::MerchantRules do
  it "creates retail merchants and their title-contains rules at priority 0 keyed to a category path" do
    user = create(:user)
    Seeders::Categories.call(user)

    described_class.call(user)

    biedronka = user.merchants.find_by(slug: "biedronka")
    expect(biedronka).to be_present
    expect(biedronka.source).to eq("system")
    expect(biedronka.default_category.path.to_s).to eq("food.cooking.supermarket")
    rule = biedronka.merchant_rules.first
    expect(rule).to be_present
    expect(rule.field).to eq("title")
    expect(rule.kind).to eq("contains")
    expect(rule.pattern).to eq("BIEDRONKA")
    expect(rule.source).to eq("system")
  end

  it "creates the ATM system rule with priority 300 and an exact match on payment_method=blik_atm" do
    user = create(:user)
    Seeders::Categories.call(user)

    described_class.call(user)

    atm = user.merchants.find_by(slug: "atm_withdrawal")
    expect(atm.default_category.path.to_s).to eq("money.transfers.atm")
    rule = atm.merchant_rules.first
    expect(rule.field).to eq("payment_method")
    expect(rule.pattern).to eq("blik_atm")
    expect(rule.kind).to eq("exact")
    expect(rule.priority).to eq(300)
  end

  it "is idempotent: a second run does not create duplicate merchants or rules" do
    user = create(:user)
    Seeders::Categories.call(user)
    described_class.call(user)
    merchant_count_before = user.merchants.count
    rule_count_before = MerchantRule.where(user: user).count

    described_class.call(user)

    expect(user.merchants.count).to eq(merchant_count_before)
    expect(MerchantRule.where(user: user).count).to eq(rule_count_before)
  end
end
