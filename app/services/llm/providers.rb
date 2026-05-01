# frozen_string_literal: true

module Llm
  # Single source of truth for the LLM vendors this app supports.
  #
  # Adding a new vendor:
  #   1. Implement Llm::Clients::Foo (subclass of Llm::Client) — same shape as
  #      OpenAI / Gemini, accepting `api_key:` and `model:`.
  #   2. Add an entry below — that's it. The model layer (LlmSetting), the
  #      preferences UI (provider/model selects), and the factory all read
  #      from this hash.
  #
  # Keys:
  #   :label         — human-readable name shown in the UI
  #   :default_model — used when LlmSetting#model is blank
  #   :models        — allowed values for LlmSetting#model (used for validation
  #                    and the UI dropdown). Keep curated, not exhaustive —
  #                    a user picking a non-existent model only finds out at
  #                    request time, which is a worse failure mode.
  #   :client_class  — string-form to avoid load-order coupling
  #   :config_key    — RubyLLM config setter for the API key (so context can
  #                    set it per-call without touching the global config)
  module Providers
    REGISTRY = {
      "openai" => {
        label:         "OpenAI",
        default_model: "gpt-5-mini",
        # Curated for the merchant-classification workload (NER + enum
        # output). Order is recommended-first; the form select renders
        # in this order, and `default_model` is the first pick for new
        # accounts. We deliberately don't list `gpt-5` / full-tier or
        # `*-pro` models — classification is structured output over a
        # bounded enum, premium reasoning is wasted spend.
        #
        #   gpt-5-mini    — sweet spot. Modern reasoning, solid schema
        #                   following, ~$0.004 per 15-item batch.
        #   gpt-5-nano    — cheapest sane choice; slight accuracy hit on
        #                   long enum lists.
        #   gpt-5.4-mini  — escalation when 5-mini misclassifies. ~3x
        #                   pricier, noticeably better at obscure brands.
        #   gpt-5.4-nano  — newer nano iteration; comparable to 5-mini
        #                   at lower input cost.
        #   gpt-4.1-mini  — legacy decent option; kept for back-compat.
        #   gpt-4o-mini   — cheapest legacy; weakest at structured output.
        models:        %w[
          gpt-5-mini
          gpt-5-nano
          gpt-5.4-mini
          gpt-5.4-nano
          gpt-4.1-mini
          gpt-4o-mini
        ],
        client_class:  "Llm::Clients::OpenAI",
        config_key:    :openai_api_key
      },
      "gemini" => {
        label:         "Google Gemini",
        default_model: "gemini-2.5-flash",
        models:        %w[gemini-2.5-flash gemini-2.5-pro gemini-2.0-flash],
        client_class:  "Llm::Clients::Gemini",
        config_key:    :gemini_api_key
      }
    }.freeze

    def self.keys
      REGISTRY.keys
    end

    def self.fetch(provider)
      REGISTRY.fetch(provider) { raise ArgumentError, "Unknown LLM provider: #{provider.inspect}" }
    end

    def self.options_for_select
      REGISTRY.map { |key, cfg| [ cfg[:label], key ] }
    end

    # Per-provider model lists, keyed for the Stimulus cascade.
    def self.models_by_provider
      REGISTRY.transform_values { |cfg| cfg[:models] }
    end
  end
end
