# frozen_string_literal: true

module Mcp
  class ApplicationTool < ::MCP::Tool
    class << self
      def current_user(server_context)
        server_context.fetch(:current_user)
      end

      def text(string)
        ::MCP::Tool::Response.new([ { type: "text", text: string.to_s } ])
      end

      def json(payload)
        ::MCP::Tool::Response.new([ { type: "text", text: payload.to_json } ])
      end

      def error(message)
        ::MCP::Tool::Response.new([ { type: "text", text: "Error: #{message}" } ], true)
      end

      def from_result(result, on_success:)
        if result.success?
          on_success.call(result)
        else
          error(result.respond_to?(:error) ? result.error : Array(result.error_messages).join(", "))
        end
      end
    end
  end
end
