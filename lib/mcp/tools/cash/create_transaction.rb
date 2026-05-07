# frozen_string_literal: true

module Mcp
  module Tools
    module Cash
      class CreateTransaction < Mcp::ApplicationTool
        tool_name "cash.create_transaction"
        description "Record a manual cash transaction (income or expense) for the current user."

        input_schema(
          properties: {
            amount:            { type: "string",  description: "Decimal amount, e.g. '12.50'" },
            currency:          { type: "string",  description: "ISO-4217, defaults to PLN" },
            direction:         { type: "string",  enum: %w[debit credit], description: "Defaults to debit (expense)" },
            booking_date:      { type: "string",  format: "date" },
            transaction_date:  { type: "string",  format: "date" },
            title:             { type: "string" },
            note:              { type: "string" },
            counterparty_name: { type: "string" },
            merchant_id:       { type: "integer" },
            category_id:       { type: "integer" },
            payment_method:    { type: "string", description: "cash / card / blik_p2p / transfer / other" }
          },
          required: %w[amount]
        )

        def self.call(server_context:, **args)
          user   = current_user(server_context)
          input  = ::Cash::TransactionCreator::Input.new(**args.symbolize_keys)
          result = ::Cash::TransactionCreator.call(user: user, input: input)

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
