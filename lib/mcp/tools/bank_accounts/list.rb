# frozen_string_literal: true

module Mcp
  module Tools
    module BankAccounts
      class List < Mcp::ApplicationTool
        tool_name "bank_accounts.list"
        description "List the user's bank accounts (synced from AISP) and cash wallets (manual=true)."

        input_schema(
          properties: {
            manual: { type: "boolean", description: "true → only cash wallets, false → only synced. Omit for both." }
          }
        )

        def self.call(server_context:, **args)
          user  = current_user(server_context)
          scope = ::BankAccount.where(id: user.all_bank_account_ids)
          scope = scope.where(manual: args[:manual]) if args.key?(:manual) && !args[:manual].nil?

          rows = scope.order(:created_at).map do |a|
            { id: a.id, name: a.name, iban: a.iban, currency: a.currency,
              status: a.status, manual: a.manual, product: a.product,
              balances_synced_at: a.balances_synced_at,
              transactions_synced_at: a.transactions_synced_at,
              balances: a.parsed_balances.map { |b|
                amount   = b.dig("balance_amount", "amount")
                currency = b.dig("balance_amount", "currency")
                {
                  name:           b["name"],
                  type:           b["balance_type"],
                  amount_cents:   amount.present? ? Money.from_amount(BigDecimal(amount.to_s), currency).cents : nil,
                  currency:       currency,
                  reference_date: b["reference_date"]
                }
              } }
          end
          json(count: rows.size, accounts: rows)
        end
      end
    end
  end
end
