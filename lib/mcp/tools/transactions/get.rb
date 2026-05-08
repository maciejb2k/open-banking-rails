# frozen_string_literal: true

module Mcp
  module Tools
    module Transactions
      class Get < Mcp::ApplicationTool
        tool_name "transactions.get"
        description "Fetch a single ledger entry by source type + id."

        input_schema(
          properties: {
            source_type: { type: "string", enum: %w[BankTransaction ManualTransaction] },
            source_id:   { type: "integer" }
          },
          required: %w[source_type source_id]
        )

        def self.call(server_context:, **args)
          user = current_user(server_context)
          entry = ::LedgerEntry.for_user(user).find_by(source_type: args[:source_type], source_id: args[:source_id])
          return error("Transaction not found.") unless entry

          json(
            source_type: entry.source_type, source_id: entry.source_id,
            booking_date: entry.booking_date, transaction_date: entry.transaction_date,
            direction: entry.direction, status: entry.status,
            amount_cents: entry.amount_cents, currency: entry.currency,
            title: entry.title, counterparty_name: entry.counterparty_name,
            counterparty_kind: entry.counterparty_kind,
            payment_method: entry.payment_method,
            merchant_id: entry.merchant_id,
            effective_category_id: entry.effective_category_id,
            category_path: entry.category_path.to_s,
            essential: entry.essential,
            enrichment_source: entry.enrichment_source
          )
        end
      end
    end
  end
end
