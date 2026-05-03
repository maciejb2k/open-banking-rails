# frozen_string_literal: true

module EnableBanking
  module Api
    # Response shape differs from POST /sessions: `accounts` is an array of UID
    # strings, full account data lives in `accounts_data` (skinny). DO NOT
    # overwrite full BankAccount data from this response - only update
    # lifecycle fields (status, valid_until, closed_at).
    class GetSession < Base
      def initialize(credential:, session_id:)
        @credential = credential
        @session_id = session_id
      end

      def call
        client.get("/sessions/#{@session_id}")
      end
    end
  end
end
