# frozen_string_literal: true

module Admin
  class BankTransactionsController < BaseController
    before_action :set_user_scope_helpers

    def index
      @pagy, @collection = paginated(
        BankTransaction.for_user(current_user),
        default_sort: "booking_date desc",
        includes: { bank_account: :current_bank_connection }
      )
    end

    def show
      @transaction = BankTransaction.for_user(current_user)
                       .includes(bank_account: :current_bank_connection)
                       .find(params[:id])
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
