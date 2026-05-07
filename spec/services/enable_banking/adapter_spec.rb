# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::Client do
  before do
    allow(EnableBanking::Client).to receive(:new).and_call_original
  end

  it "issues a GET with a Bearer JWT and returns a successful Result on a 200 JSON response" do
    credential = create(:tpp_credential)
    stub_request(:get, "https://api.enablebanking.com/aspsps")
      .with(headers: { "Authorization" => /Bearer .+/ })
      .to_return(status: 200, body: { "aspsps" => [ { "name" => "Fake Bank" } ] }.to_json, headers: { "Content-Type" => "application/json" })

    result = described_class.new(credential).get("/aspsps")

    expect(result.success?).to be(true)
    expect(result.status).to eq(200)
    expect(result.data["aspsps"].first["name"]).to eq("Fake Bank")
  end

  it "issues a POST with a JSON body and Content-Type set, surfacing the response as Result.data" do
    credential = create(:tpp_credential)
    stub_request(:post, "https://api.enablebanking.com/auth")
      .with(
        headers: { "Authorization" => /Bearer .+/, "Content-Type" => "application/json" },
        body: { state: "abc" }.to_json
      )
      .to_return(status: 200, body: { "url" => "https://bank.example/redirect" }.to_json, headers: { "Content-Type" => "application/json" })

    result = described_class.new(credential).post("/auth", { state: "abc" })

    expect(result.success?).to be(true)
    expect(result.data["url"]).to eq("https://bank.example/redirect")
  end

  it "maps a 4xx JSON body to Result(success: false) with composed error from error/message/detail" do
    credential = create(:tpp_credential)
    stub_request(:get, "https://api.enablebanking.com/sessions/x")
      .to_return(status: 400, body: { "error" => "E", "message" => "M", "detail" => "D" }.to_json, headers: { "Content-Type" => "application/json" })

    result = described_class.new(credential).get("/sessions/x")

    expect(result.success?).to be(false)
    expect(result.status).to eq(400)
    expect(result.error).to eq("E - M - D")
  end

  it "translates Faraday::ConnectionFailed into Result(success: false, status: 0) without raising" do
    credential = create(:tpp_credential)
    stub_request(:get, "https://api.enablebanking.com/aspsps")
      .to_raise(Faraday::ConnectionFailed.new("getaddrinfo: down"))

    result = described_class.new(credential).get("/aspsps")

    expect(result.success?).to be(false)
    expect(result.status).to eq(0)
    expect(result.error).to match(/ConnectionFailed/)
  end
end
