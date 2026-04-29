# frozen_string_literal: true

module Llm
  module Clients
    # OpenAI-flavored Llm::Client. Wraps RubyLLM exactly like the Gemini
    # client — same structured output via with_schema, same error contract.
    #
    # Recommended model: gpt-4o-mini (~$0.15/1M input tokens).
    # Supports JSON Schema structured output natively.
    class OpenAI < Llm::Client
      MAX_RETRIES = 4

      def initialize(model: nil)
        @model = model || ENV.fetch("LLM_MODEL", "gpt-4o-mini")
      end

      def structured(system_prompt:, user_prompt:, schema:)
        attempts = 0
        begin
          chat = RubyLLM.chat(model: @model)
                        .with_instructions(system_prompt)
                        .with_schema(schema)
          parse_content(chat.ask(user_prompt))
        rescue RubyLLM::RateLimitError => e
          attempts += 1
          raise Error, "OpenAI API error: #{e.class.name}: #{e.message}" if attempts > MAX_RETRIES

          wait = parse_retry_after(e.message)
          Rails.logger.info("[Llm::Clients::OpenAI] rate limited — retry #{attempts}/#{MAX_RETRIES} after #{wait}s")
          sleep wait
          retry
        rescue RubyLLM::Error => e
          raise Error, "OpenAI API error: #{e.class.name}: #{e.message}"
        rescue JSON::ParserError => e
          raise Error, "OpenAI returned non-JSON content: #{e.message}"
        end
      end

      private

      def parse_retry_after(message)
        if (m = message.match(/retry after (\d+)s/i))
          m[1].to_f + 1
        elsif (m = message.match(/please try again in ([\d.]+)s/i))
          m[1].to_f + 1
        else
          30.0
        end
      end

      def parse_content(message)
        content = message.respond_to?(:content) ? message.content : message
        return content if content.is_a?(Hash)
        return JSON.parse(content) if content.is_a?(String)
        raise Error, "Unexpected response shape from OpenAI: #{content.class}"
      end
    end
  end
end
