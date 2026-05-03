# frozen_string_literal: true

module EnableBanking
  module Operations
    # Remote close is best-effort - failures are swallowed; the local "closed"
    # state is what matters. Never raises Failed.
    class CloseConnection < Base
      def initialize(connection)
        @connection = connection
      end

      def call
        try_remote_close
        @connection.update!(status: "closed", closed_at: Time.current, last_error: nil)
        @connection
      end

      private

      def try_remote_close
        return unless @connection.status == "authorized" && @connection.session_id.present?

        Api::CloseSession.call(
          credential: @connection.tpp_credential,
          session_id: @connection.session_id
        )
      rescue EnableBanking::Error
        nil
      end
    end
  end
end
