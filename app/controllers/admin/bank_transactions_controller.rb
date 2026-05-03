# frozen_string_literal: true

module Admin
  class BankTransactionsController < BaseController
    before_action :set_user_scope_helpers

    def index
      scope = BankTransaction.for_user(current_user)

      # Enrichment-based filters cross the polymorphic boundary into
      # transaction_enrichments - applied as explicit scopes to keep Ransack
      # clean for the bank-data filters.
      scope = scope.joins(:enrichment).where(transaction_enrichments: { merchant_id: params[:merchant_id] }) if params[:merchant_id].present?
      scope = scope.joins(:enrichment).where(transaction_enrichments: { category_id: params[:category_id] }) if params[:category_id].present?
      scope = scope.joins(:enrichment).where(transaction_enrichments: { source: params[:enrichment_source] }) if params[:enrichment_source].present?
      scope = scope.where(payment_method: params[:payment_method]) if params[:payment_method].present?
      scope = filter_by_enrichment_state(scope, params[:enrichment_state]) if params[:enrichment_state].present?

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

      # Drilling into a tx in a hidden category would expose what's hidden.
      if current_user.hides_category?(@transaction.effective_category)
        redirect_to admin_bank_transactions_path,
                    alert: "This transaction is in a hidden category. Remove it from the hidden list in preferences to open it."
        return
      end

      @merchant_options = current_user.merchants.active.includes(:default_category).order(:name)
    end

    private

    def set_user_scope_helpers
      @user_bank_accounts = BankAccount
                              .joins(:tpp_credential)
                              .where(tpp_credentials: { user_id: current_user.id })
                              .order(:iban)
    end

    # State values mirror the LLM-enrichment "What's left" panel:
    #   merchantless  - every tx without a merchant
    #   llm_ready     - what EnrichmentRunner would actually pick up
    #   no_llm_signal - merchantless minus llm_ready (BLIK codes, "PRZELEW",
    #                   own-account moves - won't benefit from the LLM)
    def filter_by_enrichment_state(scope, state)
      merchantless = scope.joins(:enrichment).merge(TransactionEnrichment.merchantless)

      case state
      when "merchantless"
        merchantless
      when "llm_ready"
        Llm::EnrichableQuery.scope(user: current_user).where(id: merchantless.select(:id))
      when "no_llm_signal"
        merchantless.where.not(id: Llm::EnrichableQuery.scope(user: current_user).select(:id))
      else
        scope
      end
    end
  end
end
