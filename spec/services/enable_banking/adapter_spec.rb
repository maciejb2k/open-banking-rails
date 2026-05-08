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

  it "translates a Faraday transport timeout into Result(success: false, status: 0) without raising" do
    credential = create(:tpp_credential)
    stub_request(:get, "https://api.enablebanking.com/aspsps").to_timeout

    result = described_class.new(credential).get("/aspsps")

    expect(result.success?).to be(false)
    expect(result.status).to eq(0)
    expect(result.error).to match(/(Timeout|ConnectionFailed|execution expired)/i)
  end

  it "maps a 5xx response to Result(success: false) preserving the upstream status" do
    credential = create(:tpp_credential)
    stub_request(:get, "https://api.enablebanking.com/aspsps")
      .to_return(status: 502, body: { "error" => "Bad Gateway" }.to_json, headers: { "Content-Type" => "application/json" })

    result = described_class.new(credential).get("/aspsps")

    expect(result.success?).to be(false)
    expect(result.status).to eq(502)
    expect(result.error).to match(/Bad Gateway/)
  end

  it "yields a string error when the body is non-JSON HTML (proxy fallback page)" do
    credential = create(:tpp_credential)
    stub_request(:get, "https://api.enablebanking.com/aspsps")
      .to_return(status: 503, body: "<html><body>maintenance</body></html>", headers: { "Content-Type" => "text/html" })

    result = described_class.new(credential).get("/aspsps")

    expect(result.success?).to be(false)
    expect(result.status).to eq(503)
    expect(result.error).to include("maintenance")
  end

  it "sends PSU-IP-Address and PSU-User-Agent headers when both ENV vars are set (mBank requirement)" do
    credential = create(:tpp_credential)
    stub_request(:get, "https://api.enablebanking.com/aspsps")
      .with(headers: { "PSU-IP-Address" => "203.0.113.7", "PSU-User-Agent" => "test-agent/1.0" })
      .to_return(status: 200, body: { "aspsps" => [] }.to_json, headers: { "Content-Type" => "application/json" })

    ENV["PSU_IP_ADDRESS"] = "203.0.113.7"
    ENV["PSU_USER_AGENT"] = "test-agent/1.0"
    begin
      result = described_class.new(credential).get("/aspsps")
      expect(result.success?).to be(true)
    ensure
      ENV.delete("PSU_IP_ADDRESS")
      ENV.delete("PSU_USER_AGENT")
    end
  end

  it "omits PSU headers entirely when ENV vars are unset" do
    credential = create(:tpp_credential)
    stub_request(:get, "https://api.enablebanking.com/aspsps")
      .to_return(status: 200, body: { "aspsps" => [] }.to_json, headers: { "Content-Type" => "application/json" })

    described_class.new(credential).get("/aspsps")

    expect(WebMock).to have_requested(:get, "https://api.enablebanking.com/aspsps")
      .with { |req| !req.headers.key?("Psu-Ip-Address") && !req.headers.key?("Psu-User-Agent") }
  end
end
