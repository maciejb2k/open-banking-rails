# frozen_string_literal: true

# RubyLLM transport defaults. Provider keys are NOT set here — they live on
# LlmSetting (per-user, encrypted) and are bound per-call via
# `RubyLLM.context` inside Llm::Clients::*. Keeping the global config
# key-less means a misconfigured user can never accidentally use someone
# else's quota.
#
# Privacy note: only normalized titles + counterparty names are ever sent to
# the LLM provider — never amounts, IBANs, or account identifiers.
RubyLLM.configure do |config|
  config.request_timeout = 60
  config.max_retries     = 2
end
