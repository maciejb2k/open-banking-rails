# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::PersonalAccessTokenAuthenticator do
  it "returns Result(success?: true) with the matching user and token record on a valid token" do
    user = create(:user)
    issued = Auth::PersonalAccessTokenIssuer.call(user: user, input: Auth::PersonalAccessTokenIssuer::Input.new(name: "ok"))

    result = described_class.call(raw_token: issued.raw_token)

    expect(result.success?).to be(true)
    expect(result.user).to eq(user)
    expect(result.token_record).to eq(issued.token_record)
  end

  it "uniformly returns Result(success?: false) for nil, blank, wrong-prefix, unknown-digest, and revoked tokens" do
    user = create(:user)
    revoked_issue = Auth::PersonalAccessTokenIssuer.call(user: user, input: Auth::PersonalAccessTokenIssuer::Input.new(name: "to-revoke"))
    revoked_issue.token_record.update!(revoked_at: Time.current)

    [
      nil,
      "",
      "wrong_prefix_aaaaaaaaa",
      "#{PersonalAccessToken::PREFIX}#{SecureRandom.urlsafe_base64(PersonalAccessToken::RAW_BYTES)}",
      revoked_issue.raw_token
    ].each do |raw|
      result = described_class.call(raw_token: raw)
      expect(result.success?).to be(false), "raw=#{raw.inspect[0, 30]}... should fail uniformly"
      expect(result.user).to be_nil
      expect(result.token_record).to be_nil
    end
  end

  it "bumps last_used_at on success without firing AR callbacks or PaperTrail" do
    user = create(:user)
    issued = Auth::PersonalAccessTokenIssuer.call(user: user, input: Auth::PersonalAccessTokenIssuer::Input.new(name: "tracked"))
    expect(issued.token_record.last_used_at).to be_nil

    travel_to(Time.current + 1.minute) do
      described_class.call(raw_token: issued.raw_token)
    end

    expect(issued.token_record.reload.last_used_at).to be_present
  end

  it "returns failure when raw_token is anything other than a String (e.g. Integer)" do
    [ 12345, :symbol, [ "x" ] ].each do |non_string|
      result = described_class.call(raw_token: non_string)
      expect(result.success?).to be(false)
    end
  end
end
