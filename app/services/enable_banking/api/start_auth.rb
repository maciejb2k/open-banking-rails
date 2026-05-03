# frozen_string_literal: true

module EnableBanking
  module Api
    # `state` MUST be signed/verifiable on the callback to prevent CSRF -
    # the controller is responsible for that, not this query.
    # Some banks cap valid_until lower than requested (mBank → 90 days).
    class StartAuth < Base
      DEFAULT_VALID_DAYS = 180

      def initialize(credential:, aspsp_name:, aspsp_country:, state:,
                     psu_type: "personal", valid_days: DEFAULT_VALID_DAYS,
                     access_balances: true, access_transactions: true,
                     auth_method: nil, language: nil)
        @credential = credential
        @aspsp_name = aspsp_name
        @aspsp_country = aspsp_country
        @state = state
        @psu_type = psu_type
        @valid_days = valid_days
        @access_balances = access_balances
        @access_transactions = access_transactions
        @auth_method = auth_method
        @language = language
      end

      def call
        body = {
          access: {
            valid_until: (Time.current + @valid_days.days).utc.iso8601,
            balances: @access_balances,
            transactions: @access_transactions
          },
          aspsp: { name: @aspsp_name, country: @aspsp_country },
          state: @state,
          redirect_url: @credential.redirect_url,
          psu_type: @psu_type
        }
        body[:auth_method] = @auth_method if @auth_method
        body[:language] = @language if @language

        client.post("/auth", body)
      end
    end
  end
end
