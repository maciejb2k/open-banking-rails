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
require "rails_helper"

RSpec.describe LlmSetting do
  it "auto-assigns the provider's default model when model is blank" do
    setting = build(:llm_setting, provider: "gemini", model: nil)
    expect(setting).to be_valid
    expect(setting.model).to eq(Llm::Providers.fetch("gemini")[:default_model])
  end

  it "rejects a model that is not in the provider's allowlist with an error referencing the provider label" do
    setting = build(:llm_setting, provider: "gemini", model: "gpt-5-mini")
    expect(setting).not_to be_valid
    expect(setting.errors[:model].join).to include(Llm::Providers.fetch("gemini")[:label])
  end

  it "returns the explicit model from effective_model when set, else the provider default" do
    setting = build(:llm_setting, provider: "openai", model: "gpt-5-nano")
    expect(setting.effective_model).to eq("gpt-5-nano")

    setting.model = nil
    expect(setting.effective_model).to eq(Llm::Providers.fetch("openai")[:default_model])
  end

  it "truncates record_test_failure! messages to 500 characters and stamps last_tested_at" do
    setting = create(:llm_setting)
    long_error = "a" * 1000

    setting.record_test_failure!(long_error)

    expect(setting.last_test_error.length).to eq(500)
    expect(setting.last_tested_at).to be_within(2.seconds).of(Time.current)
  end

  it "clears last_test_error and stamps last_tested_at on record_test_success!" do
    setting = create(:llm_setting, last_test_error: "previous failure")

    setting.record_test_success!

    expect(setting.last_test_error).to be_nil
    expect(setting.last_tested_at).to be_within(2.seconds).of(Time.current)
  end

  it "round-trips api_key through Rails encryption with the raw column not containing the plaintext" do
    setting = create(:llm_setting, api_key: "sk-fake-secret-12345")
    setting.reload

    expect(setting.api_key).to eq("sk-fake-secret-12345")
    expect_encrypted_at_rest(setting, :api_key, "sk-fake-secret-12345")
  end
end
