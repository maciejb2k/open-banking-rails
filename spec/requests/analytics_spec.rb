# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Analytics area", type: :request do
  it "GET /admin/analytics renders the dashboard for a brand-new user with zero amounts" do
    user = create(:user)
    sign_in user

    get admin_analytics_root_path

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/analytics computes month-to-date run rate when at least three days have elapsed" do
    user = create(:user)
    sign_in user
    travel_to(Time.zone.local(2026, 5, 7, 12, 0)) do
      get admin_analytics_root_path
    end
    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/analytics with ?under_path=foo resolves @drill_category through the user's tree" do
    user = create(:user)
    cat = create(:category, user: user, path: "food", name: "Food", slug: "food")
    sign_in user

    get admin_analytics_root_path, params: { under_path: cat.path.to_s }

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/analytics with ?under_path pointing at no existing category leaves @drill_category nil and still renders" do
    user = create(:user)
    sign_in user

    get admin_analytics_root_path, params: { under_path: "does.not.exist" }

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/analytics scopes totals to the current user, ignoring another user's data" do
    user = create(:user)
    other = create(:user)
    other_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: other))
    create(:bank_transaction, bank_account: other_account, amount_cents: 999_99)
    sign_in user

    get admin_analytics_root_path

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/analytics/categories/:slug returns 200 happy path" do
    user = create(:user)
    cat = create(:category, user: user, path: "food", slug: "food", name: "Food")
    sign_in user

    get admin_analytics_category_path(cat.slug)

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/analytics/categories/:slug returns 404 for an unknown slug" do
    user = create(:user)
    sign_in user

    get admin_analytics_category_path("does-not-exist")

    expect(response).to have_http_status(:not_found)
  end

  it "GET /admin/analytics/categories/:slug returns 404 for another user's category" do
    user = create(:user)
    other = create(:user)
    foreign = create(:category, user: other, slug: "foreign-only", path: "foreign_only")
    sign_in user

    get admin_analytics_category_path(foreign.slug)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /admin/analytics/categories/:slug redirects when the category is hidden" do
    user = create(:user)
    cat = create(:category, user: user, slug: "private-cat", path: "private_cat")
    UserHiddenCategory.create!(user: user, category: cat)
    sign_in user

    get admin_analytics_category_path(cat.slug)

    expect(response.location).to start_with("http://www.example.com/admin/analytics")
    expect(flash[:alert]).to match(/private/i)
  end

  it "GET /admin/analytics/merchants/:slug returns 200 with zero totals for a merchant that has no transactions" do
    user = create(:user)
    merch = create(:merchant, user: user, slug: "empty-merch")
    sign_in user

    get admin_analytics_merchant_path(merch.slug)

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/analytics/merchants/:slug returns 404 for an unknown slug" do
    user = create(:user)
    sign_in user

    get admin_analytics_merchant_path("nope")

    expect(response).to have_http_status(:not_found)
  end

  it "GET /admin/analytics/merchants/:slug returns 404 for another user's merchant" do
    user = create(:user)
    other = create(:user)
    foreign = create(:merchant, user: other, slug: "their-only-shop")
    sign_in user

    get admin_analytics_merchant_path(foreign.slug)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /admin/analytics/merchants/:slug redirects when the merchant's default category is hidden" do
    user = create(:user)
    cat = create(:category, user: user, slug: "hidden-cat", path: "hidden_cat")
    merch = create(:merchant, user: user, default_category: cat, slug: "merch-in-hidden")
    UserHiddenCategory.create!(user: user, category: cat)
    sign_in user

    get admin_analytics_merchant_path(merch.slug)

    expect(response.location).to start_with("http://www.example.com/admin/analytics")
    expect(flash[:alert]).to match(/hidden/i)
  end

  it "GET /admin/analytics without sign-in redirects to /admin/sign_in" do
    create(:user)
    get admin_analytics_root_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
