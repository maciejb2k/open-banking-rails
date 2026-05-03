# frozen_string_literal: true

module DataExchange
  module Resources
    # `primary` flag is intentionally NOT in updatable_attributes - destination
    # decides primacy via `make_primary!`, never silently flipped on import.
    # last_verified_at / last_verification_error belong to the destination.
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
