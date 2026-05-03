# frozen_string_literal: true

module DataExchange
  module Resources
    # The two ownership shapes are mutually exclusive (DB-enforced via
    # `bank_accounts_ownership_xor`): manual=false → tpp_credential set;
    # manual=true → manual_owner set. `manual` is permitted but NOT
    # updatable - flipping ownership shape would violate the XOR check.
    class BankAccountResource < Base
      key :bank_accounts
      model BankAccount
      depends_on :tpp_credentials, :bank_connections

      def permitted_attributes
        %i[
          uid iban bban all_account_ids currency
          name product details cash_account_type usage status
          account_servicer raw_account_resource raw_details
          details_fetched_at balances_synced_at transactions_synced_at
          raw_balances manual
          created_at updated_at
        ]
      end

      # Frozen on overwrite: uid (natural key), manual (XOR), status
      # (destination owns lifecycle), synced_at timestamps.
      def updatable_attributes
        %i[
          iban bban all_account_ids currency
          name product details cash_account_type usage
          account_servicer raw_account_resource raw_details
          raw_balances
        ]
      end

      def natural_key_attrs
        %i[uid]
      end

      def scope_for_export
        BankAccount.where(tpp_credential_id: user.tpp_credentials.select(:id))
                   .or(BankAccount.where(manual_owner_id: user.id))
      end

      def references(record)
        if record.manual
          {}
        else
          {
            tpp_credential_id:          [ :tpp_credentials,   record.tpp_credential_id ],
            current_bank_connection_id: [ :bank_connections,  record.current_bank_connection_id ]
          }
        end
      end

      # Synced accounts own via tpp_credential_id (handled by remap_foreign_keys).
      def stamp_ownership!(attrs, _refs)
        attrs["manual_owner_id"] = user.id if attrs["manual"]
      end
    end
  end
end
