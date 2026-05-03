# frozen_string_literal: true

module EnableBanking
  module Api
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
