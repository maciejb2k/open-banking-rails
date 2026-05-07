# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::PersonalAccessTokenIssuer do
  it "returns Result(success?: true) carrying a fresh PersonalAccessToken record and the raw token" do
    user = create(:user)
    input = described_class::Input.new(name: "CLI laptop")

    result = described_class.call(user: user, input: input)

    expect(result.success?).to be(true)
    expect(result.token_record).to be_persisted
    expect(result.token_record.user).to eq(user)
    expect(result.token_record.name).to eq("CLI laptop")
    expect(result.raw_token).to start_with(PersonalAccessToken::PREFIX)
  end

  it "stores only the digest, not the raw token, and tracks the last four chars" do
    user = create(:user)
    input = described_class::Input.new(name: "Phone")

    result = described_class.call(user: user, input: input)

    expect(result.token_record.token_digest).to eq(PersonalAccessToken.digest_for(result.raw_token))
    expect(result.token_record.token_digest).not_to include(result.raw_token)
    expect(result.token_record.last_four).to eq(result.raw_token.last(4))
  end

  it "produces a raw token with the expected prefix and a base64url body of RAW_BYTES" do
    user = create(:user)
    input = described_class::Input.new(name: "Token A")

    result = described_class.call(user: user, input: input)

    expect(result.raw_token).to start_with(PersonalAccessToken::PREFIX)
    body = result.raw_token.delete_prefix(PersonalAccessToken::PREFIX)
    expect(body).to match(/\A[A-Za-z0-9_\-]+\z/)
    expect(Base64.urlsafe_decode64(body).bytesize).to eq(PersonalAccessToken::RAW_BYTES)
  end

  it "trims surrounding whitespace from the supplied name" do
    user = create(:user)
    input = described_class::Input.new(name: "  My token  ")

    result = described_class.call(user: user, input: input)

    expect(result.token_record.name).to eq("My token")
  end

  it "returns Result(success?: false) when (user, name) collides with an existing token" do
    user = create(:user)
    described_class.call(user: user, input: described_class::Input.new(name: "duplicate"))

    second = described_class.call(user: user, input: described_class::Input.new(name: "duplicate"))

    expect(second.success?).to be(false)
    expect(second.error).to match(/has already been taken|name/i)
  end
end
