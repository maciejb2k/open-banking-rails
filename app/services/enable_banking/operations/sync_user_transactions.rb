# frozen_string_literal: true

module EnableBanking
  module Operations
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
