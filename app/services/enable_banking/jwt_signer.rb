# frozen_string_literal: true

module EnableBanking
  # Signs JWTs for authenticating against the Enable Banking API.
  #
  # Spec (https://enablebanking.com/docs/api/reference/):
  #   header  = { typ: "JWT", alg: "RS256", kid: <application_id> }
  #   payload = { iss: "enablebanking.com",
  #               aud: "api.enablebanking.com",
  #               iat: <unix>, exp: <unix> }
  #   max TTL = 86400s (24h). We use 1h.
  class JwtSigner
    TTL_SECONDS = 1.hour.to_i
    ISSUER = "enablebanking.com"
    AUDIENCE = "api.enablebanking.com"

    def initialize(credential)
      @credential = credential
    end

    def sign
      now = Time.current.to_i
      payload = {
        iss: ISSUER,
        aud: AUDIENCE,
        iat: now,
        exp: now + TTL_SECONDS
      }
      headers = { typ: "JWT", kid: @credential.application_id }
      JWT.encode(payload, private_key, "RS256", headers)
    end

    private

    def private_key
      OpenSSL::PKey::RSA.new(@credential.private_key_pem)
    rescue OpenSSL::PKey::RSAError => e
      raise EnableBanking::ConfigError, "Invalid RSA private key: #{e.message}"
    end
  end
end
