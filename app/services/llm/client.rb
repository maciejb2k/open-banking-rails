# frozen_string_literal: true

module Llm
  # Callers depend on this, not on RubyLLM directly, so swapping providers is
  # a registry change. Methods raise Error on transport/parsing failure,
  # NotConfiguredError when no provider is set up.
  class Client
    Error             = Class.new(StandardError)
    NotConfiguredError = Class.new(Error)

    attr_reader :model, :api_key

    def initialize(api_key:, model:)
      @api_key = api_key
      @model   = model
    end

    def structured(system_prompt:, user_prompt:, schema:)
      raise NotImplementedError
    end

    # Callers must rescue NotConfiguredError and redirect to preferences,
    # not 500.
    def self.for(user:)
      setting = user.llm_setting
      unless setting&.configured?
        raise NotConfiguredError, "User has not configured an LLM provider - see /admin/settings/preferences"
      end

      setting.build_client
    end

    private

    # Per-call RubyLLM context so global config never holds keys - every
    # request carries the right user's key without mutating shared state.
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
