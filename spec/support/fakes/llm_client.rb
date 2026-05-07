# frozen_string_literal: true

module Fakes
  # In-memory implementation of Llm::Client. Tests register canned responses
  # by prompt-substring (or regex) and the fake returns the first match for
  # each call. The shape mirrors what Llm::MerchantSuggester / EnrichmentRunner
  # expect: a parsed Hash from `structured(...)` keyed by the schema's
  # required fields.
  class LlmClient
    Error = Llm::Client::Error

    attr_reader :recorded_prompts, :recorded_models, :model

    def initialize(api_key: "fake-key", model: "fake-model")
      @api_key            = api_key
      @model              = model
      @canned_responses   = []
      @scheduled_failures = []
      @recorded_prompts   = []
      @recorded_models    = []
    end

    def structured(system_prompt:, user_prompt:, schema:)
      @recorded_prompts << { system: system_prompt, user: user_prompt, schema: schema }
      @recorded_models  << @model

      if (failure = @scheduled_failures.shift)
        raise Error, failure
      end

      match = @canned_responses.find { |entry| match?(entry[:matcher], system_prompt, user_prompt) }
      return match[:response].dup if match

      default_response_for(schema, user_prompt)
    end

    def respond_with(matcher: nil, response:)
      @canned_responses << { matcher: matcher, response: response }
    end

    def respond_with_schema(matcher: nil, structured:)
      respond_with(matcher: matcher, response: structured)
    end

    def respond_for_merchant_suggester(items:)
      respond_with(matcher: /Jesteś asystentem klasyfikującym/, response: { "results" => items })
    end

    def set_failure(message: "Simulated LLM failure")
      @scheduled_failures << message
    end

    def reset!
      @canned_responses.clear
      @scheduled_failures.clear
      @recorded_prompts.clear
      @recorded_models.clear
    end

    private

    def match?(matcher, system_prompt, user_prompt)
      return true if matcher.nil?
      blob = "#{system_prompt}\n#{user_prompt}"
      case matcher
      when Regexp then blob.match?(matcher)
      when String then blob.include?(matcher)
      else matcher.call(system_prompt, user_prompt)
      end
    end

    def default_response_for(schema, user_prompt)
      required = Array(schema[:required] || schema["required"])
      if required.include?("ok") && required.include?("echo")
        sent_at = user_prompt.to_s[/sent_at=(\S+)/, 1]
        return { "ok" => true, "echo" => sent_at.to_s }
      end

      if required.include?("results")
        return { "results" => [] }
      end

      {}
    end
  end
end
