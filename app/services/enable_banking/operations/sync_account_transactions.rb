# frozen_string_literal: true

module EnableBanking
  module Operations
    # Pulls transactions for a single BankAccount and persists them as
    # BankTransaction rows. Idempotent — duplicates (by bank_account_id +
    # external_id) are skipped.
    #
    # Booked PSD2 transactions are immutable, so we don't update existing
    # rows. Pending → booked transitions are not yet handled (see PoC
    # open-questions.md — needs PDNG observation in real time first).
    #
    # date_from defaults to BackfillWindow per bank for first sync, otherwise
    # `transactions_synced_at - overlap` for incremental.
    #
    # Returns Result struct with counts. Raises Failed on API failure.
    class SyncAccountTransactions < Base
      Failed = Class.new(StandardError)

      Outcome = Struct.new(:inserted, :skipped, :pages_fetched, :truncated, :date_from, :date_to, keyword_init: true)

      INCREMENTAL_OVERLAP = 7.days

      def initialize(account, date_from: nil, date_to: nil)
        @account = account
        @date_from = date_from
        @date_to = date_to
      end

      def call
        from = (@date_from || resolve_default_date_from).to_date
        to   = (@date_to   || Date.current).to_date

        result = Api::GetAccountTransactions.call(
          credential: @account.tpp_credential,
          uid: @account.uid,
          date_from: from,
          date_to: to
        )
        raise Failed, result.error_message if result.failure?

        outcome = persist(result.data, from, to)
        @account.update!(transactions_synced_at: Time.current)
        outcome
      end

      private

      def persist(data, from, to)
        inserted = 0
        skipped  = 0
        fetched_at = Time.current

        BankTransaction.transaction do
          Array(data["transactions"]).each do |payload|
            attrs = TransactionNormalizer.call(payload, bank_account: @account, fetched_at: fetched_at)

            record = @account.bank_transactions.find_or_initialize_by(external_id: attrs[:external_id])
            if record.new_record?
              record.assign_attributes(attrs)
              record.save!
              inserted += 1
            else
              skipped += 1
            end
          end
        end

        Outcome.new(
          inserted: inserted,
          skipped: skipped,
          pages_fetched: data["pages_fetched"],
          truncated: data["truncated"],
          date_from: from,
          date_to: to
        )
      end

      def resolve_default_date_from
        if @account.transactions_synced_at.present?
          (@account.transactions_synced_at - INCREMENTAL_OVERLAP).to_date
        else
          BackfillWindow.default_date_from(@account.current_bank_connection&.bank_slug.to_s)
        end
      end
    end
  end
end
