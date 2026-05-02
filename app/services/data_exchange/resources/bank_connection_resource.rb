# frozen_string_literal: true

module DataExchange
  module Resources
    # PSD2 bank session/consent. Owned indirectly via TppCredential — scoping
    # joins through `tpp_credentials.user_id`.
    #
    # Natural key is `session_id`: it's the bank-issued OAuth-like session
    # token, semantically the unique identity of the consent. We can't use
    # `(tpp_credential_id, bank_slug)` because the rotation flow leaves
    # multiple rows per slug (expired predecessor + authorized successor),
    # and we can't `find_by(session_id: ...)` because the column is encrypted
    # non-deterministically. So: load the user's connections, compare in
    # Ruby. n is small (a handful per user) and AES-GCM decrypt is sub-ms.
    #
    # `replaces_id` is an optional self-FK for the rotation chain. We export
    # it through `references` so the chain is preserved when both predecessor
    # and successor are in the bundle. If the predecessor is missing on the
    # destination, the FK silently drops to nil — the chain trims, the
    # connection is still usable, but rotation history is lost. Acceptable.
    class BankConnectionResource < Base
      key :bank_connections
      model BankConnection
      depends_on :tpp_credentials

      def permitted_attributes
        %i[
          bank_slug bank_country bank_name
          status psu_type
          session_id psu_id_hash raw_session_payload
          access_balances access_transactions
          valid_until authorized_at
          last_refreshed_at last_synced_at closed_at last_error
          created_at updated_at
        ]
      end

      # Destination owns its own interaction history — last_*_at and last_error
      # describe what THIS instance has done with the consent. Don't revert
      # those on overwrite. session_id and the access flags are immutable
      # properties of the consent itself, safe to overwrite.
      def updatable_attributes
        %i[
          bank_country bank_name
          psu_type
          session_id psu_id_hash raw_session_payload
          access_balances access_transactions
          valid_until authorized_at
        ]
      end

      def natural_key_attrs
        %i[session_id]
      end

      def scope_for_export
        BankConnection.joins(:tpp_credential)
                      .where(tpp_credentials: { user_id: user.id })
      end

      # session_id is encrypted non-deterministically — `find_by` against the
      # ciphertext column won't match. Iterate + compare plaintext in Ruby.
      def find_existing(attrs)
        target = attrs["session_id"]
        return nil if target.blank?

        scope_for_export.find { |c| c.session_id == target }
      end

      def references(record)
        {
          tpp_credential_id: [ :tpp_credentials, record.tpp_credential_id ],
          replaces_id:       [ :bank_connections, record.replaces_id ]
        }
      end
    end
  end
end
