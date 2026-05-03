# frozen_string_literal: true

module DataExchange
  module Resources
    # session_id is the natural key - `(tpp_credential_id, bank_slug)` doesn't
    # work because rotation leaves multiple rows per slug, and session_id is
    # encrypted non-deterministically so `find_by` won't match the ciphertext.
    # We compare plaintext in Ruby (n is a handful per user).
    #
    # `replaces_id` self-FK silently drops to nil when the predecessor isn't
    # on the destination - the chain trims but the connection is still usable.
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

      # last_*_at and last_error describe what THIS instance has done with
      # the consent - don't revert those on overwrite.
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
