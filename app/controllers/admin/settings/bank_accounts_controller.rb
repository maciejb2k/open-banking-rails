# frozen_string_literal: true

module Admin
  module Settings
    class BankAccountsController < BaseController
      before_action :set_account, only: %i[show refresh_details refresh_balances]

      def index
        scope = BankAccount.joins(:tpp_credential).where(tpp_credentials: { user_id: current_user.id })
        @q = scope.ransack(params[:q])
        @q.sorts = "created_at desc" if @q.sorts.empty?
        @pagy, @collection = pagy(:offset, @q.result.includes(:current_bank_connection))
      end

      def show
      end

      def refresh_details
        result = EnableBanking::Queries::GetAccountDetails.call(
          credential: @account.tpp_credential,
          uid: @account.uid
        )

        if result.success?
          d = result.data
          @account.update!(
            raw_details: d,
            details_fetched_at: Time.current,
            iban: d.dig("account_id", "iban") || @account.iban,
            bban: BankAccount.bban_from(d["account_id"]) || @account.bban,
            all_account_ids: d["all_account_ids"] || @account.all_account_ids,
            currency: d["currency"] || @account.currency,
            name: d["name"].presence || @account.name,
            product: d["product"] || @account.product,
            details: d["details"] || @account.details,
            cash_account_type: d["cash_account_type"] || @account.cash_account_type,
            usage: d["usage"] || @account.usage,
            account_servicer: d["account_servicer"] || @account.account_servicer
          )
          redirect_to admin_settings_bank_account_path(@account),
                      notice: "Account details refreshed."
        else
          redirect_to admin_settings_bank_account_path(@account),
                      alert: "Refresh failed: #{result.error.presence || "HTTP #{result.status}"}"
        end
      rescue EnableBanking::Error => e
        redirect_to admin_settings_bank_account_path(@account),
                    alert: "Configuration error: #{e.message}"
      end

      def refresh_balances
        result = EnableBanking::Queries::GetAccountBalances.call(
          credential: @account.tpp_credential,
          uid: @account.uid
        )

        if result.success?
          @account.update!(
            raw_balances: result.data.to_json,
            balances_synced_at: Time.current
          )
          redirect_to admin_settings_bank_account_path(@account),
                      notice: "Balances refreshed."
        else
          redirect_to admin_settings_bank_account_path(@account),
                      alert: "Refresh failed: #{result.error.presence || "HTTP #{result.status}"}"
        end
      rescue EnableBanking::Error => e
        redirect_to admin_settings_bank_account_path(@account),
                    alert: "Configuration error: #{e.message}"
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
end
