# frozen_string_literal: true

module Mcp
  module Tools
    module Analytics
      class CashFlow < Mcp::ApplicationTool
        tool_name "analytics.cash_flow"
        description "Spend + income totals and a date-bucketed series for the requested period. Defaults to month-to-date."

        input_schema(
          properties: {
            from:        { type: "string", format: "date" },
            to:          { type: "string", format: "date" },
            bucket:      { type: "string", enum: %w[day week month] },
            currency:    { type: "string" },
            account_ids: { type: "array",  items: { type: "integer" } },
            under_path:  { type: "string", description: "ltree prefix" }
          }
        )

        def self.call(server_context:, **args)
          user   = current_user(server_context)
          filter = ::Analytics::Filter.new(user: user, params: args.deep_stringify_keys)

          totals = ::Analytics::CashFlow.totals(filter.scope)
          series = ::Analytics::CashFlow.series(filter.scope, period: filter.period, currency: filter.currency)

          json(
            currency: filter.currency,
            period:   { from: filter.period.from, to: filter.period.to, bucket: filter.period.bucket },
            totals:   totals,
            series:   series.map { |p|
              { date: p.date, spend_cents: p.spend_cents, income_cents: p.income_cents, net_cents: p.net_cents }
            }
          )
        end
      end
    end
  end
end
