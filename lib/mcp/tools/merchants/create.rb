# frozen_string_literal: true

module Mcp
  module Tools
    module Merchants
      class Create < Mcp::ApplicationTool
        tool_name "merchants.create"
        description "Create a user-source merchant. Slug auto-generated when omitted."

        input_schema(
          properties: {
            name:                { type: "string" },
            slug:                { type: "string" },
            kind:                { type: "string", enum: %w[company person unknown] },
            default_category_id: { type: "integer" },
            logo_url:            { type: "string" },
            notes:               { type: "string" }
          },
          required: %w[name]
        )

        def self.call(server_context:, **args)
          user   = current_user(server_context)
          result = ::Merchants::Creator.call(user: user, attributes: args)
          from_result(result, on_success: ->(r) {
            json(id: r.merchant.id, name: r.merchant.name, slug: r.merchant.slug,
                 default_category_id: r.merchant.default_category_id)
          })
        end
      end
    end
  end
end
