# frozen_string_literal: true

FactoryBot.define do
  factory :sync_schedule do
    bank_connection { association :bank_connection, :active }
    enabled         { true }
    cadence         { "daily" }
    preferred_hour  { 8 }
    next_run_at     { 1.day.from_now }

    trait :active do
      enabled { true }
    end

    trait :paused do
      enabled       { false }
      paused_until  { 1.day.from_now }
    end

    trait :hourly do
      cadence { "daily" }
    end

    trait :daily do
      cadence { "daily" }
    end
  end
end
