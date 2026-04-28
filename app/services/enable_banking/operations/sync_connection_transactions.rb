# frozen_string_literal: true

module EnableBanking
  module Operations
    # Fans out SyncAccountTransactions over every active account on a
    # BankConnection. Failures are caught per-account so a single 4xx
    # (e.g. PKO returning 400 for some edge case) doesn't tank the run.
    # See PoC bin/get_transactions.rb — same per-account rescue pattern.
    #
    # Optional `on_account_synced:` callback receives a hash describing
    # the outcome of each account as soon as it's done. Used by
    # TransactionSyncJob to push live progress to the OperationRun.
    # Synchronous callers (rake, console) can ignore it.
    #
    # Returns hash keyed by bank_account_id with each Outcome (or Failed exception).
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
