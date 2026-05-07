# frozen_string_literal: true

module Mcp
  module Tools
    module Merchants
      class Update < Mcp::ApplicationTool
        tool_name "merchants.update"
        description "Update editable fields of a merchant."

        input_schema(
          properties: {
            id:                  { type: "integer" },
            name:                { type: "string" },
            slug:                { type: "string" },
            kind:                { type: "string", enum: %w[company person unknown] },
            default_category_id: { type: "integer" },
            logo_url:            { type: "string" },
            notes:               { type: "string" }
          },
          required: %w[id]
        )

        def self.call(server_context:, **args)
          user = current_user(server_context)
          merchant = user.merchants.find_by(id: args[:id])
          return error("Merchant ##{args[:id]} not found.") unless merchant

          if merchant.update(args.symbolize_keys.except(:id))
            json(id: merchant.id, name: merchant.name, default_category_id: merchant.default_category_id)
          else
            error(merchant.errors.full_messages.join(", "))
          end
        end
      end
    end
  end
end
