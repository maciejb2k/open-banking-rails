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
FactoryBot.define do
  factory :operation_run do
    triggered_by_user { association :user }
    kind    { "transaction_sync" }
    status  { "queued" }
    trigger { "manual" }
    params  { {} }
    summary { {} }

    trait :running do
      status     { "running" }
      started_at { Time.current }
    end

    trait :succeeded do
      status      { "succeeded" }
      started_at  { 1.minute.ago }
      finished_at { Time.current }
    end

    trait :failed do
      status      { "failed" }
      started_at  { 1.minute.ago }
      finished_at { Time.current }
      error       { "Simulated failure" }
    end

    trait :partial do
      status      { "partial" }
      started_at  { 1.minute.ago }
      finished_at { Time.current }
    end

    trait :sync do
      kind { "transaction_sync" }
    end

    trait :refresh_balances do
      kind { "balance_refresh" }
    end

    trait :create_connection do
      kind { "connection_refresh" }
    end
  end
end
