# frozen_string_literal: true

module EnableBanking
  module Api
    # Used as a "ping" / health check for a TppCredential - success means JWT
    # signature + kid mapping are good.
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
