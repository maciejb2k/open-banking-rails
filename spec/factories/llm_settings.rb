# frozen_string_literal: true

# == Schema Information
#
# Table name: llm_settings
#
#  id              :bigint           not null, primary key
#  api_key         :text             not null
#  last_test_error :text
#  last_tested_at  :datetime
#  model           :string
#  provider        :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_llm_settings_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
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
