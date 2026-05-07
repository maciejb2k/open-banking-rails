# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v1 analytics resources", type: :request do
  it "GET /api/v1/analytics/cash_flow returns totals + a date-bucketed series" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_get("/api/v1/analytics/cash_flow", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include("currency", "period", "totals", "series")
    expect(body["totals"]).to include("spend_cents", "income_cents", "net_cents")
    expect(body["period"]).to include("from", "to", "bucket")
    expect(body["series"]).to be_an(Array)
  end

  it "GET /api/v1/analytics/spend returns category-grouped rows with previous-period delta fields" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_get("/api/v1/analytics/spend", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include("currency", "period", "total_cents", "rows")
    expect(body["rows"]).to be_an(Array)
  end

  it "GET /api/v1/analytics/top_merchants returns the top spend merchants for the period" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_get("/api/v1/analytics/top_merchants", token: raw, params: { limit: 5 })

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include("currency", "period", "rows")
    expect(body["rows"]).to be_an(Array)
  end

  it "GET /api/v1/analytics/categories/:slug returns 404 for an unknown slug" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_get("/api/v1/analytics/categories/does-not-exist", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /api/v1/analytics/categories/:slug returns 404 for another user's slug" do
    user = create(:user)
    other = create(:user)
    foreign = create(:category, user: other, slug: "their-slug-only", path: "their_slug_only")
    raw, _ = issue_pat(user)

    api_get("/api/v1/analytics/categories/#{foreign.slug}", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /api/v1/analytics/categories/:slug returns the category drilldown shape" do
    user = create(:user)
    cat = create(:category, user: user, slug: "food", path: "food", name: "Food")
    raw, _ = issue_pat(user)

    api_get("/api/v1/analytics/categories/#{cat.slug}", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include("category", "currency", "period", "total_cents", "merchants", "subtree")
    expect(body["category"]).to include("id" => cat.id, "name" => cat.name, "slug" => cat.slug)
  end

  it "GET /api/v1/analytics/merchants/:slug returns 404 for an unknown slug" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_get("/api/v1/analytics/merchants/nope", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /api/v1/analytics/merchants/:slug returns 404 for another user's merchant" do
    user = create(:user)
    other = create(:user)
    foreign = create(:merchant, user: other, slug: "their-shop-only")
    raw, _ = issue_pat(user)

    api_get("/api/v1/analytics/merchants/#{foreign.slug}", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /api/v1/analytics/merchants/:slug returns the merchant drilldown shape with zero totals for an empty merchant" do
    user = create(:user)
    merch = create(:merchant, user: user, slug: "lonely-merch")
    raw, _ = issue_pat(user)

    api_get("/api/v1/analytics/merchants/#{merch.slug}", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include("merchant", "currency", "period", "total_cents", "count", "monthly_trend", "transactions", "pagination")
    expect(body["merchant"]).to include("id" => merch.id, "slug" => merch.slug)
    expect(body["total_cents"]).to eq(0)
    expect(body["count"]).to eq(0)
    expect(body["monthly_trend"]).to be_an(Array)
    if body["monthly_trend"].any?
      expect(body["monthly_trend"].first).to include("period", "amount_cents")
      expect(body["monthly_trend"].first["amount_cents"]).to eq(0)
    end
  end

  it "GET /api/v1/analytics/cash_flow honors a currency override that exists in the user's data" do
    user = create(:user)
    eur_account = create(:bank_account, :eur, tpp_credential: create(:tpp_credential, user: user))
    create(:bank_transaction, bank_account: eur_account, currency: "EUR")
    raw, _ = issue_pat(user)

    api_get("/api/v1/analytics/cash_flow", token: raw, params: { currency: "EUR" })

    body = JSON.parse(response.body)
    expect(body["currency"]).to eq("EUR")
  end

  it "GET /api/v1/analytics/cash_flow rejects an invalid date with 400" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_get("/api/v1/analytics/cash_flow", token: raw, params: { from: "garbage" })

    expect(response).to have_http_status(:bad_request)
  end
end
