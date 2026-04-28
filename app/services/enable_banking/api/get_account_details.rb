# frozen_string_literal: true

module EnableBanking
  module Api
    # GET /accounts/{uid}/details — fuller per-account metadata than what
    # POST /sessions returns.
    #
    # Returns AccountResource: account_id, all_account_ids, account_servicer
    # (BIC + bank name), name (holder), cash_account_type (CACC/SVGS/CARD),
    # usage (PRIV/COMM), product, details, postal_address, identification_hash(es).
    #
    # Per-bank fill rates differ (PoC findings):
    #   PKO: account_servicer.bic_fi populated (BPKOPLPW), name often empty
    #   mBank: postal_address populated, account_servicer null (use static map → BREXPLPW)
    #   Revolut: all_account_ids has both PL and LT IBANs
    class GetAccountDetails < Base
      def initialize(credential:, uid:)
        @credential = credential
        @uid = uid
      end

      def call
        client.get("/accounts/#{@uid}/details")
      end
    end
  end
end
