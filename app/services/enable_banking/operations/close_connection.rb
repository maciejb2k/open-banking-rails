# frozen_string_literal: true

module EnableBanking
  module Operations
    # Best-effort close of a bank session.
    #
    # If the connection is still authorized and has a session_id, we ask EB
    # to close the session. Either way we mark the local record as closed.
    # The remote call is best-effort — failures are intentionally swallowed
    # because the local "closed" state is what matters from the user's POV.
    #
    # Never raises Failed; returns the connection.
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

      # Best-effort: failures (network, config, EB rejecting the session)
      # are intentionally swallowed — the local "closed" state is what
      # matters from the user's POV.
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
