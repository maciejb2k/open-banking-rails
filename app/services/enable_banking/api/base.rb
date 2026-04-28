# frozen_string_literal: true

module EnableBanking
  module Api
    # Thin wrappers around individual Enable Banking HTTP endpoints.
    #
    # Convention:
    #   EnableBanking::Api::SomeEndpoint.call(credential:, **params) → Result
    #
    # Subclasses override #call. Most just delegate to client.get/post.
    # When extra logic (multi-step, persistence, side effects) is needed,
    # build an EnableBanking::Operations::* on top of these.
    class Base
      def self.call(**args)
        new(**args).call
      end

      private

      def client
        @client ||= EnableBanking::Client.new(@credential)
      end
    end
  end
end
