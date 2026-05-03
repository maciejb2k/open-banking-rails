# frozen_string_literal: true

module Llm
  # client_class is string-form to avoid load-order coupling. config_key is
  # the RubyLLM config setter for the API key (per-call, never global).
  module Providers
    REGISTRY = {
      "openai" => {
        label:         "OpenAI",
        default_model: "gpt-5-mini",
        # Curated, recommended-first. No premium-tier models - classification
        # is bounded enum output, premium reasoning is wasted spend.
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

    def self.models_by_provider
      REGISTRY.transform_values { |cfg| cfg[:models] }
    end
  end
end
