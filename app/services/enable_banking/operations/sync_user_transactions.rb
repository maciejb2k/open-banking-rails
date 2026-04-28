# frozen_string_literal: true

module EnableBanking
  module Operations
    # Top-level orchestrator: sync transactions for every active connection
    # a user owns. Used by the recurring background sync (planned: 2x/day cron
    # — see TransactionSyncJob).
    #
    # Optional `on_account_synced:` callback is forwarded to each
    # SyncConnectionTransactions so progress is reported per-account, not
    # per-connection. Synchronous callers (rake, console) can ignore it.
    #
    # Returns {connection_id => {account_id => Outcome|Failed}}.
    class SyncUserTransactions < Base
      Failed = Class.new(StandardError)

      def initialize(user, date_from: nil, date_to: nil, on_account_synced: nil)
        @user = user
        @date_from = date_from
        @date_to = date_to
        @on_account_synced = on_account_synced
      end

      def call
        connections = BankConnection.for_user(@user).active.order(:id)

        connections.each_with_object({}) do |connection, acc|
          acc[connection.id] = SyncConnectionTransactions.call(
            connection,
            date_from: @date_from,
            date_to: @date_to,
            on_account_synced: @on_account_synced
          )
        end
      end
    end
  end
end
