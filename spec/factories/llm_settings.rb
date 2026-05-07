# frozen_string_literal: true

FactoryBot.define do
  factory :llm_setting do
    user
    provider { "gemini" }
    api_key  { "fake-gemini-key" }
    model    { "gemini-2.5-flash" }

    trait :openai do
      provider { "openai" }
      api_key  { "fake-openai-key" }
      model    { "gpt-5-mini" }
    end

    trait :gemini do
      provider { "gemini" }
      api_key  { "fake-gemini-key" }
      model    { "gemini-2.5-flash" }
    end

    trait :invalid do
      provider { "gemini" }
      api_key  { "" }
      model    { "gemini-2.5-flash" }
      to_create { |instance| instance.save(validate: false) }
    end
  end
end
