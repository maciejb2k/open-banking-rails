# frozen_string_literal: true

module EnableBanking
  module Api
    # Per-bank balance_type patterns:
    #   PKO, mBank: ITBD (interim booked) + ITAV (interim available)
    #     ITBD = booked, ITAV = ITBD minus card holds
    #   Revolut: only ITAV, reference_date lags ~5 days (no live refresh)
    class GetAccountBalances < Base
      def initialize(credential:, uid:)
        @credential = credential
        @uid = uid
      end

      def call
        client.get("/accounts/#{@uid}/balances")
      end
    end
  end
end
