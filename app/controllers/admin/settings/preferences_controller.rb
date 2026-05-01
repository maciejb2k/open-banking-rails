# frozen_string_literal: true

module Admin
  module Settings
    # Per-user preferences split across three side-nav sections:
    #
    #   - profile : display name + password
    #   - app     : cash tracking, hidden categories
    #   - llm     : AI provider, API key, connection test
    #
    # Each section gets its own GET (render the section) + PATCH (save).
    # That keeps params permitted lists scoped to one concern and makes
    # adding a fourth section a copy-paste of one of the existing pairs
    # — no fat update action accumulating fields.
    class PreferencesController < BaseController
      before_action :load_user

      # ── Profile ──────────────────────────────────────────────────────
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
          # the session so the user isn't kicked out mid-flow.
          bypass_sign_in(@user)
          redirect_to admin_settings_preferences_profile_path, notice: "Password changed."
        else
          flash.now[:alert] = @user.errors.full_messages.join(", ")
          render :profile, status: :unprocessable_entity
        end
      end

      # ── App ──────────────────────────────────────────────────────────
      def app; end

      def update_app
        was_tracking = @user.track_cash?

        if @user.update(app_params)
          notice = "App settings saved."
          if !was_tracking && @user.track_cash?
            stats = enable_cash_tracking!(@user)
            notice += " Created a PLN wallet and linked #{stats[:linked]} historical ATM withdrawal(s)."
          end
          redirect_to admin_settings_preferences_app_path, notice: notice
        else
          flash.now[:alert] = @user.errors.full_messages.join(", ")
          render :app, status: :unprocessable_entity
        end
      end

      # ── LLM ──────────────────────────────────────────────────────────
      def llm
        load_llm_form_objects
      end

      def update_llm
        load_llm_form_objects
        attrs = llm_params

        # Empty api_key on an existing record means "keep the current key" —
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
          redirect_to admin_settings_preferences_llm_path,
                      notice: "Connection OK — #{@llm_setting.provider_label} (#{@llm_setting.effective_model})."
        rescue Llm::Client::Error => e
          run.fail!(error: e.message, summary: { "request" => request_payload, "response" => nil })
          @llm_setting.record_test_failure!(e.message) if @llm_setting.persisted?
          redirect_to admin_settings_preferences_llm_path,
                      alert: "Test failed: #{e.message}"
        end
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
        # multi_select renders no hidden inputs when nothing is selected, so
        # the param is omitted entirely from the form. Force an empty array
        # so the has_many through can clear the join table.
        permitted[:hidden_category_ids] ||= []
        permitted
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
