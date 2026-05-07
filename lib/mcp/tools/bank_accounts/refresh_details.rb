# frozen_string_literal: true

module Mcp
  module Tools
    module BankAccounts
      class RefreshDetails < Mcp::ApplicationTool
        tool_name "bank_accounts.refresh_details"
        description "Pull fresh account-info from the AISP provider (name, holder, product). Live API call."

        input_schema(properties: { id: { type: "integer" } }, required: %w[id])

        def self.call(server_context:, **args)
          user    = current_user(server_context)
          account = ::BankAccount.where(id: user.all_bank_account_ids).find_by(id: args[:id])
          return error("Bank account ##{args[:id]} not found.") unless account

          ::EnableBanking::Operations::RefreshAccountDetails.call(account)
          text("Account details refreshed for ##{account.id}.")
        rescue ::EnableBanking::Operations::RefreshAccountDetails::Failed => e
          error("Refresh failed: #{e.message}")
        end
      end
    end
  end
end
