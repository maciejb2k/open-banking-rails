# frozen_string_literal: true

module DataExchange
  module Resources
    # Synced bank account OR cash wallet. The two ownership shapes are
    # mutually exclusive (DB-enforced via `bank_accounts_ownership_xor`):
    #
    #   manual=false → tpp_credential set, manual_owner nil
    #   manual=true  → manual_owner set,    tpp_credential nil
    #
    # The resource handles both by branching on `manual` in `references` and
    # `stamp_ownership!`:
    #   - synced: tpp_credential_id + current_bank_connection_id come through
    #     the RefMap (parents are exported earlier in the topo order).
    #   - cash:   manual_owner_id is stamped from current_user, never copied
    #     from the bundle.
    #
    # `uid` is globally unique (DB index), so it's a clean natural key.
    # `manual` is in permitted but NOT in updatable — flipping ownership
    # shape on an existing account would violate the XOR check anyway.
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

      # Frozen on overwrite: uid (natural key, never reassigned), manual
      # (would break XOR), status (destination owns lifecycle), the synced_at
      # timestamps (destination's sync history).
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

      # Both ownership shapes in scope: synced accounts (via the user's TPP
      # credentials) OR cash wallets (manual_owner = user).
      def scope_for_export
        BankAccount.where(tpp_credential_id: user.tpp_credentials.select(:id))
                   .or(BankAccount.where(manual_owner_id: user.id))
      end

      def references(record)
        if record.manual
          {} # manual_owner_id is stamped from current_user on import
        else
          {
            tpp_credential_id:          [ :tpp_credentials,   record.tpp_credential_id ],
            current_bank_connection_id: [ :bank_connections,  record.current_bank_connection_id ]
          }
        end
      end

      # Cash wallets own through manual_owner_id. Synced accounts own through
      # tpp_credential_id, which is set via `references` → remap_foreign_keys,
      # so nothing to stamp here for that shape.
      def stamp_ownership!(attrs, _refs)
        attrs["manual_owner_id"] = user.id if attrs["manual"]
      end
    end
  end
end
