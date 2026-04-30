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

      # Drilling into a tx in a hidden category exposes everything the
      # index/dashboard hid. Bounce back; user has to remove the category
      # from the hidden list in /admin/settings/preferences to open it.
      if current_user.hides_category?(@transaction.effective_category)
        redirect_to admin_bank_transactions_path,
                    alert: "Ta transakcja jest w ukrytej kategorii. Usuń ją z listy w preferencjach, żeby ją otworzyć."
        return
      end

      @merchant_options = current_user.merchants.active.includes(:default_category).order(:name)
    end

    private

    # User-owned account list for filter selects (active accounts only).
    def set_user_scope_helpers
      @user_bank_accounts = BankAccount
                              .joins(:tpp_credential)
                              .where(tpp_credentials: { user_id: current_user.id })
                              .order(:iban)
    end

    # Drill-down filters for the LLM-enrichment dashboard. Each value
    # corresponds to a row in the "What's left" panel:
    #   merchantless   — every tx without a merchant (panel total)
    #   llm_ready      — what the next LLM run would actually pick up.
    #                    Defers to EnrichmentRunner so the count here matches
    #                    the count there exactly. That scope filters out
    #                    non-merchant payment methods, own IBANs and own
    #                    holder names, so "ready to send" is honest.
    #   no_llm_signal  — merchantless minus llm_ready: rows that won't ever
    #                    benefit from the LLM (BLIK codes, "PRZELEW", numeric
    #                    junk, own-account leakage) and need manual
    #                    classification or a different rule.
    def filter_by_enrichment_state(scope, state)
      merchantless = scope.joins(:enrichment).merge(TransactionEnrichment.merchantless)

      case state
      when "merchantless"
        merchantless
      when "llm_ready"
        Llm::EnrichmentRunner.new(user: current_user).send(:default_scope).where(id: merchantless.select(:id))
      when "no_llm_signal"
        ready_ids = Llm::EnrichmentRunner.new(user: current_user).send(:default_scope).select(:id)
        merchantless.where.not(id: ready_ids)
      else
        scope
      end
    end
  end
end
