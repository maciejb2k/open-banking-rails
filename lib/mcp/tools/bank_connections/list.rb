# frozen_string_literal: true

module Mcp
  module Tools
    module BankConnections
      class List < Mcp::ApplicationTool
        tool_name "bank_connections.list"
        description "List the user's bank connections with status + validity."

        input_schema(properties: { status: { type: "string" } })

        def self.call(server_context:, **args)
          user = current_user(server_context)
          scope = ::BankConnection.for_user(user)
          scope = scope.where(status: args[:status]) if args[:status]

          rows = scope.includes(:tpp_credential).order(valid_until: :asc).map do |c|
            { id: c.id, bank_name: c.bank_name, bank_country: c.bank_country,
              status: c.status, authorized_at: c.authorized_at,
              valid_until: c.valid_until, last_synced_at: c.last_synced_at,
              last_error: c.last_error }
          end
          json(count: rows.size, connections: rows)
        end
      end
    end
  end
end
