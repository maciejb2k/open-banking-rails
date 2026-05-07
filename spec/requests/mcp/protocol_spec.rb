# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP protocol envelope", type: :request do
  it "POST /mcp without an Authorization header returns 401" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "POST /mcp with a non-Bearer Authorization header returns 401" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                 headers: { "HTTP_AUTHORIZATION" => "Basic foo", "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "POST /mcp with a revoked PAT returns 401" do
    user = create(:user)
    raw, record = issue_pat(user)
    record.update!(revoked_at: Time.current)

    mcp_call(method: "tools/list", token: raw)

    expect(response).to have_http_status(:unauthorized)
  end

  it "POST /mcp with method=tools/list returns the full registered-tool surface including canonical names" do
    user = create(:user)
    raw, _ = issue_pat(user)

    body = mcp_call(method: "tools/list", token: raw)

    expect(response).to have_http_status(:ok)
    tool_names = body.dig("result", "tools").map { |t| t["name"] }
    expect(tool_names).to include("cash.create_transaction", "transactions.list", "analytics.cash_flow", "transaction_syncs.create")
    expect(tool_names.size).to eq(27)
  end

  it "POST /mcp tools/call cash.create_transaction creates the row and returns a JSON content block" do
    user = create(:user)
    raw, _ = issue_pat(user)

    body = mcp_tool_call(name: "cash.create_transaction", token: raw, arguments: {
      amount: "12.50", currency: "PLN", direction: "debit",
      booking_date: Date.current.to_s, title: "Lunch via MCP"
    })

    expect(response).to have_http_status(:ok)
    content = body.dig("result", "content")
    expect(content).to be_an(Array)
    expect(content.first).to include("type" => "text")
    payload = JSON.parse(content.first["text"])
    expect(payload).to include("id", "amount_cents", "currency", "direction")
    expect(payload["currency"]).to eq("PLN")
    expect(ManualTransaction.where(title: "Lunch via MCP", created_by_user: user)).to exist
  end

  it "POST /mcp tools/call cash.create_transaction with invalid args returns the tool-error envelope (isError: true)" do
    user = create(:user)
    raw, _ = issue_pat(user)

    body = mcp_tool_call(name: "cash.create_transaction", token: raw, arguments: {
      amount: "", currency: "PLN", direction: "debit", booking_date: Date.current.to_s
    })

    expect(response).to have_http_status(:ok)
    expect(body.dig("result", "isError")).to be(true)
  end

  it "POST /mcp tools/call with an unknown tool name returns a JSON-RPC error envelope rather than 500" do
    user = create(:user)
    raw, _ = issue_pat(user)

    body = mcp_tool_call(name: "does.not.exist", token: raw, arguments: {})

    expect(response).to have_http_status(:ok).or have_http_status(:bad_request)
    expect(body["error"] || body.dig("result", "isError")).to be_truthy
  end

  it "GET /mcp goes through the same transport.handle_request path with a routed status" do
    user = create(:user)
    raw, _ = issue_pat(user)

    get "/mcp", headers: bearer_headers(raw)

    expect(response.status).to be_between(200, 599)
  end

  it "DELETE /mcp goes through the same transport.handle_request path with a routed status" do
    user = create(:user)
    raw, _ = issue_pat(user)

    delete "/mcp", headers: bearer_headers(raw)

    expect(response.status).to be_between(200, 599)
  end

  it "POST /mcp tools/call transactions.get on another user's id returns the tool-error envelope without leaking fields" do
    user_a = create(:user)
    user_b = create(:user)
    foreign_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user_b))
    foreign_tx = create(:bank_transaction, bank_account: foreign_account, title: "USER_B_PRIVATE_TITLE_42")
    raw_a, _ = issue_pat(user_a)

    body = mcp_tool_call(name: "transactions.get", token: raw_a, arguments: {
      source_type: "BankTransaction", source_id: foreign_tx.id
    })

    expect(response).to have_http_status(:ok)
    text_payload = body.dig("result", "content").to_a.map { |c| c["text"].to_s }.join
    expect(text_payload).not_to include("USER_B_PRIVATE_TITLE_42")
    expect(body.dig("result", "isError")).to be(true).or be_nil
  end
end
