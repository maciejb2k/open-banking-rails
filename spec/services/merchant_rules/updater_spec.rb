# frozen_string_literal: true

require "rails_helper"

RSpec.describe MerchantRules::Updater do
  it "applies the attributes and returns Result(success?: true) on a valid update" do
    user = create(:user)
    Seeders::Categories.call(user)
    rule = create(:merchant_rule, owner: user, pattern: "OLD")

    result = described_class.call(rule: rule, actor: user, attributes: { pattern: "NEW", priority: 50 })

    expect(result.success?).to be(true)
    expect(rule.reload).to have_attributes(pattern: "NEW", priority: 50)
  end

  it "triggers TransactionEnricher.rebuild! ONLY after a successful update (invariant: do not rebuild on validation failure)" do
    user = create(:user)
    Seeders::Categories.call(user)
    rule = create(:merchant_rule, owner: user)
    allow(Enrichment::TransactionEnricher).to receive(:rebuild!)

    described_class.call(rule: rule, actor: user, attributes: { pattern: "" })

    expect(Enrichment::TransactionEnricher).not_to have_received(:rebuild!)
  end

  it "returns Result(success?: false) with full error_messages when validation fails" do
    user = create(:user)
    Seeders::Categories.call(user)
    rule = create(:merchant_rule, owner: user)

    result = described_class.call(rule: rule, actor: user, attributes: { pattern: "" })

    expect(result.success?).to be(false)
    expect(result.error_messages).to be_present
    expect(result.error).to match(/Pattern/i)
  end

  it "accepts ActionController::Parameters-style hashes by symbolizing keys" do
    user = create(:user)
    Seeders::Categories.call(user)
    rule = create(:merchant_rule, owner: user, pattern: "OLD")

    result = described_class.call(rule: rule, actor: user, attributes: { "pattern" => "NEW" })

    expect(result.success?).to be(true)
    expect(rule.reload.pattern).to eq("NEW")
  end
end
