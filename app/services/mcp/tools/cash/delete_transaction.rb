# frozen_string_literal: true

module Mcp
  module Tools
    module Cash
      class DeleteTransaction < Mcp::ApplicationTool
        tool_name "cash.delete_transaction"
        description "Delete a manual cash transaction. Auto-generated rows (e.g. ATM linker) cannot be deleted here."

        input_schema(
          properties: { id: { type: "integer" } },
          required: %w[id]
        )

        def self.call(server_context:, **args)
          user = current_user(server_context)
          tx   = ::ManualTransaction.for_user(user).find_by(id: args[:id])
          return error("Manual transaction ##{args[:id]} not found.") unless tx
          return error("This transaction was auto-generated and isn't deletable.") unless tx.source == "manual"

          tx.destroy!
          text("Deleted manual transaction ##{args[:id]}.")
        end
      end
    end
  end
end
