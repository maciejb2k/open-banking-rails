# frozen_string_literal: true

module DataExchange
  module Resources
    # Reference resource — copy this shape when adding new resources.
    #
    # Notes specific to TppCredential:
    #   - Encrypted fields (`application_id`, `private_key_pem`) are read as
    #     plaintext via the `encrypts` accessors. Bundle carries plaintext;
    #     destination re-encrypts under its own AR encryption keys on save.
    #   - Natural key is (name, provider) scoped to the user. Two creds with
    #     the same name+provider for one user are not allowed in practice
    #     (the form steers users toward unique names) — collisions on import
    #     follow the chosen strategy.
    #   - `primary` flag is intentionally NOT in updatable_attributes — the
    #     destination decides primacy via `make_primary!`. Importing should
    #     never silently flip which credential is primary.
    #   - `last_verified_at` / `last_verification_error` belong to the
    #     destination's verification history, frozen on overwrite.
    class TppCredentialResource < Base
      key :tpp_credentials
      model TppCredential

      def permitted_attributes
        %i[
          name provider environment status redirect_url
          application_id private_key_pem public_cert_pem
          primary metadata
          created_at updated_at
        ]
      end

      def updatable_attributes
        %i[
          environment redirect_url
          application_id private_key_pem public_cert_pem
          metadata
        ]
      end

      def natural_key_attrs
        %i[name provider]
      end

      def scope_for_export
        TppCredential.where(user_id: user.id)
      end
    end
  end
end
