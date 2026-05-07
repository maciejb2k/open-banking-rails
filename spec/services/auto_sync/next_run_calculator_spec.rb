# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutoSync::NextRunCalculator do
  def input(cadence: "daily", preferred_hour: 8, timezone: "UTC", from: Time.current, jitter: 0..0)
    described_class::Input.new(cadence: cadence, preferred_hour: preferred_hour, timezone: timezone, from: from, jitter: jitter)
  end

  it "snaps a first-fire baseline to the preferred hour on the same day when from is before the slot" do
    from = Time.utc(2026, 5, 7, 6, 30)

    result = described_class.call(input: input(preferred_hour: 8, from: from))

    expect(result).to eq(Time.utc(2026, 5, 7, 8, 0))
  end

  it "rolls a first-fire baseline to the next day when from is past the preferred hour" do
    from = Time.utc(2026, 5, 7, 9, 30)

    result = described_class.call(input: input(preferred_hour: 8, from: from))

    expect(result).to eq(Time.utc(2026, 5, 8, 8, 0))
  end

  it "honors the per-cadence interval when last_dispatched_at is supplied (daily)" do
    from = Time.utc(2026, 5, 7, 7, 0)
    last = Time.utc(2026, 5, 7, 8, 0)

    result = described_class.call(input: input(cadence: "daily", preferred_hour: 8, from: from), last_dispatched_at: last)

    expect(result).to eq(Time.utc(2026, 5, 8, 8, 0))
  end

  it "honors the weekly interval, snapping last + 7d to the preferred hour" do
    from = Time.utc(2026, 5, 7, 7, 0)
    last = Time.utc(2026, 5, 7, 8, 0)

    result = described_class.call(input: input(cadence: "weekly", preferred_hour: 8, from: from), last_dispatched_at: last)

    expect(result).to eq(Time.utc(2026, 5, 14, 8, 0))
  end

  it "uses max(from, last + interval) so a long downtime fires once on recovery (not a backlog)" do
    last = Time.utc(2026, 1, 1, 8, 0)
    from = Time.utc(2026, 5, 7, 6, 0)

    result = described_class.call(input: input(cadence: "daily", preferred_hour: 8, from: from), last_dispatched_at: last)

    expect(result).to eq(Time.utc(2026, 5, 7, 8, 0))
  end

  it "raises ArgumentError for an unknown cadence string when last_dispatched_at is supplied" do
    expect {
      described_class.call(input: input(cadence: "hourly"), last_dispatched_at: 1.hour.ago)
    }.to raise_error(ArgumentError, /Unknown cadence/)
  end

  it "applies a jitter offset capped by the supplied range" do
    fixed_from = Time.utc(2026, 5, 7, 6, 0)
    base = described_class.call(input: input(preferred_hour: 8, from: fixed_from, jitter: 0..0))
    jittered = described_class.call(input: input(preferred_hour: 8, from: fixed_from, jitter: 5..5))

    expect(jittered - base).to eq(5)
  end

  it "evaluates from_time and snap in the configured time zone" do
    warsaw = ActiveSupport::TimeZone.new("Europe/Warsaw")
    from = warsaw.local(2026, 5, 7, 6, 0)

    result = described_class.call(input: input(timezone: "Europe/Warsaw", preferred_hour: 8, from: from))

    expect(result.in_time_zone(warsaw)).to eq(warsaw.local(2026, 5, 7, 8, 0))
  end
end
