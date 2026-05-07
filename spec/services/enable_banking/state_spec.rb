# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::State do
  it "round-trips every encoded field plus expires_at and a non-empty nonce" do
    token = described_class.encode(
      user_id: 7,
      tpp_credential_id: 11,
      aspsp_name: "Fake Bank",
      aspsp_country: "PL",
      psu_type: "personal",
      replaces_connection_id: 99
    )

    data = described_class.decode(token)

    expect(data).to include(
      user_id: 7,
      tpp_credential_id: 11,
      aspsp_name: "Fake Bank",
      aspsp_country: "PL",
      psu_type: "personal",
      replaces_connection_id: 99
    )
    expect(data[:expires_at]).to be_within(60).of(described_class::TTL.from_now.to_i)
    expect(data[:nonce]).to be_present
  end

  it "produces a different token on each encode call (nonce must vary)" do
    args = { user_id: 1, tpp_credential_id: 2, aspsp_name: "Bank", aspsp_country: "PL", psu_type: "personal" }
    token_a = described_class.encode(**args)
    token_b = described_class.encode(**args)

    expect(token_a).not_to eq(token_b)
  end

  it "decodes nil for tokens encoded under a different message_verifier purpose" do
    foreign_token = Rails.application.message_verifier("some_other_purpose").generate(
      { user_id: 1, expires_at: 30.minutes.from_now.to_i, nonce: "x" }
    )

    expect(described_class.decode(foreign_token)).to be_nil
  end

  it "decodes nil for blank, garbage, or empty tokens" do
    expect(described_class.decode(nil)).to be_nil
    expect(described_class.decode("")).to be_nil
    expect(described_class.decode("garbage.token")).to be_nil
  end

  it "decodes nil after the 30-minute TTL has passed" do
    token = described_class.encode(user_id: 1, tpp_credential_id: 2, aspsp_name: "Bank", aspsp_country: "PL", psu_type: "personal")

    travel_to(31.minutes.from_now) do
      expect(described_class.decode(token)).to be_nil
    end
  end

  it "round-trips replaces_connection_id when nil and when present" do
    nil_token = described_class.encode(user_id: 1, tpp_credential_id: 2, aspsp_name: "Bank", aspsp_country: "PL", psu_type: "personal", replaces_connection_id: nil)
    set_token = described_class.encode(user_id: 1, tpp_credential_id: 2, aspsp_name: "Bank", aspsp_country: "PL", psu_type: "personal", replaces_connection_id: 42)

    expect(described_class.decode(nil_token)[:replaces_connection_id]).to be_nil
    expect(described_class.decode(set_token)[:replaces_connection_id]).to eq(42)
  end
end
