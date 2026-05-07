# frozen_string_literal: true

require "rails_helper"

RSpec.describe Merchant do
  it "auto-generates a slug from the name, stripping diacritics and collapsing non-alphanumerics" do
    user = create(:user)

    zabka = build(:merchant, user: user, name: "Żabka Polska", slug: nil)
    cafe  = build(:merchant, user: user, name: "Café & Co.", slug: nil)

    zabka.valid?
    cafe.valid?

    expect(zabka.slug).to eq("zabka_polska")
    expect(cafe.slug).to eq("cafe_co")
  end

  it "falls back to merchant_<hex> when slug normalization yields a blank string" do
    user = create(:user)
    record = build(:merchant, user: user, name: "@@@", slug: nil)

    record.valid?
    expect(record.slug).to match(/\Amerchant_[0-9a-f]{8}\z/)
  end

  it "preserves a pre-set slug instead of overwriting it" do
    user = create(:user)
    record = build(:merchant, user: user, name: "Whatever", slug: "custom")
    record.valid?
    expect(record.slug).to eq("custom")
  end

  it "scopes slug uniqueness per user (different users can share, same user cannot)" do
    user_a = create(:user)
    user_b = create(:user)
    create(:merchant, user: user_a, name: "Żabka", slug: "zabka")
    expect { create(:merchant, user: user_b, name: "Żabka", slug: "zabka") }.to change(described_class, :count).by(1)

    duplicate = build(:merchant, user: user_a, name: "Other", slug: "zabka")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:slug]).to include("has already been taken")
  end

  it "validates the confidence boundary at 0.0..1.0 and accepts nil" do
    user = create(:user)

    accepted = [ 0.0, 1.0, nil ].map { |c| build(:merchant, user: user, confidence: c) }
    rejected = [ -0.5, 1.01 ].map { |c| build(:merchant, user: user, confidence: c) }

    accepted.each { |m| expect(m).to be_valid, "confidence=#{m.confidence.inspect} should pass" }
    rejected.each do |m|
      expect(m).not_to be_valid, "confidence=#{m.confidence.inspect} should fail"
      expect(m.errors[:confidence]).to be_present
    end
  end

  it "limits the pending scope to llm-sourced rows that have not been approved" do
    user = create(:user)
    pending_llm  = create(:merchant, :llm, user: user, name: "Pending LLM", slug: "pending_llm")
    approved_llm = create(:merchant, :llm, user: user, name: "Approved LLM", slug: "approved_llm", approved_at: Time.current)
    user_pending = create(:merchant, user: user, name: "User Pending", slug: "user_pending", source: "user", approved_at: nil)

    ids = described_class.pending.pluck(:id)
    expect(ids).to contain_exactly(pending_llm.id)
    expect(ids).not_to include(approved_llm.id, user_pending.id)
  end

  it "nullifies dependent transaction_enrichment.merchant_id when the merchant is destroyed" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user, currency: "PLN")
    record = create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN")
    merchant = create(:merchant, user: user)
    enrichment = create(:transaction_enrichment, enrichable: record, merchant: merchant, source: "user_rule")

    merchant.destroy
    expect(enrichment.reload.merchant_id).to be_nil
  end
end
