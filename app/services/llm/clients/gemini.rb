# frozen_string_literal: true

module Llm
  module Clients
    # Gemini-flavored Llm::Client. Thin wrapper over RubyLLM — all the
    # provider-specific quirks (model name, structured output via
    # responseSchema, key in env) are encapsulated here.
    #
    # Uses RubyLLM's `with_schema` to enforce JSON Schema on the response —
    # we get back a parsed Hash, not free-form text, so callers don't need
    # to handle markdown fences or hallucinated prose.
    class Gemini < Llm::Client
      def initialize(model: nil)
        @model = model || ENV.fetch("LLM_MODEL", "gemini-2.5-flash")
      end

      def structured(system_prompt:, user_prompt:, schema:)
        chat = RubyLLM.chat(model: @model)
                      .with_instructions(system_prompt)
                      .with_schema(schema)

        response = chat.ask(user_prompt)
        parse_content(response)
      rescue RubyLLM::Error => e
        raise Error, "Gemini API error: #{e.class.name}: #{e.message}"
      rescue JSON::ParserError => e
        raise Error, "Gemini returned non-JSON content: #{e.message}"
      end

      private

      # RubyLLM::Message exposes parsed content for structured responses on
      # `.content` (Hash when schema is set) — but defensively handle both
      # the parsed Hash and a raw JSON string in case provider wraps it.
      def parse_content(message)
        content = message.respond_to?(:content) ? message.content : message
        return content if content.is_a?(Hash)
        return JSON.parse(content) if content.is_a?(String)
        raise Error, "Unexpected response shape from Gemini: #{content.class}"
      end
    end
  end
end
