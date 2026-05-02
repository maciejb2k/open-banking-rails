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
class LlmSetting < ApplicationRecord
  # Per-user LLM credentials + model choice. Replaces the previous global
  # ENV-based config (OPENAI_API_KEY / GEMINI_API_KEY / LLM_MODEL) — every user
  # brings their own key, AI features fail loudly if not configured.
  #
  # Lookup of supported providers/models lives in Llm::Providers::REGISTRY,
  # so adding a vendor doesn't require touching this file.

  belongs_to :user

  encrypts :api_key

  validates :provider, presence: true, inclusion: { in: ->(_) { Llm::Providers.keys } }
  validates :api_key, presence: true
  validate :model_supported_by_provider

  before_validation :assign_default_model

  def configured?
    api_key.present?
  end

  def provider_config
    Llm::Providers.fetch(provider)
  end

  def provider_label
    provider_config[:label]
  end

  def effective_model
    model.presence || provider_config[:default_model]
  end

  # Build a ready-to-use Llm::Client (OpenAI/Gemini/...). The factory in
  # Llm::Client.for(user:) is the canonical entry point — most callers should
  # use that, not this method directly.
  def build_client
    klass = provider_config[:client_class].constantize
    klass.new(api_key: api_key, model: effective_model)
  end

  def record_test_success!
    update!(last_tested_at: Time.current, last_test_error: nil)
  end

  def record_test_failure!(message)
    update!(last_tested_at: Time.current, last_test_error: message.to_s.truncate(500))
  end

  private

  def model_supported_by_provider
    return if model.blank?
    return unless Llm::Providers.keys.include?(provider)
    return if provider_config[:models].include?(model)

    errors.add(:model, "is not supported by #{provider_label}")
  end

  def assign_default_model
    return if model.present?
    return unless Llm::Providers.keys.include?(provider)

    self.model = provider_config[:default_model]
  end
end
