# frozen_string_literal: true

module EnableBanking
  module Api
    # POST /sessions — exchange the `code` returned from the bank redirect
    # for an authorized session.
    #
    # Returns:
    #   { session_id, accounts: [...full account objects...],
    #     aspsp, psu_type, access }
    #
    # IMPORTANT (PoC finding): the `accounts` array here contains FULL
    # account info (iban, currency, name, product, etc.). This is the only
    # place to get that without an extra GET /accounts/{uid}/details call —
    # the same field on GET /sessions/{id} is just an array of UID strings.
    #
    # Caller (controller / operation) creates the BankConnection record AND
    # the BankAccount records from this single response.
    class CreateSession < Base
      def initialize(credential:, code:)
        @credential = credential
        @code = code
      end

      def call
        client.post("/sessions", { code: @code })
      end
    end
  end
end
