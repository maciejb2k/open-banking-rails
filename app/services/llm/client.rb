# frozen_string_literal: true

module Llm
  # Provider-agnostic interface for our LLM use cases. Each concrete client
  # (Llm::Clients::Gemini, eventually Llm::Clients::Anthropic, ::Ollama)
  # exposes the same shape. Callers depend on this — never on RubyLLM
  # directly — so swapping providers is a one-line change in the factory.
  #
  # Methods raise Error on transport / parsing failure. Successful calls
  # return plain Ruby Hashes matching the documented schema.
  class Client
    Error = Class.new(StandardError)

    # @param system_prompt [String]
    # @param user_prompt [String]
    # @param schema [Hash] JSON Schema (object) the response must conform to
    # @return [Hash] parsed structured response
    def structured(system_prompt:, user_prompt:, schema:)
      raise NotImplementedError
    end

    # Tiny factory — picks the configured provider. Centralized here so
    # tests can stub `Llm::Client.default` and prod swaps Gemini → Anthropic
    # via initializer.
    def self.default
      @default ||= Llm::Clients::OpenAI.new
    end

    # Drop-in replacement for testing or one-off scripts.
    def self.with_default(client)
      previous = @default
      @default = client
      yield
    ensure
      @default = previous
    end
  end
end
