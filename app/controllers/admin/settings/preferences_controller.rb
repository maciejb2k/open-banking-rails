# frozen_string_literal: true

module Admin
  module Settings
    # Per-user preferences: profile (name, email), cash tracking, hidden
    # categories. Password changes go through `update_password`, which uses
    # Devise's `update_with_password` so the current password is required.
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

      def update_password
        @user = current_user

        if @user.update_with_password(password_params)
          # Rememberable rotates the auth token on password change; rebind the
          # session so the user isn't kicked out mid-flow.
          bypass_sign_in(@user)
          redirect_to edit_admin_settings_preferences_path, notice: "Password changed."
        else
          flash.now[:alert] = @user.errors.full_messages.join(", ")
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def preference_params
        permitted = params.require(:user).permit(:name, :track_cash, hidden_category_ids: [])
        # multi_select renders no hidden inputs when nothing is selected, so
        # the param is omitted entirely from the form. Force an empty array
        # so the has_many through can clear the join table.
        permitted[:hidden_category_ids] ||= []
        permitted
      end

      def password_params
        params.require(:user).permit(:current_password, :password, :password_confirmation)
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
