# frozen_string_literal: true

# == Schema Information
#
# Table name: operation_runs
#
#  id                   :bigint           not null, primary key
#  error                :text
#  finished_at          :datetime
#  kind                 :string           not null
#  params               :jsonb            not null
#  scheduled_for        :datetime
#  started_at           :datetime
#  status               :string           default("queued"), not null
#  subject_type         :string
#  summary              :jsonb            not null
#  trigger              :string           default("manual"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  subject_id           :bigint
#  triggered_by_user_id :bigint           not null
#
# Indexes
#
#  index_operation_runs_on_created_at              (created_at)
#  index_operation_runs_on_kind                    (kind)
#  index_operation_runs_on_kind_and_status         (kind,status)
#  index_operation_runs_on_status                  (status)
#  index_operation_runs_on_subject                 (subject_type,subject_id)
#  index_operation_runs_on_triggered_by_user_id    (triggered_by_user_id)
#  index_operation_runs_scheduled_for_idempotency  (subject_type,subject_id,kind,scheduled_for) UNIQUE WHERE (scheduled_for IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (triggered_by_user_id => users.id)
#
require "rails_helper"

RSpec.describe OperationRun do
  it "transitions from queued to running and stamps started_at when start! is called" do
    run = create(:operation_run)

    freeze_time do
      run.start!
      expect(run.status).to eq("running")
      expect(run.started_at).to eq(Time.current)
      expect(run.finished_at).to be_nil
    end
  end

  it "marks the run succeeded with finished_at and persists the summary jsonb on succeed!" do
    run = create(:operation_run, :running, started_at: 1.minute.ago)

    freeze_time do
      run.succeed!(summary: { count: 5 })

      expect(run.status).to eq("succeeded")
      expect(run.finished_at).to eq(Time.current)
      expect(run.summary).to eq("count" => 5)
      expect(run).to be_terminal
    end
  end

  it "marks the run partial with both summary and error on mark_partial!" do
    run = create(:operation_run, :running, started_at: 1.minute.ago)

    run.mark_partial!(summary: { ok: 3, errors: 2 }, error: "partial sync")

    expect(run.status).to eq("partial")
    expect(run.summary).to eq("ok" => 3, "errors" => 2)
    expect(run.error).to eq("partial sync")
    expect(run.finished_at).to be_present
  end

  it "stringifies a non-string error argument on fail! using error.to_s" do
    run = create(:operation_run, :running, started_at: 1.minute.ago)

    run.fail!(error: StandardError.new("boom"))

    expect(run.status).to eq("failed")
    expect(run.error).to eq("boom")
    expect(run.finished_at).to be_present
  end

  it "returns terminal? true only for succeeded, partial, and failed statuses" do
    user = create(:user)
    statuses = OperationRun::STATUSES.index_with do |s|
      build(:operation_run, triggered_by_user: user, status: s).terminal?
    end

    expect(statuses).to eq(
      "queued"    => false,
      "running"   => false,
      "succeeded" => true,
      "partial"   => true,
      "failed"    => true
    )
  end

  it "computes duration_seconds as nil before start, positive while running, and (finished - started).to_i after finish" do
    user = create(:user)
    fresh    = build(:operation_run, triggered_by_user: user, started_at: nil, finished_at: nil)
    running  = build(:operation_run, triggered_by_user: user, started_at: 30.seconds.ago, finished_at: nil)
    finished = build(:operation_run, triggered_by_user: user, started_at: 60.seconds.ago, finished_at: 10.seconds.ago)

    expect(fresh.duration_seconds).to be_nil
    expect(running.duration_seconds).to be >= 30
    expect(finished.duration_seconds).to eq(50)
  end

  it "raises RecordNotUnique on a second scheduled run for the same (subject, kind, scheduled_for)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    slot = 1.hour.from_now.change(usec: 0)

    create(:operation_run, triggered_by_user: user, subject: connection, kind: "transaction_sync", scheduled_for: slot, trigger: "scheduled")

    expect {
      create(:operation_run, triggered_by_user: user, subject: connection, kind: "transaction_sync", scheduled_for: slot, trigger: "scheduled")
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows multiple non-scheduled runs with the same subject and kind (partial index excludes nil scheduled_for)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)

    create(:operation_run, triggered_by_user: user, subject: connection, kind: "transaction_sync", scheduled_for: nil)

    expect {
      create(:operation_run, triggered_by_user: user, subject: connection, kind: "transaction_sync", scheduled_for: nil)
    }.to change(described_class, :count).by(1)
  end

  it "resolves subject_label through to_breadcrumb, falls back to <Type>#<id> for unsupported subjects, and returns '-' for nil" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, bank_name: "Test Bank")
    schedule = create(:sync_schedule, bank_connection: connection)

    with_breadcrumb = build(:operation_run, triggered_by_user: user, subject: connection)
    nil_subject     = build(:operation_run, triggered_by_user: user, subject: nil)
    fallback_run    = build(:operation_run, triggered_by_user: user, subject: schedule)

    expect(with_breadcrumb.subject_label).to eq("Test Bank")
    expect(nil_subject.subject_label).to eq("-")
    expect(fallback_run.subject_label).to eq("SyncSchedule##{schedule.id}")
  end

  it "maps each status to the expected status_tone for the admin UI" do
    user = create(:user)
    tones = OperationRun::STATUSES.index_with do |s|
      build(:operation_run, triggered_by_user: user, status: s).status_tone
    end

    expect(tones).to eq(
      "queued"    => :muted,
      "running"   => :info,
      "succeeded" => :success,
      "partial"   => :warning,
      "failed"    => :destructive
    )
  end

  it "broadcasts progress only for kinds in STREAMED_KINDS on after_update_commit" do
    user = create(:user)
    streamed = create(:operation_run, triggered_by_user: user, kind: "transaction_sync", status: "queued")
    silent   = create(:operation_run, triggered_by_user: user, kind: "data_export", status: "queued")

    expect(streamed).to receive(:broadcast_replace_later_to).once
    expect(silent).not_to receive(:broadcast_replace_later_to)

    streamed.update!(status: "running", started_at: Time.current)
    silent.update!(status: "running", started_at: Time.current)
  end
end
