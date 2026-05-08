# frozen_string_literal: true

require "rails_helper"

RSpec.describe Merchants::Approver do
  it "stamps approved_at and approved_by on the merchant and returns Result(success?: true)" do
    user = create(:user)
    Seeders::Categories.call(user)
    merchant = create(:merchant, user: user, source: "llm", approved_at: nil, approved_by: nil)

    result = described_class.call(merchant: merchant, actor: user)

    expect(result.success?).to be(true)
    expect(result.merchant).to eq(merchant)
    expect(merchant.reload.approved_at).to be_present
    expect(merchant.approved_by).to eq(user)
  end

  it "approves and enables every pending LLM-sourced rule under the merchant" do
    user = create(:user)
    Seeders::Categories.call(user)
    merchant = create(:merchant, user: user, source: "llm", approved_at: nil)
    pending_rule = create(:merchant_rule, owner: user, merchant: merchant, source: "llm", enabled: false, approved_at: nil)
    user_rule    = create(:merchant_rule, owner: user, merchant: merchant, source: "user", enabled: true)

    described_class.call(merchant: merchant, actor: user)

    expect(pending_rule.reload).to have_attributes(enabled: true, approved_at: be_present, approved_by: user)
    expect(user_rule.reload.approved_at).to be_nil
  end

  it "skips llm rules that are already enabled (idempotency on re-approval)" do
    user = create(:user)
    Seeders::Categories.call(user)
    merchant = create(:merchant, user: user, source: "llm", approved_at: 1.day.ago)
    already_enabled = create(:merchant_rule, owner: user, merchant: merchant, source: "llm", enabled: true, approved_at: 1.day.ago)
    original_approval = already_enabled.approved_at

    described_class.call(merchant: merchant, actor: user)

    expect(already_enabled.reload.approved_at.to_i).to eq(original_approval.to_i)
  end

  it "triggers TransactionEnricher.rebuild! after approval (so historical tx pick up the now-enabled rules)" do
    user = create(:user)
    Seeders::Categories.call(user)
    merchant = create(:merchant, user: user, source: "llm", approved_at: nil)
    allow(Enrichment::TransactionEnricher).to receive(:rebuild!)

    described_class.call(merchant: merchant, actor: user)

    expect(Enrichment::TransactionEnricher).to have_received(:rebuild!).with(user: user)
  end
end
