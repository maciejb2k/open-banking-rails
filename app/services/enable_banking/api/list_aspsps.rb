# frozen_string_literal: true

module EnableBanking
  module Api
    # GET /aspsps[?country=XX] — list of bank integrations EB supports.
    #
    # Response: { aspsps: [{ name, country, logo, psu_types, auth_methods,
    #             maximum_consent_validity, beta, required_psu_headers, ... }] }
    #
    # Used to populate the "Add bank" picker in the UI.
    class ListAspsps < Base
      def initialize(credential:, country: nil)
        @credential = credential
        @country = country
      end

      def call
        params = {}
        params[:country] = @country if @country
        client.get("/aspsps", params)
      end
    end
  end
end
