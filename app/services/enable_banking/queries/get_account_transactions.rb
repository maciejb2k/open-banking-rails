# frozen_string_literal: true

module EnableBanking
  module Queries
    # GET /accounts/{uid}/transactions — paginated transactions list.
    #
    # Auto-paginates via `continuation_key` and aggregates pages into a single
    # Result. Returns the flattened transactions array as `data["transactions"]`,
    # plus `data["pages_fetched"]` and `data["truncated"]` (true if max_pages cap hit).
    #
    # Query parameters:
    #   date_from, date_to  YYYY-MM-DD (inclusive, UTC)
    #   transaction_status  BOOK | PDNG | INFO | OTHR
    #                       Note: PKO returns 400 ASPSP_ERROR for PDNG; default
    #                       (no filter) returns BOOK only on most banks.
    #
    # Per-bank history horizons (PoC findings, silently truncate if exceeded):
    #   Revolut: ~90 days (strict PSD2)
    #   PKO BP:  ~26 months
    #   mBank:   inconclusive (constant 51 tx in tests, low activity sample)
    #
    # Each transaction shape per bank documented in PoC docs/banks/*.md.
    class GetAccountTransactions < Base
      DEFAULT_MAX_PAGES = 100  # safety cap; ~5000 tx with EB's 50/page typical

      def initialize(credential:, uid:, date_from: nil, date_to: nil,
                     transaction_status: nil, max_pages: DEFAULT_MAX_PAGES)
        @credential = credential
        @uid = uid
        @date_from = date_from
        @date_to = date_to
        @transaction_status = transaction_status
        @max_pages = max_pages
      end

      def call
        all_transactions = []
        continuation_key = nil
        pages = 0
        last_response = nil

        loop do
          pages += 1
          result = client.get("/accounts/#{@uid}/transactions", page_params(continuation_key))
          return result if result.failure?

          all_transactions.concat(Array(result.data["transactions"]))
          continuation_key = result.data["continuation_key"]
          last_response = result

          break if continuation_key.nil? || continuation_key.empty?
          break if pages >= @max_pages
        end

        Result.new(
          success: true,
          status: last_response.status,
          data: {
            "transactions" => all_transactions,
            "pages_fetched" => pages,
            "truncated" => continuation_key.present?
          },
          headers: last_response.headers,
          error: nil
        )
      end

      private

      def page_params(continuation_key)
        params = {}
        params[:date_from] = @date_from.to_s if @date_from
        params[:date_to] = @date_to.to_s if @date_to
        params[:transaction_status] = @transaction_status if @transaction_status
        params[:continuation_key] = continuation_key if continuation_key
        params
      end
    end
  end
end
