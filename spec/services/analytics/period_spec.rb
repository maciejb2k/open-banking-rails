# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::Period do
  it "rejects an unsupported bucket and a from > to range with ArgumentError" do
    expect { described_class.new(from: Date.today, to: Date.today, bucket: :hour) }.to raise_error(ArgumentError, /bucket/)
    expect { described_class.new(from: Date.today, to: Date.today - 1, bucket: :day) }.to raise_error(ArgumentError, /from/)
  end

  it "computes length_days inclusively and previous as the same-length window ending the day before from" do
    period = described_class.new(from: Date.new(2026, 5, 1), to: Date.new(2026, 5, 7))

    expect(period.length_days).to eq(7)
    expect(period.previous.from).to eq(Date.new(2026, 4, 24))
    expect(period.previous.to).to eq(Date.new(2026, 4, 30))
  end

  it "buckets returns one date per day for :day bucket" do
    period = described_class.new(from: Date.new(2026, 5, 1), to: Date.new(2026, 5, 3))

    expect(period.buckets).to eq([ Date.new(2026, 5, 1), Date.new(2026, 5, 2), Date.new(2026, 5, 3) ])
  end

  it "buckets steps by week starting at beginning_of_week, by month starting at beginning_of_month" do
    weekly = described_class.new(from: Date.new(2026, 5, 4), to: Date.new(2026, 5, 24), bucket: :week)
    monthly = described_class.new(from: Date.new(2026, 1, 15), to: Date.new(2026, 4, 10), bucket: :month)

    expect(weekly.buckets.first).to eq(Date.new(2026, 5, 4).beginning_of_week)
    expect(weekly.buckets.length).to eq(3)
    expect(monthly.buckets).to eq([ Date.new(2026, 1, 1), Date.new(2026, 2, 1), Date.new(2026, 3, 1), Date.new(2026, 4, 1) ])
  end

  it "fill maps a sparse series onto every bucket with the supplied default" do
    period = described_class.new(from: Date.new(2026, 5, 1), to: Date.new(2026, 5, 3))
    series = { Date.new(2026, 5, 2) => 100 }

    expect(period.fill(series, default: 0)).to eq([
      { bucket: Date.new(2026, 5, 1), value: 0 },
      { bucket: Date.new(2026, 5, 2), value: 100 },
      { bucket: Date.new(2026, 5, 3), value: 0 }
    ])
  end

  it "last_n_days returns a period ending today and starting n-1 days back" do
    travel_to(Date.new(2026, 5, 7)) do
      period = described_class.last_n_days(7)
      expect(period.from).to eq(Date.new(2026, 5, 1))
      expect(period.to).to eq(Date.new(2026, 5, 7))
      expect(period.length_days).to eq(7)
    end
  end
end
