# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::Operations::VerifyCredential do
  it "returns :ok and stamps last_verified_at when /application succeeds and our redirect_url is among the registered ones" do
    credential = create(:tpp_credential, redirect_url: "https://app.example.com/callback")
    fake_eb.application_redirect_urls = [ "https://app.example.com/callback", "https://staging.example.com/callback" ]

    result = described_class.call(credential)

    expect(result.ok?).to be(true)
    expect(result.redirect_url_synced_to).to be_nil
    expect(credential.reload.status).to eq("active")
    expect(credential.last_verified_at).to be_present
    expect(credential.last_verification_error).to be_nil
    expect(credential.redirect_url).to eq("https://app.example.com/callback")
  end

  it "syncs the local redirect_url when EB has exactly ONE registered URL differing from ours" do
    credential = create(:tpp_credential, redirect_url: "https://stale.example.com/callback")
    fake_eb.application_redirect_urls = [ "https://canonical.example.com/callback" ]

    result = described_class.call(credential)

    expect(result.ok?).to be(true)
    expect(result.redirect_url_synced_to).to eq("https://canonical.example.com/callback")
    expect(credential.reload.redirect_url).to eq("https://canonical.example.com/callback")
    expect(result.message).to include("Local redirect_url updated")
  end

  it "returns :warning and does NOT sync when EB has multiple URLs and ours is not among them" do
    credential = create(:tpp_credential, redirect_url: "https://stale.example.com/callback")
    fake_eb.application_redirect_urls = [ "https://a.example.com/callback", "https://b.example.com/callback" ]

    result = described_class.call(credential)

    expect(result.warning?).to be(true)
    expect(result.redirect_url_synced_to).to be_nil
    expect(credential.reload.redirect_url).to eq("https://stale.example.com/callback")
    expect(result.message).to include("NOT in EB list")
    expect(result.message).to include("a.example.com")
    expect(result.message).to include("b.example.com")
    expect(credential.status).to eq("active")
  end

  it "returns :failed and flips credential.status to error with a stamped last_verification_error on API failure" do
    credential = create(:tpp_credential)
    fake_eb.simulate_failure(method: :get, path: "/application", status: 401, error: "Invalid signature")

    result = described_class.call(credential)

    expect(result.failed?).to be(true)
    expect(result.message).to include("Test failed")
    expect(credential.reload.status).to eq("error")
    expect(credential.last_verification_error).to include("HTTP 401")
    expect(credential.last_verification_error).to include("Invalid signature")
  end

  it "rescues EnableBanking::Error (malformed PEM, JWT signing failure) and returns :failed with a Configuration error message" do
    EnableBanking::Error
    credential = create(:tpp_credential)
    allow(EnableBanking::Api::GetApplication).to receive(:call).and_raise(EnableBanking::ConfigError, "Invalid RSA private key")

    result = described_class.call(credential)

    expect(result.failed?).to be(true)
    expect(result.message).to include("Configuration error")
    expect(result.message).to include("Invalid RSA private key")
    expect(credential.reload.status).to eq("error")
    expect(credential.last_verification_error).to eq("Invalid RSA private key")
  end

  it "leaves redirect_url untouched when EB returns no registered URLs (corner case)" do
    credential = create(:tpp_credential, redirect_url: "https://app.example.com/callback")
    fake_eb.application_redirect_urls = []

    result = described_class.call(credential)

    expect(result.ok?).to be(true)
    expect(result.redirect_url_synced_to).to be_nil
    expect(credential.reload.redirect_url).to eq("https://app.example.com/callback")
  end
end
