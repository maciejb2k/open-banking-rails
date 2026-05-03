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
class OperationRun < ApplicationRecord
  # `kind` discriminates; `params`/`summary` are kind-specific jsonb.
  # The contract for each kind lives in code (the owning operation/job).

  KINDS = %w[
    transaction_sync
    balance_refresh
    connection_refresh
    account_details_refresh
    llm_enrichment
    llm_connection_test
    data_export
    data_import
  ].freeze

  STATUSES = %w[queued running succeeded partial failed].freeze
  TRIGGERS = %w[manual scheduled].freeze
  TERMINAL_STATUSES = %w[succeeded partial failed].freeze

  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :triggered_by_user, class_name: "User"

  validates :kind,    presence: true, inclusion: { in: KINDS }
  validates :status,  presence: true, inclusion: { in: STATUSES }
  validates :trigger, presence: true, inclusion: { in: TRIGGERS }

  # Other kinds don't have a show page; broadcasting without a `_run_progress`
  # partial would enqueue failing render jobs.
  STREAMED_KINDS = %w[transaction_sync llm_enrichment].freeze

  after_update_commit :broadcast_progress, if: -> { STREAMED_KINDS.include?(kind) }

  scope :recent,        -> { order(created_at: :desc) }
  scope :running,       -> { where(status: "running") }
  scope :queued,        -> { where(status: "queued") }
  scope :terminal,      -> { where(status: TERMINAL_STATUSES) }
  scope :of_kind,       ->(k) { where(kind: k) }
  scope :triggered_by,  ->(user) { where(triggered_by_user: user) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[id kind status trigger subject_type subject_id triggered_by_user_id
       started_at finished_at created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[subject triggered_by_user]
  end

  def start!
    update!(status: "running", started_at: Time.current)
  end

  def succeed!(summary: nil)
    finish!("succeeded", summary: summary)
  end

  def mark_partial!(summary: nil, error: nil)
    finish!("partial", summary: summary, error: error)
  end

  def fail!(error:, summary: nil)
    finish!("failed", summary: summary, error: error.to_s)
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def running?
    status == "running"
  end

  def queued?
    status == "queued"
  end

  def duration_seconds
    return nil if started_at.nil?
    end_time = finished_at || Time.current
    (end_time - started_at).to_i
  end

  def status_tone
    case status
    when "succeeded" then :success
    when "running"   then :info
    when "queued"    then :muted
    when "partial"   then :warning
    when "failed"    then :destructive
    else :muted
    end
  end

  def subject_label
    return "-" if subject.nil?
    %i[to_breadcrumb display_name email name].each do |m|
      return subject.public_send(m) if subject.respond_to?(m) && subject.public_send(m).present?
    end
    "#{subject_type}##{subject_id}"
  end

  private

  def broadcast_progress
    broadcast_replace_later_to(
      "operation_run_#{id}",
      target: ActionView::RecordIdentifier.dom_id(self, :progress),
      partial: "admin/#{kind.pluralize}/run_progress",
      locals: { run: self }
    )
  end

  def finish!(new_status, summary: nil, error: nil)
    attrs = { status: new_status, finished_at: Time.current }
    attrs[:summary] = summary if summary
    attrs[:error] = error if error
    update!(attrs)
  end
end
