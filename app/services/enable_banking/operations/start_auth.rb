# frozen_string_literal: true

module EnableBanking
  module Operations
    # Initiates the bank authorization flow.
    #
    # - Encodes signed CSRF state (user, credential, aspsp, replaces target)
    # - Calls Api::StartAuth
    # - Returns the bank's redirect URL on success
    #
    # Raises Failed when EB doesn't return a URL.
    class StartAuth < Base
      Failed = Class.new(StandardError)

      def initialize(credential:, form:, current_user:, replaces_connection_id: nil)
        @credential = credential
        @form = form
        @current_user = current_user
        @replaces_connection_id = replaces_connection_id
      end

      def call
        result = Api::StartAuth.call(
          credential: @credential,
          aspsp_name: @form.aspsp_name,
          aspsp_country: @form.aspsp_country,
          psu_type: @form.psu_type,
          state: state_token,
          valid_days: @form.valid_days
        )

        url = result.success? && result.data["url"].presence
        raise Failed, "Failed to start auth: #{result.error_message}" if url.blank?

        url
      end

      private

      def state_token
        EnableBanking::State.encode(
          user_id: @current_user.id,
          tpp_credential_id: @credential.id,
          aspsp_name: @form.aspsp_name,
          aspsp_country: @form.aspsp_country,
          psu_type: @form.psu_type,
          replaces_connection_id: @replaces_connection_id
        )
      end
    end
  end
end
