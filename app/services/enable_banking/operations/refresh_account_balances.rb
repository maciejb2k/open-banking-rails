# frozen_string_literal: true

module EnableBanking
  module Operations
    # Pulls the latest balance snapshot from EB and stores it on the
    # BankAccount. raw_balances is encrypted at rest (see BankAccount).
    #
    # Raises Failed on API failure.
    class RefreshAccountBalances < Base
      Failed = Class.new(StandardError)

      def initialize(account)
        @account = account
      end

      def call
        result = Api::GetAccountBalances.call(
          credential: @account.tpp_credential,
          uid: @account.uid
        )
        raise Failed, result.error_message if result.failure?

        @account.update!(
          raw_balances: result.data.to_json,
          balances_synced_at: Time.current
        )
        @account
      end
    end
  end
end
