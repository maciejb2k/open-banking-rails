# frozen_string_literal: true

# RubyLLM configuration. Provider keys live in ENV; LLM_MODEL overrides the
# default model name so swapping versions touches only .env.
#
# Privacy note: only normalized titles + counterparty names are ever sent to
# the LLM provider — never amounts, IBANs, or account identifiers.
RubyLLM.configure do |config|
  config.openai_api_key  = ENV["OPENAI_API_KEY"]  if ENV["OPENAI_API_KEY"].present?
  config.gemini_api_key  = ENV["GEMINI_API_KEY"]  if ENV["GEMINI_API_KEY"].present?
  config.default_model   = ENV.fetch("LLM_MODEL", "gpt-4o-mini")
  config.request_timeout = 60
  config.max_retries     = 2
end
