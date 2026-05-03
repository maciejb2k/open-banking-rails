# frozen_string_literal: true

module EnableBanking
  module Api
    # The `accounts` array here is the only place to get FULL account info
    # without a per-account GET - GET /sessions/{id} just returns UID strings.
    class CreateSession < Base
      def initialize(credential:, code:)
        @credential = credential
        @code = code
      end

      def call
        client.post("/sessions", { code: @code })
      end
    end
  end
end
