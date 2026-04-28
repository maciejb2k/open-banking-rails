# frozen_string_literal: true

module EnableBanking
  module Api
    # DELETE /sessions/{session_id} — explicitly close a session on the EB side.
    #
    # PoC noted side effects untested. Use as best-effort cleanup; mark
    # local connection as closed regardless of API result.
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
