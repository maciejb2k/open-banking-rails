# frozen_string_literal: true

module EnableBanking
  module Operations
    # Refreshes a BankConnection's lifecycle state from EB.
    #
    # GET /sessions/{id} returns SKINNY data — only status, scope and timestamps.
    # We deliberately do NOT touch BankAccount records here (see Api::GetSession
    # comment for why). For full account data refresh, use RefreshAccountDetails.
    #
    # On API failure we still record `last_error` on the connection so the UI
    # can show what went wrong.
    #
    # Raises Failed on API failure (after persisting last_error).
    class RefreshConnection < Base
      Failed = Class.new(StandardError)

      EB_STATUS_MAP = {
        "AUTHORIZED" => "authorized",
        "CLOSED" => "closed",
        "EXPIRED" => "expired",
        "REJECTED" => "revoked",
        "REVOKED" => "revoked"
      }.freeze

      def initialize(connection)
        @connection = connection
      end

      def call
        result = Api::GetSession.call(
          credential: @connection.tpp_credential,
          session_id: @connection.session_id
        )

        if result.failure?
          @connection.update!(last_error: "HTTP #{result.status}: #{result.error}")
          raise Failed, result.error_message
        end

        data = result.data
        @connection.update!(
          status: EB_STATUS_MAP.fetch(data["status"], "error"),
          last_refreshed_at: Time.current,
          access_balances: data.dig("access", "balances"),
          access_transactions: data.dig("access", "transactions"),
          valid_until: data.dig("access", "valid_until"),
          closed_at: data["closed"],
          last_error: nil
        )
        @connection
      end
    end
  end
end
