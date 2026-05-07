# frozen_string_literal: true

module Mcp
  module Tools
    module Merchants
      class Approve < Mcp::ApplicationTool
        tool_name "merchants.approve"
        description "Approve an LLM-suggested merchant. Enables its disabled rules and rebuilds enrichment for the user."

        input_schema(properties: { id: { type: "integer" } }, required: %w[id])

        def self.call(server_context:, **args)
          user = current_user(server_context)
          merchant = user.merchants.find_by(id: args[:id])
          return error("Merchant ##{args[:id]} not found.") unless merchant

          ::Merchants::Approver.call(merchant: merchant, actor: user)
          text("Approved '#{merchant.name}' and re-classified historical transactions.")
        end
      end
    end
  end
end
