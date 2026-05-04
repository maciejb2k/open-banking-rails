# frozen_string_literal: true

module Admin
  module Settings
    class ApiTokensController < BaseController
      def index
        @tokens    = current_user.personal_access_tokens.order(revoked_at: :asc, created_at: :desc)
        @new_token = PersonalAccessToken.new
        @raw_token = flash[:new_raw_token]
      end

      def create
        result = Auth::PersonalAccessTokenIssuer.call(
          user:  current_user,
          input: Auth::PersonalAccessTokenIssuer::Input.new(name: params.dig(:personal_access_token, :name))
        )

        if result.success?
          # Raw token reaches the redirected GET via signed+encrypted flash,
          # one hop only - rendered there and never persisted in clear.
          flash[:new_raw_token] = result.raw_token
          redirect_to admin_settings_preferences_api_tokens_path,
                      notice: "Token \"#{result.token_record.name}\" generated. Copy it now - it won't be shown again."
        else
          @tokens    = current_user.personal_access_tokens.order(revoked_at: :asc, created_at: :desc)
          @new_token = result.token_record || PersonalAccessToken.new
          flash.now[:alert] = result.error.presence || "Could not generate the token."
          render :index, status: :unprocessable_entity
        end
      end

      def destroy
        token = current_user.personal_access_tokens.find(params[:id])
        if token.revoked?
          redirect_to admin_settings_preferences_api_tokens_path,
                      alert: "Token already revoked."
        else
          token.update!(revoked_at: Time.current)
          redirect_to admin_settings_preferences_api_tokens_path,
                      notice: "Token \"#{token.name}\" revoked."
        end
      end
    end
  end
end
