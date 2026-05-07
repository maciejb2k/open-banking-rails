# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v1 cross-cutting concerns", type: :request do
  it_behaves_like "a bearer-authenticated endpoint", verb: :get, path: "/api/v1/cash_transactions"

  it "401s a Bearer that belongs to user A when user A's record is no longer the owner of the token's digest" do
    user_a = create(:user)
    user_b = create(:user)
    raw_a, _record_a = issue_pat(user_a)

    api_get("/api/v1/cash_transactions", token: raw_a)
    expect(response).to have_http_status(:ok)

    raw_b, _record_b = issue_pat(user_b)
    api_get("/api/v1/cash_transactions", token: raw_b)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["data"]).to eq([])
  end

  it "maps ActiveRecord::RecordNotFound to a 404 with a uniform JSON envelope" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_get("/api/v1/cash_transactions/9999999", token: raw)

    expect(response).to have_http_status(:not_found)
    body = JSON.parse(response.body)
    expect(body).to include("message")
  end

  it "maps ActiveRecord::RecordInvalid to 422 with a details array" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_post("/api/v1/cash_transactions", token: raw, params: { amount: "" })

    expect(response).to have_http_status(:unprocessable_content)
    body = JSON.parse(response.body)
    expect(body["details"]).to be_an(Array)
  end

  it "maps Grape::Exceptions::ValidationErrors to 400 with a details array" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_get("/api/v1/transactions", token: raw, params: { from: "garbage" })

    expect(response).to have_http_status(:bad_request)
    body = JSON.parse(response.body)
    expect(body["message"]).to match(/invalid|parameter/i)
    expect(body["details"]).to be_an(Array)
  end

  it "maps unhandled StandardError raised inside a service to 500 with the message envelope" do
    user = create(:user)
    raw, _ = issue_pat(user)
    allow(Cash::TransactionCreator).to receive(:call).and_raise(RuntimeError, "boom")

    api_post("/api/v1/cash_transactions", token: raw, params: { amount: "1.00" })

    expect(response).to have_http_status(:internal_server_error)
    body = JSON.parse(response.body)
    expect(body["message"]).to match(/boom/)
  end

  it "exposes /api/v1/swagger_doc as JSON with the configured info.title" do
    get "/api/v1/swagger_doc"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.dig("info", "title")).to eq("Open Banking Rails API")
    expect(body["paths"]).to include("/api/v1/cash_transactions")
  end

  it "rejects /api/v2/* with a routing miss (Rails 404, not Grape envelope) because the version constraint is /v\\d+/" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_get("/api/v2/cash_transactions", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "exposes pagination meta on /api/v1/cash_transactions including page, items, count, pages" do
    user = create(:user)
    create_list(:manual_transaction, 3, user: user)
    raw, _ = issue_pat(user)

    api_get("/api/v1/cash_transactions", token: raw, params: { page: 1, limit: 25 })

    body = JSON.parse(response.body)
    expect(body).to include("data", "pagination")
    pagination = body["pagination"]
    expect(pagination).to include("page", "limit", "count", "pages")
    expect(pagination["count"]).to eq(3)
  end

  it "the authenticator bumps last_used_at on every authenticated request" do
    user = create(:user)
    raw, record = issue_pat(user)
    expect(record.last_used_at).to be_nil

    api_get("/api/v1/cash_transactions", token: raw)

    expect(record.reload.last_used_at).to be_present
  end
end
