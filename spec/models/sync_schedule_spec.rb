# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSchedule do
  it "treats a NULL next_run_at as due alongside past timestamps and excludes future ones" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    conn_a = create(:bank_connection, tpp_credential: tpp)
    conn_b = create(:bank_connection, tpp_credential: tpp)
    conn_c = create(:bank_connection, tpp_credential: tpp)

    never_run = create(:sync_schedule, bank_connection: conn_a, enabled: true, next_run_at: nil, paused_until: nil)
    overdue   = create(:sync_schedule, bank_connection: conn_b, enabled: true, next_run_at: 1.minute.ago, paused_until: nil)
    future    = create(:sync_schedule, bank_connection: conn_c, enabled: true, next_run_at: 1.day.from_now, paused_until: nil)

    due_ids = described_class.due.pluck(:id)
    expect(due_ids).to include(never_run.id, overdue.id)
    expect(due_ids).not_to include(future.id)
  end

  it "excludes paused schedules from due when paused_until is in the future" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    conn_a = create(:bank_connection, tpp_credential: tpp)
    conn_b = create(:bank_connection, tpp_credential: tpp)
    conn_c = create(:bank_connection, tpp_credential: tpp)

    paused      = create(:sync_schedule, bank_connection: conn_a, enabled: true, next_run_at: 1.minute.ago, paused_until: 1.day.from_now)
    pause_lifted = create(:sync_schedule, bank_connection: conn_b, enabled: true, next_run_at: 1.minute.ago, paused_until: 1.minute.ago)
    never_paused = create(:sync_schedule, bank_connection: conn_c, enabled: true, next_run_at: 1.minute.ago, paused_until: nil)

    due_ids = described_class.due.pluck(:id)
    expect(due_ids).to include(pause_lifted.id, never_paused.id)
    expect(due_ids).not_to include(paused.id)
  end

  it "excludes any schedule where enabled is false regardless of timestamps" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    conn = create(:bank_connection, tpp_credential: tpp)

    disabled = create(:sync_schedule, bank_connection: conn, enabled: false, next_run_at: 1.minute.ago, paused_until: nil)

    expect(described_class.due.pluck(:id)).not_to include(disabled.id)
  end

  it "returns paused? false for blank or past paused_until and true for future" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    conn_a = create(:bank_connection, tpp_credential: tpp)
    conn_b = create(:bank_connection, tpp_credential: tpp)
    conn_c = create(:bank_connection, tpp_credential: tpp)

    blank   = create(:sync_schedule, bank_connection: conn_a, paused_until: nil)
    past    = create(:sync_schedule, bank_connection: conn_b, paused_until: 1.minute.ago)
    future  = create(:sync_schedule, bank_connection: conn_c, paused_until: 1.minute.from_now)

    expect(blank).not_to be_paused
    expect(past).not_to be_paused
    expect(future).to be_paused
  end

  it "validates preferred_hour as integer in 0..23 and rejects floats and out-of-range values" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    conn = create(:bank_connection, tpp_credential: tpp)

    [ 0, 23 ].each do |hour|
      ok = build(:sync_schedule, bank_connection: conn, preferred_hour: hour)
      expect(ok).to be_valid, "preferred_hour=#{hour.inspect} should pass"
    end

    [ -1, 24 ].each do |hour|
      bad = build(:sync_schedule, bank_connection: conn, preferred_hour: hour)
      expect(bad).not_to be_valid, "preferred_hour=#{hour.inspect} should fail"
      expect(bad.errors[:preferred_hour]).to be_present
    end

    fractional = build(:sync_schedule, bank_connection: conn, preferred_hour: 12.5)
    expect(fractional).not_to be_valid
    expect(fractional.errors[:preferred_hour]).to include("must be an integer")
  end

  it "rejects a negative consecutive_failures and a non-CADENCES cadence value" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    conn = create(:bank_connection, tpp_credential: tpp)

    bad_failures = build(:sync_schedule, bank_connection: conn, consecutive_failures: -1)
    expect(bad_failures).not_to be_valid
    expect(bad_failures.errors[:consecutive_failures]).to be_present

    bad_cadence = build(:sync_schedule, bank_connection: conn, cadence: "hourly")
    expect(bad_cadence).not_to be_valid
    expect(bad_cadence.errors[:cadence]).to include("is not included in the list")
  end

  it "raises RecordNotUnique when a second schedule is added for the same bank_connection" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    conn = create(:bank_connection, tpp_credential: tpp)
    create(:sync_schedule, bank_connection: conn)

    expect {
      create(:sync_schedule, bank_connection: conn)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
