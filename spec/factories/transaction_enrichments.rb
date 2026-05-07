# frozen_string_literal: true

FactoryBot.define do
  factory :transaction_enrichment do
    enrichable { association :bank_transaction }
    source     { "system_rule" }
    confidence { 0.95 }
    enriched_at { Time.current }

    trait :rule do
      source { "system_rule" }
    end

    trait :llm do
      source     { "llm_rule" }
      confidence { 0.9 }
      model      { "gemini-2.5-flash" }
    end

    trait :manual do
      source              { "manual" }
      category_overridden { true }
      confidence          { 1.0 }
    end

    trait :high_confidence do
      confidence { 0.95 }
    end

    trait :low_confidence do
      confidence { 0.4 }
    end
  end
end
