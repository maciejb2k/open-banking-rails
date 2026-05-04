# frozen_string_literal: true

module Mcp
  module Tools
    module Transactions
      class List < Mcp::ApplicationTool
        tool_name "transactions.list"
        description "List ledger entries (bank + manual) with filters. Returns at most `limit` rows (default 25, max 200)."

        input_schema(
          properties: {
            from:           { type: "string", format: "date", description: "Booking date >=" },
            to:             { type: "string", format: "date", description: "Booking date <=" },
            direction:      { type: "string", enum: %w[credit debit] },
            status:         { type: "string", enum: %w[booked pending] },
            account_id:     { type: "integer" },
            merchant_id:    { type: "integer" },
            category_id:    { type: "integer" },
            category_path:  { type: "string", description: "ltree prefix; matches descendants" },
            payment_method: { type: "string" },
            currency:       { type: "string" },
            source_type:    { type: "string", enum: %w[BankTransaction ManualTransaction] },
            limit:          { type: "integer", description: "1-200, default 25" }
          }
        )

        def self.call(server_context:, **args)
          user  = current_user(server_context)
          limit = [ [ args[:limit].to_i, 1 ].max, 200 ].min
          limit = 25 if limit.zero?

          scope = ::LedgerEntry.for_user(user)
          scope = scope.where(booking_date: args[:from]..) if args[:from]
          scope = scope.where(booking_date: ..args[:to])   if args[:to]
          scope = scope.where(direction: args[:direction]) if args[:direction]
          scope = scope.where(status: args[:status])       if args[:status]
          scope = scope.where(bank_account_id: args[:account_id]) if args[:account_id]
          scope = scope.where(merchant_id: args[:merchant_id])    if args[:merchant_id]
          scope = scope.where(effective_category_id: args[:category_id]) if args[:category_id]
          scope = scope.under_path(args[:category_path]) if args[:category_path]
          scope = scope.where(payment_method: args[:payment_method]) if args[:payment_method]
          scope = scope.where(currency: args[:currency].to_s.upcase) if args[:currency]
          scope = scope.where(source_type: args[:source_type]) if args[:source_type]

          rows = scope.order(booking_date: :desc, source_id: :desc).limit(limit).map do |e|
            {
              source_type: e.source_type, source_id: e.source_id,
              booking_date: e.booking_date, direction: e.direction,
              amount_cents: e.amount_cents, currency: e.currency,
              title: e.title, counterparty_name: e.counterparty_name,
              merchant_id: e.merchant_id, category_path: e.category_path.to_s,
              payment_method: e.payment_method
            }
          end

          json(count: rows.size, transactions: rows)
        end
      end
    end
  end
end
