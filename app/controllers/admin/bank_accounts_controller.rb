# frozen_string_literal: true

module Admin
  class BankAccountsController < BaseController
    before_action :set_account, only: %i[show refresh_details refresh_balances]

    def index
      scope = BankAccount.joins(:tpp_credential).where(tpp_credentials: { user_id: current_user.id })
      @pagy, @collection = paginated(scope, default_sort: "created_at desc", includes: :current_bank_connection)
    end

    def show
    end

    def refresh_details
      EnableBanking::Operations::RefreshAccountDetails.call(@account)
      redirect_to admin_bank_account_path(@account), notice: "Account details refreshed."
    rescue EnableBanking::Operations::RefreshAccountDetails::Failed => e
      redirect_to admin_bank_account_path(@account), alert: "Refresh failed: #{e.message}"
    end

    def refresh_balances
      EnableBanking::Operations::RefreshAccountBalances.call(@account)
      redirect_to admin_bank_account_path(@account), notice: "Balances refreshed."
    rescue EnableBanking::Operations::RefreshAccountBalances::Failed => e
      redirect_to admin_bank_account_path(@account), alert: "Refresh failed: #{e.message}"
    end

    private

    def set_account
      @account = BankAccount
                   .joins(:tpp_credential)
                   .where(tpp_credentials: { user_id: current_user.id })
                   .find(params[:id])
    end
  end
end
