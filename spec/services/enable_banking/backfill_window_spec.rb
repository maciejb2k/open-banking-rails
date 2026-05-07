# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::BackfillWindow do
  it "exposes per-bank horizons for revolut, pko_bank_polski, and mbank" do
    expect(described_class.days_for("revolut")).to eq(90)
    expect(described_class.days_for("pko_bank_polski")).to eq(26 * 30)
    expect(described_class.days_for("mbank")).to eq(90)
  end

  it "falls back to DEFAULT_DAYS for unknown bank slugs and nil" do
    expect(described_class.days_for("unknown_bank")).to eq(described_class::DEFAULT_DAYS)
    expect(described_class.days_for(nil)).to eq(described_class::DEFAULT_DAYS)
  end

  it "computes default_date_from as today minus the per-bank horizon" do
    today = Date.new(2026, 1, 1)

    expect(described_class.default_date_from("pko_bank_polski", today: today)).to eq(today - (26 * 30).days)
    expect(described_class.default_date_from("revolut", today: today)).to eq(today - 90.days)
  end

  it "uses Date.current as the default reference point for default_date_from" do
    travel_to(Date.new(2026, 5, 7)) do
      expect(described_class.default_date_from("revolut")).to eq(Date.new(2026, 5, 7) - 90.days)
    end
  end
end
