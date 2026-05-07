# frozen_string_literal: true

require "rails_helper"

RSpec.describe MerchantRule do
  it "matches contains case-insensitively by default and respects case_sensitive: true" do
    user = create(:user)
    merchant = create(:merchant, user: user)
    insensitive = build(:merchant_rule, owner: user, merchant: merchant, kind: "contains", field: "title", pattern: "żabka", case_sensitive: false)
    sensitive   = build(:merchant_rule, owner: user, merchant: merchant, kind: "contains", field: "title", pattern: "żabka", case_sensitive: true)

    expect(insensitive.matches?("Żabka 123")).to be(true)
    expect(sensitive.matches?("Żabka 123")).to be(false)
  end

  it "matches iban with whitespace stripped and both sides upcased" do
    user = create(:user)
    merchant = create(:merchant, user: user)
    rule = build(:merchant_rule, owner: user, merchant: merchant, kind: "iban", field: "counterparty_iban", pattern: "pl1234567890")

    expect(rule.matches?("PL12 3456 7890")).to be(true)
    expect(rule.matches?("PL99 0000 0000")).to be(false)
  end

  it "matches regex against the value, returns false on a blank value, and uses ignorecase when not case_sensitive" do
    user = create(:user)
    merchant = create(:merchant, user: user)
    insensitive = build(:merchant_rule, owner: user, merchant: merchant, kind: "regex", field: "title", pattern: 'INVOICE \d{4}-\d{2}', case_sensitive: false)
    sensitive   = build(:merchant_rule, owner: user, merchant: merchant, kind: "regex", field: "title", pattern: 'INVOICE \d{4}-\d{2}', case_sensitive: true)

    expect(insensitive.matches?("invoice 2024-01")).to be(true)
    expect(sensitive.matches?("invoice 2024-01")).to be(false)
    expect(insensitive.matches?("")).to be(false)
    expect(insensitive.matches?(nil)).to be(false)
  end

  it "matches exact case-insensitively by default and respects case_sensitive: true" do
    user = create(:user)
    merchant = create(:merchant, user: user)
    insensitive = build(:merchant_rule, owner: user, merchant: merchant, kind: "exact", field: "payment_method", pattern: "PAYDAY", case_sensitive: false)
    sensitive   = build(:merchant_rule, owner: user, merchant: merchant, kind: "exact", field: "payment_method", pattern: "PAYDAY", case_sensitive: true)

    expect(insensitive.matches?("payday")).to be(true)
    expect(sensitive.matches?("payday")).to be(false)
  end

  it "rejects an invalid regex pattern with a :pattern error and accepts a non-regex rule with the same string" do
    user = create(:user)
    merchant = create(:merchant, user: user)

    bad_regex = build(:merchant_rule, owner: user, merchant: merchant, kind: "regex", field: "title", pattern: "[")
    expect(bad_regex).not_to be_valid
    expect(bad_regex.errors[:pattern].first).to start_with("is not a valid regex:")

    contains_rule = build(:merchant_rule, owner: user, merchant: merchant, kind: "contains", field: "title", pattern: "[")
    expect(contains_rule).to be_valid
  end

  it "ranks sources user > llm > system and returns -1 for unknown values" do
    user = create(:user)
    merchant = create(:merchant, user: user)
    user_rule   = build(:merchant_rule, owner: user, merchant: merchant, source: "user")
    llm_rule    = build(:merchant_rule, owner: user, merchant: merchant, source: "llm")
    system_rule = build(:merchant_rule, owner: user, merchant: merchant, source: "system")
    unknown     = build(:merchant_rule, owner: user, merchant: merchant, source: "user").tap { |r| r.source = "mystery" }

    expect(user_rule.source_rank).to eq(2)
    expect(llm_rule.source_rank).to eq(1)
    expect(system_rule.source_rank).to eq(0)
    expect(unknown.source_rank).to eq(-1)
  end

  it "validates the confidence boundary at 0.0..1.0 and accepts nil" do
    user = create(:user)
    merchant = create(:merchant, user: user)
    accepted = [ 0.0, 1.0, nil ].map { |c| build(:merchant_rule, owner: user, merchant: merchant, confidence: c) }
    rejected = [ -0.01, 1.01 ].map { |c| build(:merchant_rule, owner: user, merchant: merchant, confidence: c) }

    accepted.each { |r| expect(r).to be_valid, "confidence=#{r.confidence.inspect} should pass" }
    rejected.each do |r|
      expect(r).not_to be_valid, "confidence=#{r.confidence.inspect} should fail"
      expect(r.errors[:confidence]).to be_present
    end
  end
end
