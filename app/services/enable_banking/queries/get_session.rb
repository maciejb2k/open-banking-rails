# frozen_string_literal: true

module EnableBanking
  module Queries
    # GET /sessions/{session_id} — refreshes session status / scope.
    #
    # IMPORTANT (PoC finding): the GET response shape differs from POST /sessions:
    # - `accounts` is an array of UID strings (not full account objects)
    # - `accounts_data` carries skinny per-account data (uid + identification_hashes)
    # - `session_id` is NOT echoed in the response
    # - extra fields: status (uppercase), authorized_at, closed
    #
    # Callers should NOT overwrite full BankAccount data with this response.
    # Use this only to update lifecycle fields (status, valid_until, closed_at).
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
