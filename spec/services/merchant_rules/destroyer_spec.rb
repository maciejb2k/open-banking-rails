# frozen_string_literal: true

require "rails_helper"

RSpec.describe MerchantRules::Destroyer do
  it "destroys the rule and returns Result(success?: true)" do
    user = create(:user)
    Seeders::Categories.call(user)
    rule = create(:merchant_rule, owner: user)

    result = described_class.call(rule: rule, actor: user)

    expect(result.success?).to be(true)
    expect(MerchantRule.exists?(rule.id)).to be(false)
  end

  it "triggers TransactionEnricher.rebuild! after destroying so historical enrichments tied to the rule re-resolve" do
    user = create(:user)
    Seeders::Categories.call(user)
    rule = create(:merchant_rule, owner: user)
    allow(Enrichment::TransactionEnricher).to receive(:rebuild!)

    described_class.call(rule: rule, actor: user)

    expect(Enrichment::TransactionEnricher).to have_received(:rebuild!).with(user: user)
  end
end
