# frozen_string_literal: true

module EnableBanking
  # CSRF protection for the OAuth-like auth flow:
  #
  #   1. UI generates a `state` token via .encode(...) — signed payload
  #   2. State is sent in POST /auth body
  #   3. Bank echoes it back in the redirect query string
  #   4. Callback controller calls .decode(state) and verifies authenticity
  #
  # Without this, an attacker could trick a logged-in user into linking
  # the attacker's bank account to the victim's app.
  class State
    PURPOSE = "enable_banking:oauth_state"
    TTL = 30.minutes

    class << self
      def encode(user_id:, tpp_credential_id:, aspsp_name:, aspsp_country:, psu_type:, replaces_connection_id: nil)
        payload = {
          user_id: user_id,
          tpp_credential_id: tpp_credential_id,
          aspsp_name: aspsp_name,
          aspsp_country: aspsp_country,
          psu_type: psu_type,
          replaces_connection_id: replaces_connection_id,
          expires_at: TTL.from_now.to_i,
          nonce: SecureRandom.hex(8)
        }
        Rails.application.message_verifier(PURPOSE).generate(payload)
      end

      def decode(token)
        return nil if token.blank?
        data = Rails.application.message_verifier(PURPOSE).verified(token)
        return nil if data.nil?
        return nil if data[:expires_at].to_i < Time.current.to_i
        data
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage
        nil
      end
    end
  end
end
