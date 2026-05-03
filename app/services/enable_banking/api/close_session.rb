# frozen_string_literal: true

module EnableBanking
  module Api
    # Best-effort cleanup; mark local connection as closed regardless of result.
    class CloseSession < Base
      def initialize(credential:, session_id:)
        @credential = credential
        @session_id = session_id
      end

      def call
        client.delete("/sessions/#{@session_id}")
      end
    end
  end
end
