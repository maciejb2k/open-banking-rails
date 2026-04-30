# frozen_string_literal: true

module Admin
  module Settings
    # Per-user preferences. Today: track_cash. Future: localization,
    # default currency, notification opt-ins.
    #
    # Toggling track_cash off→on triggers a one-shot setup so the user's
    # next visit to /admin/cash_transactions isn't an empty state:
    #   - a PLN cash wallet is created (if absent), and
    #   - historical BLIK ATM withdrawals are linked retroactively.
    # Both steps are idempotent — running them more than once is safe.
    class PreferencesController < BaseController
      def edit
        @user = current_user
      end

      def update
        @user = current_user
        was_tracking = @user.track_cash?

        if @user.update(preference_params)
          notice = "Preferences saved."
          if !was_tracking && @user.track_cash?
            stats = enable_cash_tracking!(@user)
            notice += " Created a PLN wallet and linked #{stats[:linked]} historical ATM withdrawal(s)."
          end
          redirect_to edit_admin_settings_preferences_path, notice: notice
        else
          flash.now[:alert] = @user.errors.full_messages.join(", ")
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def preference_params
        params.require(:user).permit(:track_cash)
      end

      def enable_cash_tracking!(user)
        Cash::WalletResolver.call(user: user, currency: "PLN")

        linked = 0
        BankTransaction.for_user(user)
                       .where(payment_method: "blik_atm", direction: "debit")
                       .find_each do |tx|
          linked += 1 if Cash::AtmWithdrawalLinker.link!(tx)
        end
        { linked: linked }
      end
    end
  end
end
