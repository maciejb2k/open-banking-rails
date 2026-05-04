# frozen_string_literal: true

module Mcp
  module Tools
    module Operations
      class QueueLlmEnrichment < Mcp::ApplicationTool
        tool_name "llm_enrichments.create"
        description "Queue an LLM enrichment run. The user must have an LLM provider configured in Preferences."

        input_schema(
          properties: {
            limit: { type: "integer", description: "Max distinct title groups to send to the LLM" }
          }
        )

        def self.call(server_context:, **args)
          user   = current_user(server_context)
          result = ::LlmEnrichments::Queuer.call(
            user:  user,
            input: ::LlmEnrichments::Queuer::Input.new(limit: args[:limit])
          )
          from_result(result, on_success: ->(r) { json(run_id: r.run.id, status: r.run.status) })
        end
      end
    end
  end
end
