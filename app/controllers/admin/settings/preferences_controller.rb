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
      before_action :load_form_objects

      def edit
      end

      def update
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

      def update_llm
        attrs = llm_params

        # Empty api_key on an existing record means "keep the current key" —
        # the form pre-fills with a placeholder, never the real value, so
        # blank submission is the intent to leave it untouched.
        attrs.delete(:api_key) if attrs[:api_key].blank? && @llm_setting.persisted?

        if @llm_setting.update(attrs)
          redirect_to edit_admin_settings_preferences_path, notice: "LLM settings saved."
        else
          flash.now[:alert] = @llm_setting.errors.full_messages.join(", ")
          render :edit, status: :unprocessable_entity
        end
      end

      def test_llm
        unless @llm_setting.configured?
          redirect_to edit_admin_settings_preferences_path,
                      alert: "Save a provider and API key first." and return
        end

        run = OperationRun.create!(
          kind:              "llm_connection_test",
          status:            "running",
          trigger:           "manual",
          started_at:        Time.current,
          triggered_by_user: current_user,
          subject:           current_user,
          params:            { "provider" => @llm_setting.provider, "model" => @llm_setting.effective_model },
          summary:           {}
        )

        # Embed the current timestamp in the prompt so the I/O panel proves
        # this isn't a cached response — and echo it back via the schema so
        # a misbehaving provider that returns canned JSON is visible.
        sent_at        = Time.current.iso8601
        system_prompt  = "You are a connectivity probe. Reply with exactly the JSON {\"ok\": true, \"echo\": \"<the sent_at value from the user message>\"}."
        user_prompt    = "ping sent_at=#{sent_at}"
        schema = {
          type: "object", additionalProperties: false,
          required: %w[ok echo],
          properties: {
            ok:   { type: "boolean" },
            echo: { type: "string", description: "Echo of the sent_at timestamp from the user message." }
          }
        }

        request_payload = {
          "provider"      => @llm_setting.provider,
          "model"         => @llm_setting.effective_model,
          "system_prompt" => system_prompt,
          "user_prompt"   => user_prompt,
          "schema"        => schema
        }

        begin
          response = @llm_setting.build_client.structured(
            system_prompt: system_prompt, user_prompt: user_prompt, schema: schema
          )
          run.succeed!(summary: { "request" => request_payload, "response" => response })
          @llm_setting.record_test_success!
          redirect_to edit_admin_settings_preferences_path,
                      notice: "Connection OK — #{@llm_setting.provider_label} (#{@llm_setting.effective_model})."
        rescue Llm::Client::Error => e
          run.fail!(error: e.message, summary: { "request" => request_payload, "response" => nil })
          @llm_setting.record_test_failure!(e.message) if @llm_setting.persisted?
          redirect_to edit_admin_settings_preferences_path,
                      alert: "Test failed: #{e.message}"
        end
      end

      private

      def load_form_objects
        @user        = current_user
        @llm_setting = current_user.llm_setting ||
                       current_user.build_llm_setting(provider: Llm::Providers.keys.first)
        @last_llm_test = OperationRun
                           .where(kind: "llm_connection_test", triggered_by_user: current_user)
                           .order(created_at: :desc)
                           .first
      end

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

      def llm_params
        params.require(:llm_setting).permit(:provider, :api_key, :model)
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
