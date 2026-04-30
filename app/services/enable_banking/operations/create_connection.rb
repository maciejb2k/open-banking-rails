# frozen_string_literal: true

module EnableBanking
  module Operations
    # Materializes the OAuth-like callback into a BankConnection +
    # BankAccount records in a single transaction.
    #
    # Combines:
    #   - Api::CreateSession (exchange `code` for full session payload)
    #   - building BankConnection from session payload
    #   - upserting BankAccounts from the FULL account info
    #     (only POST /sessions returns full per-account data — see
    #     Api::CreateSession comment)
    #   - marking the previous connection as "replaced" (audit trail kept)
    #
    # Returns the freshly-created BankConnection, or raises Failed.
    class CreateConnection < Base
      Failed = Class.new(StandardError)

      def initialize(credential:, code:, state:)
        @credential = credential
        @code = code
        @state = state
      end

      def call
        result = Api::CreateSession.call(credential: @credential, code: @code)
        raise Failed, "Could not create session: #{result.error_message}" if result.failure?

        BankConnection.transaction do
          old_connection = find_replaces_target
          bc = build_connection(result.data, old_connection)
          upsert_accounts(bc, result.data)
          mark_replaced(old_connection)
          bc
        end
      rescue ActiveRecord::RecordInvalid => e
        raise Failed, "Could not save records: #{e.message}"
      end

      private

      def build_connection(payload, old_connection)
        @credential.bank_connections.create!(
          bank_slug: @state[:aspsp_name].to_s.parameterize(separator: "_"),
          bank_country: @state[:aspsp_country] || payload.dig("aspsp", "country"),
          bank_name: payload.dig("aspsp", "name") || @state[:aspsp_name],
          status: "authorized",
          psu_type: payload["psu_type"] || @state[:psu_type],
          session_id: payload["session_id"],
          psu_id_hash: payload["psu_id_hash"],
          access_balances: payload.dig("access", "balances"),
          access_transactions: payload.dig("access", "transactions"),
          valid_until: payload.dig("access", "valid_until"),
          authorized_at: payload["authorized"] || Time.current,
          raw_session_payload: payload.to_json,
          replaces: old_connection
        )
      end

      def upsert_accounts(bc, payload)
        Array(payload["accounts"]).each do |account|
          next unless account.is_a?(Hash) && account["uid"].present?

          ba = BankAccount.find_or_initialize_by(uid: account["uid"])
          ba.assign_attributes(
            tpp_credential: @credential,
            current_bank_connection: bc,  # repoint to new connection (old stays in DB)
            iban: account.dig("account_id", "iban"),
            bban: BankAccount.bban_from(account["account_id"]),
            all_account_ids: account["all_account_ids"] || [],
            currency: account["currency"],
            name: account["name"].presence || ba.name,
            product: account["product"] || ba.product,
            details: account["details"] || ba.details,
            cash_account_type: account["cash_account_type"] || ba.cash_account_type,
            usage: account["usage"] || ba.usage,
            status: "active",
            account_servicer: account["account_servicer"] || ba.account_servicer,
            raw_account_resource: account
          )
          ba.save!

          # Refresh the per-account "Konto własne" merchant + iban rules so
          # transfers between own accounts get classified correctly on the
          # very first sync. Idempotent — safe to call on every save.
          Enrichment::OwnAccountMerchantSyncer.call(ba)
        end
      end

      # Mark replaced connection — KEEP the record (audit trail), don't destroy.
      # Accounts that were on the new payload have already been re-pointed
      # in #upsert_accounts. Accounts NOT in the new payload (user deselected
      # them at the bank) keep their old current_bank_connection_id — they
      # appear "stale" in the UI and stop syncing, but historical data is preserved.
      def mark_replaced(old_connection)
        old_connection&.update!(status: "replaced", closed_at: Time.current)
      end

      # Resolve `replaces_connection_id` from the signed state, scoped to the
      # current credential. Returns nil if missing or if it points to a connection
      # that doesn't belong to this credential (defense-in-depth).
      def find_replaces_target
        id = @state[:replaces_connection_id]
        return nil if id.blank?
        @credential.bank_connections.find_by(id: id)
      end
    end
  end
end
