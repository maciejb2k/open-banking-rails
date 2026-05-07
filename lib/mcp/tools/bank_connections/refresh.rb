# frozen_string_literal: true

module Mcp
  module Tools
    module BankConnections
      class Refresh < Mcp::ApplicationTool
        tool_name "bank_connections.refresh"
        description "Pull current status + validity for a bank connection from the provider."

        input_schema(properties: { id: { type: "integer" } }, required: %w[id])

        def self.call(server_context:, **args)
          user = current_user(server_context)
          connection = ::BankConnection.for_user(user).find_by(id: args[:id])
          return error("Bank connection ##{args[:id]} not found.") unless connection

          ::EnableBanking::Operations::RefreshConnection.call(connection)
          text("Refreshed: status=#{connection.reload.status}, valid_until=#{connection.valid_until&.to_date}.")
        rescue ::EnableBanking::Operations::RefreshConnection::Failed => e
          error("Refresh failed: #{e.message}")
        end
      end
    end
  end
end
