# frozen_string_literal: true

FactoryBot.define do
  factory :merchant do
    user
    sequence(:name) { |n| "Merchant #{n}" }
    sequence(:slug) { |n| "merchant_#{n}" }
    source          { "user" }
    kind            { "company" }

    trait :system do
      source      { "system" }
      approved_at { Time.current }
    end

    trait :user_source do
      source      { "user" }
      approved_at { Time.current }
    end

    trait :llm do
      source     { "llm" }
      confidence { 0.9 }
      model      { "gemini-2.5-flash" }
    end

    trait :with_default_category do
      default_category { association :category, user: user }
    end
  end
end
