# frozen_string_literal: true

module Mcp
  module Tools
    module Transactions
      class Classify < Mcp::ApplicationTool
        tool_name "transactions.classify"
        description <<~MD.strip
          Apply a merchant + category to a bank transaction.
          mode=only_this writes the override on this row only.
          mode=all_for_merchant sets merchant.default_category - all rows for the merchant inherit.
          mode=create_rule creates a user-source MerchantRule (rule_field/rule_kind/rule_pattern required) and rebuilds enrichment.
        MD

        input_schema(
          properties: {
            bank_transaction_id: { type: "integer" },
            mode:                { type: "string", enum: %w[only_this all_for_merchant create_rule] },
            merchant_id:         { type: "integer" },
            category_id:         { type: "integer" },
            rule_field:          { type: "string", enum: %w[title counterparty_name counterparty_iban] },
            rule_kind:           { type: "string", enum: %w[contains equals regex starts_with ends_with] },
            rule_pattern:        { type: "string" }
          },
          required: %w[bank_transaction_id mode]
        )

        def self.call(server_context:, **args)
          user = current_user(server_context)
          tx   = ::BankTransaction.for_user(user).find_by(id: args[:bank_transaction_id])
          return error("Bank transaction ##{args[:bank_transaction_id]} not found.") unless tx

          input = ::Enrichment::ClassificationApplier::Input.new(
            mode:         args[:mode],
            merchant:     user.merchants.find_by(id: args[:merchant_id]),
            category:     user.categories.find_by(id: args[:category_id]),
            rule_field:   args[:rule_field],
            rule_kind:    args[:rule_kind],
            rule_pattern: args[:rule_pattern]
          )
          result = ::Enrichment::ClassificationApplier.call(transaction: tx, actor: user, input: input)

          if result.success?
            text(result.message)
          else
            error(result.message)
          end
        end
      end
    end
  end
end
