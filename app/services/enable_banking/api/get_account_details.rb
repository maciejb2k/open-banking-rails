# frozen_string_literal: true

module EnableBanking
  module Api
    # Per-bank fill rates:
    #   PKO:     account_servicer.bic_fi populated (BPKOPLPW), name often empty
    #   mBank:   postal_address populated, account_servicer null
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
