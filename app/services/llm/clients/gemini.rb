# frozen_string_literal: true

module Llm
  module Clients
    class Gemini < Llm::Client
      def structured(system_prompt:, user_prompt:, schema:)
        chat = ruby_llm_context
                 .chat(model: @model)
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

      # Defensively handle Hash and raw JSON string - provider may wrap.
      def parse_content(message)
        content = message.respond_to?(:content) ? message.content : message
        return content if content.is_a?(Hash)
        return JSON.parse(content) if content.is_a?(String)
        raise Error, "Unexpected response shape from Gemini: #{content.class}"
      end
    end
  end
end
