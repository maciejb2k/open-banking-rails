# frozen_string_literal: true

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
