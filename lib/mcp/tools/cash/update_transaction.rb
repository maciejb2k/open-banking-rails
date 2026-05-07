# frozen_string_literal: true

module Mcp
  module Tools
    module Cash
      class UpdateTransaction < Mcp::ApplicationTool
        tool_name "cash.update_transaction"
        description "Update fields on an existing manual cash transaction. Currency is locked - delete and recreate to change it."

        input_schema(
          properties: {
            id:                { type: "integer" },
            amount:            { type: "string",  description: "Decimal, e.g. '12.50'. Omit to keep" },
            direction:         { type: "string",  enum: %w[debit credit] },
            booking_date:      { type: "string",  format: "date" },
            transaction_date:  { type: "string",  format: "date" },
            title:             { type: "string",  description: "Empty string clears" },
            note:              { type: "string",  description: "Empty string clears" },
            counterparty_name: { type: "string",  description: "Empty string clears" },
            merchant_id:       { type: "integer" },
            category_id:       { type: "integer" },
            payment_method:    { type: "string" }
          },
          required: %w[id]
        )

        def self.call(server_context:, **args)
          user = current_user(server_context)
          tx   = ::ManualTransaction.for_user(user).find_by(id: args[:id])
          return error("Manual transaction ##{args[:id]} not found.") unless tx
          return error("This transaction was auto-generated and isn't editable.") unless tx.source == "manual"

          input = ::Cash::TransactionUpdater::Input.new(**args.symbolize_keys.except(:id))
          result = ::Cash::TransactionUpdater.call(transaction: tx, input: input)

          from_result(result, on_success: ->(r) {
            json(id: r.transaction.id, amount_cents: r.transaction.amount_cents,
                 currency: r.transaction.currency, direction: r.transaction.direction,
                 booking_date: r.transaction.booking_date, title: r.transaction.title)
          })
        end
      end
    end
  end
end
