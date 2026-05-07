# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.test" }
    name             { "Test User" }
    password         { "Password123!" }
    track_cash       { false }

    trait :without_llm do
      after(:create) { |u| u.llm_setting&.destroy }
    end

    trait :cash_on do
      track_cash { true }
    end
  end
end
