# frozen_string_literal: true

module EnableBanking
  module Operations
    # Idempotent on booked rows - PSD2 says booked transactions are immutable,
    # so a re-sync of an already-booked record is a no-op (skipped).
    # Pending rows are not immutable: a transaction can sit pending for a
    # while before the bank firms it up (status flips to booked, the amount
    # or dates can settle). On re-sync we overwrite pending rows with the
    # latest payload so the local copy keeps up.
    class SyncAccountTransactions < Base
      Failed = Class.new(StandardError)

      Outcome = Struct.new(:inserted, :updated, :skipped, :pages_fetched, :truncated, :date_from, :date_to, keyword_init: true)

      INCREMENTAL_OVERLAP = 7.days

      def initialize(account, date_from: nil, date_to: nil)
        @account = account
        @date_from = date_from
        @date_to = date_to
      end

      AUTH_FAILURE_STATUSES = [ 401, 403, 410 ].freeze

      def call
        from = (@date_from || resolve_default_date_from).to_date
        to   = (@date_to   || Date.current).to_date

        result = Api::GetAccountTransactions.call(
          credential: @account.tpp_credential,
          uid: @account.uid,
          date_from: from,
          date_to: to
        )
        if result.failure?
          probe_session_on_auth_failure(result.status)
          raise Failed, result.error_message
        end

        outcome = persist(result.data, from, to)
        @account.update!(transactions_synced_at: Time.current)
        outcome
      end

      private

      def persist(data, from, to)
        inserted = 0
        updated  = 0
        skipped  = 0
        fetched_at = Time.current
        user = @account.owner

        BankTransaction.transaction do
          Array(data["transactions"]).each do |payload|
            attrs = TransactionNormalizer.call(payload, bank_account: @account, fetched_at: fetched_at)
            attrs[:counterparty_kind] = Banking::CounterpartyResolver.call(
              payment_method:    attrs[:payment_method],
              counterparty_iban: attrs[:counterparty_iban],
              counterparty_name: attrs[:counterparty_name],
              user:              user
            )

            record = @account.bank_transactions.find_or_initialize_by(external_id: attrs[:external_id])
            if record.new_record?
              record.assign_attributes(attrs)
              record.save!
              inserted += 1
            elsif record.status == "pending"
              record.update!(attrs)
              updated += 1
            else
              skipped += 1
            end
          end
        end

        Outcome.new(
          inserted: inserted,
          updated: updated,
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

      # On an auth-shaped failure, the per-account endpoint can't tell us
      # whether the consent died or this was a transient glitch. The
      # session endpoint can - delegate the truth to RefreshConnection.
      # Swallow its Failed so the original sync error stays the user-visible
      # cause; RefreshConnection has already persisted whatever lifecycle
      # change was needed.
      def probe_session_on_auth_failure(status)
        return unless AUTH_FAILURE_STATUSES.include?(status)
        bc = @account.current_bank_connection
        return unless bc

        RefreshConnection.call(bc)
      rescue RefreshConnection::Failed
        nil
      end
    end
  end
end
