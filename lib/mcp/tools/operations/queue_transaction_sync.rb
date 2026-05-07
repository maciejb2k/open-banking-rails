# frozen_string_literal: true

module Mcp
  module Tools
    module Operations
      class QueueTransactionSync < Mcp::ApplicationTool
        tool_name "transaction_syncs.create"
        description "Queue a background transaction sync. Subject = a single bank connection (when bank_connection_id is given) or all of the user's active connections."

        input_schema(
          properties: {
            bank_connection_id: { type: "integer" },
            date_from:          { type: "string", format: "date" },
            date_to:            { type: "string", format: "date" }
          }
        )

        def self.call(server_context:, **args)
          user   = current_user(server_context)
          result = ::TransactionSyncs::Queuer.call(
            user:  user,
            input: ::TransactionSyncs::Queuer::Input.new(**args.symbolize_keys)
          )
          from_result(result, on_success: ->(r) {
            json(run_id: r.run.id, status: r.run.status, subject_type: r.run.subject_type, subject_id: r.run.subject_id)
          })
        end
      end
    end
  end
end
