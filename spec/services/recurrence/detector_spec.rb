# frozen_string_literal: true

require "rails_helper"

RSpec.describe Recurrence::Detector do
  def setup_user_with_merchant
    user = create(:user)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp, currency: "PLN")
    spend_category = user.categories.find_by(path: "food.cooking.supermarket")
    merchant = create(:merchant, user: user, name: "Recurring Co.", slug: "recurring_co_#{SecureRandom.hex(2)}", default_category: spend_category)
    [ user, account, merchant, spend_category ]
  end

  def seed_charge(user, account, merchant, category, on:, amount_cents:)
    tx = create(:bank_transaction, bank_account: account, amount_cents: amount_cents, currency: "PLN", direction: "debit", payment_method: "card", booking_date: on, transaction_date: on)
    create(:transaction_enrichment, enrichable: tx, source: "system_rule", merchant: merchant, category: category, category_overridden: false)
    tx
  end

  it "marks a stable monthly merchant's enrichments as recurring with interval monthly and returns the count" do
    user, account, merchant, category = setup_user_with_merchant
    today = Date.new(2026, 5, 7)

    travel_to(today) do
      [ today - 90.days, today - 60.days, today - 30.days ].each do |on|
        seed_charge(user, account, merchant, category, on: on, amount_cents: 100_00)
      end

      stats = described_class.call(user: user, lookback_days: 365)

      expect(stats[:monthly]).to eq(3)
      enrichments = TransactionEnrichment.for_user(user).where(merchant: merchant)
      expect(enrichments.all? { |e| e.recurring && e.recurrence_interval == "monthly" }).to be(true)
    end
  end

  it "skips a merchant with fewer than MIN_OCCURRENCES charges (skipped_short)" do
    user, account, merchant, category = setup_user_with_merchant
    today = Date.new(2026, 5, 7)

    travel_to(today) do
      [ today - 60.days, today - 30.days ].each do |on|
        seed_charge(user, account, merchant, category, on: on, amount_cents: 100_00)
      end

      stats = described_class.call(user: user, lookback_days: 365)

      expect(stats[:skipped_short]).to eq(1)
      expect(stats.values_at(:weekly, :monthly, :yearly).compact.sum).to eq(0)
      expect(TransactionEnrichment.for_user(user).where(recurring: true).count).to eq(0)
    end
  end

  it "skips a merchant whose intervals don't cluster into a canonical bucket (skipped_irregular)" do
    user, account, merchant, category = setup_user_with_merchant
    today = Date.new(2026, 5, 7)

    travel_to(today) do
      [ today - 100.days, today - 80.days, today - 50.days, today - 5.days ].each do |on|
        seed_charge(user, account, merchant, category, on: on, amount_cents: 100_00)
      end

      stats = described_class.call(user: user, lookback_days: 365)

      expect(stats[:skipped_irregular]).to eq(1)
    end
  end

  it "skips a merchant whose amounts vary beyond AMOUNT_CV_MAX (skipped_unstable)" do
    user, account, merchant, category = setup_user_with_merchant
    today = Date.new(2026, 5, 7)

    travel_to(today) do
      [ [ today - 90.days, 50_00 ], [ today - 60.days, 250_00 ], [ today - 30.days, 800_00 ] ].each do |(on, cents)|
        seed_charge(user, account, merchant, category, on: on, amount_cents: cents)
      end

      stats = described_class.call(user: user, lookback_days: 365)

      expect(stats[:skipped_unstable]).to eq(1)
    end
  end

  it "ignores manual-source and category_overridden enrichments when marking the merchant's rows" do
    user, account, merchant, category = setup_user_with_merchant
    today = Date.new(2026, 5, 7)

    travel_to(today) do
      txs = [ today - 90.days, today - 60.days, today - 30.days ].map do |on|
        seed_charge(user, account, merchant, category, on: on, amount_cents: 100_00)
      end

      txs[0].enrichment.update!(source: "manual")
      txs[1].enrichment.update!(category_overridden: true)

      described_class.call(user: user, lookback_days: 365)

      expect(txs[0].enrichment.reload.recurring).to be(false)
      expect(txs[1].enrichment.reload.recurring).to be(false)
      expect(txs[2].enrichment.reload.recurring).to be(true)
    end
  end

  it "detects yearly interval at the 365±7-day bucket boundary" do
    user, account, merchant, category = setup_user_with_merchant
    today = Date.new(2026, 5, 7)

    travel_to(today) do
      [ today - 730.days, today - 365.days, today - 1.day ].each do |on|
        seed_charge(user, account, merchant, category, on: on, amount_cents: 100_00)
      end

      stats = described_class.call(user: user, lookback_days: 800)

      expect(stats[:yearly]).to be >= 1
    end
  end
end
