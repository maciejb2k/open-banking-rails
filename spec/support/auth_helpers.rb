# frozen_string_literal: true

# Bearer-token auth helpers for the JSON API (`/api/v1/*`) and MCP (`/mcp`)
# request specs. `issue_pat` goes through the real
# `Auth::PersonalAccessTokenIssuer` so request specs prove wiring end-to-end.
module AuthHelpers
  def issue_pat(user, name: "test")
    result = Auth::PersonalAccessTokenIssuer.call(
      user:  user,
      input: Auth::PersonalAccessTokenIssuer::Input.new(name: name)
    )
    raise "Could not issue PAT: #{result.error}" unless result.success?
    [ result.raw_token, result.token_record ]
  end

  def bearer_headers(token, extra = {})
    {
      "HTTP_AUTHORIZATION" => "Bearer #{token}",
      "CONTENT_TYPE"       => "application/json",
      "ACCEPT"             => "application/json"
    }.merge(extra)
  end

  def api_get(path, token: nil, params: {}, headers: {})
    get path, params: params, headers: bearer_headers(token, headers)
  end

  def api_post(path, token: nil, params: {}, headers: {})
    post path, params: params.to_json, headers: bearer_headers(token, headers)
  end

  def api_patch(path, token: nil, params: {}, headers: {})
    patch path, params: params.to_json, headers: bearer_headers(token, headers)
  end

  def api_delete(path, token: nil, params: {}, headers: {})
    delete path, params: params.to_json, headers: bearer_headers(token, headers)
  end

  def mcp_call(method:, params: {}, token:, id: 1)
    body = { jsonrpc: "2.0", id: id, method: method, params: params }
    post "/mcp", params: body.to_json, headers: bearer_headers(token)
    return nil if response.body.blank?
    JSON.parse(response.body)
  end

  def mcp_tool_call(name:, arguments: {}, token:, id: 1)
    mcp_call(
      method: "tools/call",
      params: { name: name, arguments: arguments },
      token:  token,
      id:     id
    )
  end
end

RSpec.shared_examples "a bearer-authenticated endpoint" do |verb:, path:|
  it "rejects requests with no Authorization header" do
    public_send(verb, path, headers: { "CONTENT_TYPE" => "application/json" })
    expect(response.status).to eq(401)
    expect(JSON.parse(response.body)).to include("message" => "Invalid or missing access token.")
  end

  it "rejects requests with a non-Bearer Authorization header" do
    public_send(verb, path, headers: { "HTTP_AUTHORIZATION" => "Basic foo", "CONTENT_TYPE" => "application/json" })
    expect(response.status).to eq(401)
  end

  it "rejects requests with a Bearer token missing the obrl_ prefix" do
    public_send(verb, path, headers: { "HTTP_AUTHORIZATION" => "Bearer not-a-pat", "CONTENT_TYPE" => "application/json" })
    expect(response.status).to eq(401)
  end

  it "rejects requests with a revoked PAT" do
    user = create(:user)
    raw, record = issue_pat(user)
    record.update!(revoked_at: Time.current)
    public_send(verb, path, headers: bearer_headers(raw))
    expect(response.status).to eq(401)
  end
end
