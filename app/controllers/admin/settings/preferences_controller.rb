# frozen_string_literal: true

module Admin
  module Settings
    class PreferencesController < BaseController
      before_action :load_user

      def profile; end

      def update_profile
        if @user.update(profile_params)
          redirect_to admin_settings_preferences_profile_path, notice: "Profile saved."
        else
          flash.now[:alert] = @user.errors.full_messages.join(", ")
          render :profile, status: :unprocessable_entity
        end
      end

      def update_password
        if @user.update_with_password(password_params)
          # Rememberable rotates the auth token on password change; rebind
          # so the user isn't kicked out mid-flow.
          bypass_sign_in(@user)
          redirect_to admin_settings_preferences_profile_path, notice: "Password changed."
        else
          flash.now[:alert] = @user.errors.full_messages.join(", ")
          render :profile, status: :unprocessable_entity
        end
      end

      def app; end

      def update_app
        was_tracking = @user.track_cash?

        if @user.update(app_params)
          notice = "App settings saved."
          if !was_tracking && @user.track_cash?
            result = Cash::Tracking.enable!(user: @user)
            notice += " Created a #{result.wallet.currency} wallet and linked #{result.linked} historical ATM withdrawal(s)."
          end
          redirect_to admin_settings_preferences_app_path, notice: notice
        else
          flash.now[:alert] = @user.errors.full_messages.join(", ")
          render :app, status: :unprocessable_entity
        end
      end

      def llm
        load_llm_form_objects
      end

      def update_llm
        load_llm_form_objects
        attrs = llm_params

        # Empty api_key on an existing record means "keep the current key" -
        # the form pre-fills with a placeholder, never the real value, so
        # blank submission is the intent to leave it untouched.
        attrs.delete(:api_key) if attrs[:api_key].blank? && @llm_setting.persisted?

        if @llm_setting.update(attrs)
          redirect_to admin_settings_preferences_llm_path, notice: "LLM settings saved."
        else
          flash.now[:alert] = @llm_setting.errors.full_messages.join(", ")
          render :llm, status: :unprocessable_entity
        end
      end

      def test_llm
        load_llm_form_objects

        unless @llm_setting.configured?
          redirect_to admin_settings_preferences_llm_path,
                      alert: "Save a provider and API key first." and return
        end

        result = Llm::ConnectionTestRunner.call(user: current_user)
        redirect_to admin_settings_preferences_llm_path,
                    notice: "Connection OK - #{result.setting.provider_label} (#{result.setting.effective_model})."
      rescue Llm::ConnectionTestRunner::Failed => e
        redirect_to admin_settings_preferences_llm_path, alert: "Test failed: #{e.message}"
      end

      private

      def load_user
        @user = current_user
      end

      def load_llm_form_objects
        @llm_setting   = current_user.llm_setting ||
                         current_user.build_llm_setting(provider: Llm::Providers.keys.first)
        @last_llm_test = current_user.operation_runs
                                     .where(kind: "llm_connection_test")
                                     .order(created_at: :desc)
                                     .first
      end

      def profile_params
        params.require(:user).permit(:name)
      end

      def password_params
        params.require(:user).permit(:current_password, :password, :password_confirmation)
      end

      def app_params
        permitted = params.require(:user).permit(:track_cash, hidden_category_ids: [])
        # multi_select omits the param when nothing is selected - force [] so
        # the has_many through can clear the join table.
        permitted[:hidden_category_ids] ||= []
        permitted
      end

      def llm_params
        params.require(:llm_setting).permit(:provider, :api_key, :model)
      end
    end
  end
end
