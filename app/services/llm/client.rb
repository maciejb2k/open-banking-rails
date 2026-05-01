# frozen_string_literal: true

module Llm
  # Provider-agnostic interface for our LLM use cases. Each concrete client
  # (Llm::Clients::OpenAI, Llm::Clients::Gemini, eventually ::Anthropic, ::Ollama)
  # exposes the same shape. Callers depend on this — never on RubyLLM
  # directly — so swapping providers is a one-line change in the registry
  # (Llm::Providers::REGISTRY) and a per-user choice in Preferences.
  #
  # Methods raise Error on transport / parsing failure, NotConfiguredError
  # when the user hasn't set up an LLM provider yet (callers should redirect
  # to /admin/settings/preferences). Successful calls return plain Ruby
  # Hashes matching the documented schema.
  class Client
    Error             = Class.new(StandardError)
    NotConfiguredError = Class.new(Error)

    attr_reader :model, :api_key

    def initialize(api_key:, model:)
      @api_key = api_key
      @model   = model
    end

    # @param system_prompt [String]
    # @param user_prompt [String]
    # @param schema [Hash] JSON Schema (object) the response must conform to
    # @return [Hash] parsed structured response
    def structured(system_prompt:, user_prompt:, schema:)
      raise NotImplementedError
    end

    # Resolve the user's configured client. Raises NotConfiguredError when
    # no LlmSetting exists — every caller must catch this and surface a
    # "configure LLM in preferences" message rather than 500.
    def self.for(user:)
      setting = user.llm_setting
      unless setting&.configured?
        raise NotConfiguredError, "User has not configured an LLM provider — see /admin/settings/preferences"
      end

      setting.build_client
    end

    private

    # Build a per-call RubyLLM context with this client's api_key. Uses
    # `RubyLLM.context` (per-call config) so the global RubyLLM.configure
    # never holds keys — every request carries the right user's key without
    # mutating shared state.
    def ruby_llm_context
      key_setter = Llm::Providers::REGISTRY
                     .values
                     .find { |cfg| cfg[:client_class] == self.class.name }
                     &.dig(:config_key) ||
                   raise(Error, "Provider config missing for #{self.class.name}")

      RubyLLM.context do |config|
        config.public_send("#{key_setter}=", @api_key)
      end
    end
  end
end
