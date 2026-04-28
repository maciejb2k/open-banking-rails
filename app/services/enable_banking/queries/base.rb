# frozen_string_literal: true

module EnableBanking
  module Queries
    # Convention for query services:
    #   EnableBanking::Queries::SomeQuery.call(credential:, **params) → Result
    #
    # Subclasses override #call. Most just delegate to client.get/post.
    # When extra logic is needed (validation, transformation), it lives
    # in #call so the controller layer stays thin.
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
