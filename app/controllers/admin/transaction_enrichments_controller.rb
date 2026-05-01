# frozen_string_literal: true

module Admin
  # Single endpoint for the "edit classification" modal on a transaction's
  # show page. Delegates all logic to ClassificationApplier — the controller
  # only resolves params and routes the result back to the user.
  class TransactionEnrichmentsController < BaseController
    def update
      transaction = BankTransaction.for_user(current_user).find(params[:bank_transaction_id])
      attrs = params.fetch(:enrichment, {}).permit(:mode, :merchant_id, :category_id, :rule_field, :rule_kind, :rule_pattern)

      result = Enrichment::ClassificationApplier.call(
        transaction: transaction,
        actor:       current_user,
        input: Enrichment::ClassificationApplier::Input.new(
          mode:         attrs[:mode],
          merchant:     current_user.merchants.find_by(id: attrs[:merchant_id]),
          category:     current_user.categories.find_by(id: attrs[:category_id]),
          rule_field:   attrs[:rule_field],
          rule_kind:    attrs[:rule_kind],
          rule_pattern: attrs[:rule_pattern]
        )
      )

      if result.success?
        redirect_to admin_bank_transaction_path(transaction), notice: result.message
      else
        redirect_to admin_bank_transaction_path(transaction), alert: result.message
      end
    end
  end
end
