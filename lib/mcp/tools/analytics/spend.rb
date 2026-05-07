# frozen_string_literal: true

module Mcp
  module Tools
    module Analytics
      class Spend < Mcp::ApplicationTool
        tool_name "analytics.spend"
        description "Spend breakdown by category path with previous-period delta. depth=1 → top-level, depth=2 → mid-level, omit for leaf rows."

        input_schema(
          properties: {
            from:        { type: "string", format: "date" },
            to:          { type: "string", format: "date" },
            currency:    { type: "string" },
            account_ids: { type: "array",  items: { type: "integer" } },
            under_path:  { type: "string" },
            depth:       { type: "integer" }
          }
        )

        def self.call(server_context:, **args)
          user   = current_user(server_context)
          filter = ::Analytics::Filter.new(user: user, params: args.deep_stringify_keys)

          rows = ::Analytics::SpendBreakdown.by_category(
            filter.scope,
            user:           user,
            currency:       filter.currency,
            depth:          args[:depth],
            previous_scope: filter.previous_scope
          )

          json(
            currency:    filter.currency,
            period:      { from: filter.period.from, to: filter.period.to },
            total_cents: rows.sum(&:amount_cents),
            rows: rows.map { |r|
              { path: r.path.to_s, name: r.name, amount_cents: r.amount_cents,
                prev_amount_cents: r.prev_amount_cents, count: r.count, delta_pct: r.delta_pct }
            }
          )
        end
      end
    end
  end
end
