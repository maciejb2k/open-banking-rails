# frozen_string_literal: true

FactoryBot.define do
  factory :category do
    user
    sequence(:name) { |n| "Category #{n}" }
    sequence(:slug) { |n| "category_#{n}" }
    sequence(:path) { |n| "category_#{n}" }
    kind            { "expense" }
    color           { "emerald" }
    icon            { "tag" }
    essential       { false }
    position        { 0 }

    trait :spend do
      kind { "expense" }
    end

    trait :income do
      kind { "income" }
    end

    trait :transfer do
      kind { "transfer" }
    end

    trait :savings do
      kind { "savings" }
    end

    trait :ignore do
      kind { "ignored" }
    end

    trait :archived do
      archived_at { Time.current }
    end
  end
end
