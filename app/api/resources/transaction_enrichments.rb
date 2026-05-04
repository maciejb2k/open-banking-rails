# frozen_string_literal: true

module Resources
  class TransactionEnrichments < Grape::API
    before { authenticate! }

    resource :bank_transactions do
      route_param :bank_transaction_id, type: Integer do
        resource :classification do
          desc "Apply merchant + category to a bank transaction" do
            success model: Entities::TransactionEnrichment
            failure [ [ 422, "Could not apply" ] ]
          end
          params do
            requires :mode,         type: String, values: %w[only_this all_for_merchant create_rule],
                                    desc: "Propagation strategy"
            optional :merchant_id,  type: Integer
            optional :category_id,  type: Integer
            optional :rule_field,   type: String, values: %w[title counterparty_name counterparty_iban],
                                    desc: "Required when mode=create_rule"
            optional :rule_kind,    type: String, values: %w[contains equals regex starts_with ends_with]
            optional :rule_pattern, type: String
          end
          post do
            transaction = ::BankTransaction.for_user(current_user).find(params[:bank_transaction_id])
            result = ::Enrichment::ClassificationApplier.call(
              transaction: transaction,
              actor:       current_user,
              input: ::Enrichment::ClassificationApplier::Input.new(
                mode:         params[:mode],
                merchant:     current_user.merchants.find_by(id: params[:merchant_id]),
                category:     current_user.categories.find_by(id: params[:category_id]),
                rule_field:   params[:rule_field],
                rule_kind:    params[:rule_kind],
                rule_pattern: params[:rule_pattern]
              )
            )
            if result.success?
              present transaction.reload.enrichment, with: Entities::TransactionEnrichment
            else
              error!({ message: result.message }, 422)
            end
          end
        end
      end
    end
  end
end
