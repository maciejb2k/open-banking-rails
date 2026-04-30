# frozen_string_literal: true

module Admin
  # Single endpoint for the "edit classification" modal on a transaction's
  # show page. Delegates all logic to ClassificationApplier — the controller
  # only resolves params and routes the result back to the user.
  class TransactionEnrichmentsController < BaseController
    def update
      transaction = BankTransaction.for_user(current_user).find(params[:bank_transaction_id])

      mode      = params.dig(:enrichment, :mode)
      merchant  = current_user.merchants.find_by(id: params.dig(:enrichment, :merchant_id))
      category  = current_user.categories.find_by(id: params.dig(:enrichment, :category_id))

      result = Enrichment::ClassificationApplier.call(
        transaction: transaction,
        merchant: merchant,
        category: category,
        mode: mode,
        rule_field: params.dig(:enrichment, :rule_field),
        rule_pattern: params.dig(:enrichment, :rule_pattern),
        rule_kind: params.dig(:enrichment, :rule_kind),
        actor: current_user
      )

      if result.success?
        redirect_to admin_bank_transaction_path(transaction), notice: result.message
      else
        redirect_to admin_bank_transaction_path(transaction), alert: result.message
      end
    end
  end
end
