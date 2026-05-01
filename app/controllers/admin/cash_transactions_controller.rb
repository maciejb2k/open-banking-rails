# frozen_string_literal: true

module Admin
  # Off-bank ledger CRUD. Each entry lands in a per-currency cash wallet
  # (BankAccount#manual=true) auto-resolved by Cash::WalletResolver.
  # Only manual-source rows are user-editable here — atm-link rows
  # (Phase 3) are read-only from this controller's perspective.
  class CashTransactionsController < BaseController
    before_action :load_cash_transaction, only: %i[show edit update destroy]
    before_action :reject_non_manual,     only: %i[edit update destroy]

    def index
      scope = ManualTransaction.for_user(current_user)
      scope = scope.where(bank_account_id: params[:wallet_id]) if params[:wallet_id].present?
      scope = scope.where(direction: params[:direction]) if params[:direction].present?
      scope = scope.where("booking_date >= ?", params[:from]) if params[:from].present?
      scope = scope.where("booking_date <= ?", params[:to]) if params[:to].present?

      @q = scope.ransack(params[:q])
      @q.sorts = "booking_date desc" if @q.sorts.empty?

      @pagy, @collection = pagy(:offset, @q.result.includes(
        :bank_account, enrichment: [ { merchant: :default_category }, :category ]
      ))

      @user_wallets = current_user.cash_wallets.order(:currency)
      @wallet_balances = compute_wallet_balances(@user_wallets)
    end

    def show
      # Reuse edit view for now; show-only would be redundant given the form's clarity.
      redirect_to edit_admin_cash_transaction_path(@cash_transaction)
    end

    def new
      @cash_transaction = ManualTransaction.new(
        direction:      params[:direction].presence || "debit",
        currency:       default_currency,
        booking_date:   Date.current,
        payment_method: "cash"
      )
      load_form_options
    end

    def create
      result = Cash::TransactionCreator.call(
        user: current_user,
        input: Cash::TransactionCreator::Input.new(**cash_params.to_h.symbolize_keys)
      )
      if result.success?
        redirect_to admin_cash_transactions_path,
                    notice: t_kind(result.transaction, action: :created)
      else
        @cash_transaction = result.transaction || ManualTransaction.new
        load_form_options
        flash.now[:alert] = result.error.presence || "Could not save the transaction."
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      # Same logic as the bank-tx show: editing a row in a hidden
      # category would reveal what's hidden, so bounce.
      if current_user.hides_category?(@cash_transaction.effective_category)
        redirect_to admin_cash_transactions_path,
                    alert: "Ta transakcja jest w ukrytej kategorii. Usuń ją z listy w preferencjach, żeby ją edytować."
        return
      end

      load_form_options
    end

    def update
      result = Cash::TransactionUpdater.call(
        transaction: @cash_transaction,
        input: Cash::TransactionUpdater::Input.new(**cash_params.to_h.symbolize_keys.except(:currency))
      )
      if result.success?
        redirect_to admin_cash_transactions_path,
                    notice: t_kind(@cash_transaction, action: :updated)
      else
        load_form_options
        flash.now[:alert] = result.error.presence || "Could not update the transaction."
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @cash_transaction.destroy!
      redirect_to admin_cash_transactions_path, notice: "Transaction deleted."
    end

    private

    def load_cash_transaction
      @cash_transaction = ManualTransaction.for_user(current_user).find(params[:id])
    end

    def reject_non_manual
      return if @cash_transaction.source == "manual"
      redirect_to admin_cash_transactions_path,
                  alert: "This transaction was auto-generated and isn't editable here."
    end

    def load_form_options
      @merchant_options = current_user.merchants.active.order(:name).limit(500)
      @category_options = current_user.categories.active.includes(:parent).order(:position, :name)
      @currency_options = supported_currencies
    end

    def cash_params
      params.require(:cash_transaction).permit(
        :amount, :currency, :direction, :booking_date, :transaction_date,
        :title, :note, :counterparty_name, :merchant_id, :category_id,
        :payment_method
      )
    end

    # Default to existing wallet currency when the user already has one,
    # else PLN. Avoids pushing a fresh user toward EUR by accident.
    def default_currency
      current_user.cash_wallets.order(:created_at).first&.currency || "PLN"
    end

    # PLN as canonical + any currency the user already touches via a wallet
    # or a synced bank account. No global "every currency on Earth" dropdown.
    def supported_currencies
      ([
        "PLN",
        *current_user.cash_wallets.pluck(:currency),
        *current_user.bank_accounts.pluck(:currency)
      ].compact.map(&:upcase).uniq.sort)
    end

    def compute_wallet_balances(wallets)
      return {} if wallets.empty?
      rows = ManualTransaction.where(bank_account_id: wallets.map(&:id))
                              .group(:bank_account_id, :direction)
                              .sum(:amount_cents)
      wallets.each_with_object({}) do |wallet, acc|
        credit = rows[[ wallet.id, "credit" ]].to_i
        debit  = rows[[ wallet.id, "debit"  ]].to_i
        acc[wallet.id] = Money.new(credit - debit, wallet.currency)
      end
    end

    def t_kind(transaction, action:)
      verb = action == :created ? "Saved" : "Updated"
      kind = transaction.direction == "credit" ? "income" : "expense"
      "#{verb} #{kind} #{transaction.amount.format}."
    end
  end
end
