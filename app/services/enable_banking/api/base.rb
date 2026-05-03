# frozen_string_literal: true

module EnableBanking
  module Api
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
