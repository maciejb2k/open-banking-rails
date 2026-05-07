# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutoSync::Dispatcher do
  it "enqueues a TransactionSyncJob and an OperationRun for each due, authorized schedule" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized")
    create(:sync_schedule, bank_connection: connection, enabled: true, next_run_at: 1.minute.ago)

    queued_jobs_before = Sidekiq::Worker.jobs.size
    expect {
      result = described_class.call
      expect(result.examined).to eq(1)
      expect(result.dispatched).to eq(1)
      expect(result.skipped).to eq(0)
    }.to change(OperationRun, :count).by(1)

    expect(Sidekiq::Worker.jobs.size - queued_jobs_before).to eq(1)
    run = OperationRun.last
    expect(run.kind).to eq(TransactionSyncJob::KIND)
    expect(run.trigger).to eq("scheduled")
    expect(run.subject).to eq(connection)
  end

  it "does not dispatch and applies REVOKED_BACKOFF when the connection is no longer authorized" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "revoked")
    schedule = create(:sync_schedule, bank_connection: connection, enabled: true, next_run_at: 1.minute.ago, paused_until: nil)

    result = described_class.call

    expect(result.dispatched).to eq(0)
    expect(result.skipped).to eq(1)
    expect(OperationRun.count).to eq(0)
    expect(schedule.reload.paused_until).to be_within(1.minute).of(described_class::REVOKED_BACKOFF.from_now)
  end

  it "advances next_run_at and stamps last_dispatched_at after a successful dispatch" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized")
    schedule = create(:sync_schedule, bank_connection: connection, enabled: true, next_run_at: 1.minute.ago, last_dispatched_at: nil)
    before_call = Time.current

    described_class.call

    schedule.reload
    expect(schedule.last_dispatched_at).to be_within(1.minute).of(before_call)
    expect(schedule.next_run_at).to be > before_call
  end

  it "skips a second tick racing the same slot via the partial UNIQUE on operation_runs (idempotency, permutation 1)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized")
    slot = 1.minute.ago.change(usec: 0)
    create(:sync_schedule, bank_connection: connection, enabled: true, next_run_at: slot)
    create(:operation_run, triggered_by_user: user, subject: connection, kind: TransactionSyncJob::KIND, scheduled_for: slot, trigger: "scheduled")

    expect {
      result = described_class.call
      expect(result.examined).to eq(1)
      expect(result.dispatched).to eq(0)
      expect(result.skipped).to eq(1)
    }.not_to change(OperationRun, :count)
  end

  it "ignores schedules where enabled is false even when next_run_at is overdue" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized")
    create(:sync_schedule, bank_connection: connection, enabled: false, next_run_at: 1.minute.ago)

    result = described_class.call

    expect(result.examined).to eq(0)
    expect(result.dispatched).to eq(0)
  end
end
