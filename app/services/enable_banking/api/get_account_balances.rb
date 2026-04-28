# frozen_string_literal: true

module EnableBanking
  module Api
    # GET /accounts/{uid}/balances — current balance snapshot.
    #
    # Returns { balances: [{ name, balance_amount{currency, amount},
    #                        balance_type, last_change_date_time, reference_date,
    #                        last_committed_transaction }] }
    #
    # balance_type enum: CLAV CLBD FWAV INFO ITAV ITBD OPAV OPBD OTHR PRCD VALU XPCD
    #
    # Per-bank patterns (PoC findings):
    #   PKO, mBank: ITBD (interim booked) + ITAV (interim available)
    #     ITBD = booked, ITAV = ITBD minus card holds
    #   Revolut: only ITAV, with reference_date that lags ~5 days behind
    #     (their API doesn't refresh balance live)
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
