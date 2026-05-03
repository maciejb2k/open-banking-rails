# frozen_string_literal: true

module EnableBanking
  module Operations
    # Only overwrites fields the API actually returned - per-bank fill rates
    # differ (see Api::GetAccountDetails).
    class RefreshAccountDetails < Base
      Failed = Class.new(StandardError)

      def initialize(account)
        @account = account
      end

      def call
        result = Api::GetAccountDetails.call(
          credential: @account.tpp_credential,
          uid: @account.uid
        )
        raise Failed, result.error_message if result.failure?

        d = result.data
        @account.update!(
          raw_details: d,
          details_fetched_at: Time.current,
          iban: d.dig("account_id", "iban") || @account.iban,
          bban: BankAccount.bban_from(d["account_id"]) || @account.bban,
          all_account_ids: d["all_account_ids"] || @account.all_account_ids,
          currency: d["currency"] || @account.currency,
          name: d["name"].presence || @account.name,
          product: d["product"] || @account.product,
          details: d["details"] || @account.details,
          cash_account_type: d["cash_account_type"] || @account.cash_account_type,
          usage: d["usage"] || @account.usage,
          account_servicer: d["account_servicer"] || @account.account_servicer
        )

        # Revolut only exposes the second (LT) IBAN via this endpoint, not the
        # initial /sessions payload - re-sync after refreshing details.
        Enrichment::OwnAccountMerchantSyncer.call(@account)

        @account
      end
    end
  end
end
