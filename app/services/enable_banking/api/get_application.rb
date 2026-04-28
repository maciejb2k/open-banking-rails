# frozen_string_literal: true

module EnableBanking
  module Api
    # GET /application — returns the credential's own metadata as known
    # to Enable Banking: name, environment, services, redirect_urls,
    # countries, active flag, kid.
    #
    # Used as a "ping" / health check for a TppCredential — if this
    # succeeds, the JWT signature + kid mapping in EB are good.
    class GetApplication < Base
      def initialize(credential:)
        @credential = credential
      end

      def call
        client.get("/application")
      end
    end
  end
end
