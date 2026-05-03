# frozen_string_literal: true

module EnableBanking
  module Operations
    # Per-account rescue so a single 4xx doesn't tank the run. The
    # `on_account_synced:` callback drives live progress in
    # TransactionSyncJob.
    class SyncConnectionTransactions < Base
      Failed = Class.new(StandardError)

      def initialize(connection, date_from: nil, date_to: nil, on_account_synced: nil)
        @connection = connection
        @date_from = date_from
        @date_to = date_to
        @on_account_synced = on_account_synced
      end

      def call
        results = {}
        @connection.current_bank_accounts.active.order(:id).each do |account|
          outcome = sync_one(account)
          results[account.id] = outcome
          @on_account_synced&.call(account: account, outcome: outcome)
        end

        @connection.update!(last_synced_at: Time.current)
        results
      end

      private

      def sync_one(account)
        SyncAccountTransactions.call(
          account,
          date_from: @date_from,
          date_to: @date_to
        )
      rescue SyncAccountTransactions::Failed => e
        e
      end
    end
  end
end
