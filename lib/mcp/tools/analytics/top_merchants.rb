# frozen_string_literal: true

module Mcp
  module Tools
    module Analytics
      class TopMerchants < Mcp::ApplicationTool
        tool_name "analytics.top_merchants"
        description "Top spend merchants for the period."

        input_schema(
          properties: {
            from:        { type: "string", format: "date" },
            to:          { type: "string", format: "date" },
            currency:    { type: "string" },
            account_ids: { type: "array",  items: { type: "integer" } },
            under_path:  { type: "string" },
            limit:       { type: "integer", description: "Default 10, max 50" }
          }
        )

        def self.call(server_context:, **args)
          user   = current_user(server_context)
          filter = ::Analytics::Filter.new(user: user, params: args.deep_stringify_keys)
          limit  = [ [ (args[:limit] || 10).to_i, 1 ].max, 50 ].min

          rows = ::Analytics::TopMerchants.call(filter.scope, user: user, currency: filter.currency, limit: limit)
          json(
            currency: filter.currency,
            period:   { from: filter.period.from, to: filter.period.to },
            rows: rows.map { |r|
              { merchant_id: r.merchant.id, merchant_name: r.merchant.name,
                merchant_slug: r.merchant.slug,
                amount_cents: r.amount_cents, count: r.count }
            }
          )
        end
      end
    end
  end
end
