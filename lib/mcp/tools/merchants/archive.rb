# frozen_string_literal: true

module Mcp
  module Tools
    module Merchants
      class Archive < Mcp::ApplicationTool
        tool_name "merchants.archive"
        description "Archive a merchant - keeps history visible, hides from active selectors."

        input_schema(properties: { id: { type: "integer" } }, required: %w[id])

        def self.call(server_context:, **args)
          user = current_user(server_context)
          merchant = user.merchants.find_by(id: args[:id])
          return error("Merchant ##{args[:id]} not found.") unless merchant

          merchant.update!(archived_at: Time.current)
          text("Archived merchant '#{merchant.name}'.")
        end
      end
    end
  end
end
