# frozen_string_literal: true

module EnableBanking
  module Operations
    # GET /sessions/{id} returns skinny data only - DO NOT touch BankAccount
    # records here (see Api::GetSession). Use RefreshAccountDetails for those.
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

      AUTH_FAILURE_STATUSES = [ 401, 403, 410 ].freeze

      def call
        result = Api::GetSession.call(
          credential: @connection.tpp_credential,
          session_id: @connection.session_id
        )

        if result.failure?
          attrs = { last_error: "HTTP #{result.status}: #{result.error}" }
          attrs[:status] = "expired" if AUTH_FAILURE_STATUSES.include?(result.status)
          @connection.update!(attrs)
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
