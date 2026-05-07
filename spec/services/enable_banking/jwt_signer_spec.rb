# frozen_string_literal: true

require "rails_helper"
require "jwt"

RSpec.describe EnableBanking::JwtSigner do
  it "signs a JWT carrying the EB-required iss/aud/kid claims and a 1-hour TTL" do
    credential = create(:tpp_credential)

    freeze_time do
      token = described_class.new(credential).sign
      payload, headers = JWT.decode(token, nil, false)

      expect(token.split(".").length).to eq(3)
      expect(headers).to include("typ" => "JWT", "alg" => "RS256", "kid" => credential.application_id)
      expect(payload).to include("iss" => "enablebanking.com", "aud" => "api.enablebanking.com")
      expect(payload["iat"]).to eq(Time.current.to_i)
      expect(payload["exp"]).to eq(Time.current.to_i + 3600)
    end
  end

  it "produces a token that verifies against the matching public key under RS256" do
    private_key = OpenSSL::PKey::RSA.new(2048)
    credential = create(:tpp_credential, private_key_pem: private_key.to_pem)

    token = described_class.new(credential).sign
    decoded, = JWT.decode(token, private_key.public_key, true, algorithm: "RS256")

    expect(decoded["iss"]).to eq("enablebanking.com")
  end

  it "raises EnableBanking::ConfigError when the credential's PEM is malformed" do
    EnableBanking::Error
    credential = build_stubbed(:tpp_credential, application_id: "x", private_key_pem: "not-a-key")

    expect {
      described_class.new(credential).sign
    }.to raise_error(EnableBanking::ConfigError, /Invalid RSA private key/)
  end

  it "produces tokens that only verify against their own credential's public key" do
    key_a = OpenSSL::PKey::RSA.new(2048)
    key_b = OpenSSL::PKey::RSA.new(2048)
    cred_a = create(:tpp_credential, private_key_pem: key_a.to_pem)
    cred_b = create(:tpp_credential, private_key_pem: key_b.to_pem)

    token_a = described_class.new(cred_a).sign
    token_b = described_class.new(cred_b).sign

    expect(token_a).not_to eq(token_b)
    expect { JWT.decode(token_a, key_a.public_key, true, algorithm: "RS256") }.not_to raise_error
    expect { JWT.decode(token_a, key_b.public_key, true, algorithm: "RS256") }.to raise_error(JWT::VerificationError)
  end

  it "stamps exp at iat + TTL_SECONDS so a clock advanced past TTL invalidates the token's exp claim" do
    credential = create(:tpp_credential)

    issued_token = nil
    freeze_time do
      issued_token = described_class.new(credential).sign
    end

    payload, = JWT.decode(issued_token, nil, false)
    expect(payload["exp"] - payload["iat"]).to eq(described_class::TTL_SECONDS)
  end
end
