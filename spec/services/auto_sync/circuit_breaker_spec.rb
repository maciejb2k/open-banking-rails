# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutoSync::CircuitBreaker do
  it "is a no-op for manual-trigger runs even when the run failed" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    schedule = create(:sync_schedule, bank_connection: connection, consecutive_failures: 0)
    run = create(:operation_run, :failed, triggered_by_user: user, subject: connection, trigger: "manual")

    described_class.observe(run: run)

    expect(schedule.reload.consecutive_failures).to eq(0)
    expect(schedule.paused_until).to be_nil
  end

  it "is a no-op for non-terminal runs (queued, running)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    schedule = create(:sync_schedule, bank_connection: connection, consecutive_failures: 2)
    run = create(:operation_run, :running, triggered_by_user: user, subject: connection, trigger: "scheduled")

    described_class.observe(run: run)

    expect(schedule.reload.consecutive_failures).to eq(2)
  end

  it "resets consecutive_failures and paused_until to clean state on a scheduled success" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    schedule = create(:sync_schedule, bank_connection: connection, consecutive_failures: 2, paused_until: 5.minutes.from_now)
    run = create(:operation_run, :succeeded, triggered_by_user: user, subject: connection, trigger: "scheduled")

    described_class.observe(run: run)

    expect(schedule.reload.consecutive_failures).to eq(0)
    expect(schedule.paused_until).to be_nil
  end

  it "increments consecutive_failures on a scheduled non-success below the failure threshold" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    schedule = create(:sync_schedule, bank_connection: connection, consecutive_failures: 1, paused_until: nil)
    run = create(:operation_run, :failed, triggered_by_user: user, subject: connection, trigger: "scheduled")

    described_class.observe(run: run)

    expect(schedule.reload.consecutive_failures).to eq(2)
    expect(schedule.paused_until).to be_nil
  end

  it "trips the breaker by setting paused_until once consecutive_failures reaches FAILURE_THRESHOLD" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    schedule = create(:sync_schedule, bank_connection: connection, consecutive_failures: SyncSchedule::FAILURE_THRESHOLD - 1, paused_until: nil)
    run = create(:operation_run, :failed, triggered_by_user: user, subject: connection, trigger: "scheduled")

    described_class.observe(run: run)

    schedule.reload
    expect(schedule.consecutive_failures).to eq(SyncSchedule::FAILURE_THRESHOLD)
    expect(schedule.paused_until).to be_within(1.minute).of(described_class::COOLDOWN.from_now)
  end

  it "is a no-op when the run's subject is not a BankConnection" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    schedule = create(:sync_schedule, bank_connection: connection)
    run = create(:operation_run, :failed, triggered_by_user: user, subject: schedule, trigger: "scheduled")

    expect {
      described_class.observe(run: run)
    }.not_to change { schedule.reload.consecutive_failures }
  end
end
