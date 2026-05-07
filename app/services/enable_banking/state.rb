# frozen_string_literal: true

module EnableBanking
  # CSRF protection for the OAuth-like auth flow - signed payload sent in
  # POST /auth body, echoed back by the bank, verified on callback. Without
  # it, an attacker could link their bank account to the victim's app.
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
        raw = Rails.application.message_verifier(PURPOSE).verified(token)
        return nil if raw.nil?
        data = raw.respond_to?(:symbolize_keys) ? raw.symbolize_keys : raw
        return nil if data[:expires_at].to_i < Time.current.to_i
        data
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage
        nil
      end
    end
  end
end
