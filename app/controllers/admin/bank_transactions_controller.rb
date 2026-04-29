# frozen_string_literal: true

module Admin
  class BankTransactionsController < BaseController
    before_action :set_user_scope_helpers

    def index
      scope = BankTransaction.for_user(current_user)

      # Enrichment-based filters live outside Ransack — they cross the
      # polymorphic boundary into transaction_enrichments. We apply them as
      # explicit scopes so Ransack stays clean for the bank-data filters.
      scope = scope.joins(:enrichment).where(transaction_enrichments: { merchant_id: params[:merchant_id] }) if params[:merchant_id].present?
      scope = scope.joins(:enrichment).where(transaction_enrichments: { category_id: params[:category_id] }) if params[:category_id].present?
      scope = scope.joins(:enrichment).where(transaction_enrichments: { source: params[:enrichment_source] }) if params[:enrichment_source].present?
      scope = scope.where(payment_method: params[:payment_method]) if params[:payment_method].present?

      @pagy, @collection = paginated(
        scope,
        default_sort: "booking_date desc",
        includes: [ { bank_account: :current_bank_connection }, { enrichment: { merchant: :default_category } } ]
      )
    end

    def show
      @transaction = BankTransaction.for_user(current_user)
                       .includes(bank_account: :current_bank_connection, enrichment: [ :merchant, :category, :merchant_rule ])
                       .find(params[:id])
      @merchant_options = Merchant.active.includes(:default_category).order(:name)
    end

    private

    # User-owned account list for filter selects (active accounts only).
    def set_user_scope_helpers
      @user_bank_accounts = BankAccount
                              .joins(:tpp_credential)
                              .where(tpp_credentials: { user_id: current_user.id })
                              .order(:iban)
    end
  end
end
