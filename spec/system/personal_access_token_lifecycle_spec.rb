# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Personal access token lifecycle journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "issues a PAT through the admin UI, exercises the JSON API and MCP server with the same Bearer, then revokes and deletes it across the full lifecycle", :papertrail do
    user = User.create!(email: "owner@example.test", password: "Password123!", name: "PAT Owner")
    Seeders::Categories.call(user)
    own_manual = create(:manual_transaction, user: user, title: "OWN_MANUAL_PAT_LIFECYCLE", amount_cents: 25_00, currency: "PLN")

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    visit "/admin/settings/preferences/api_tokens"
    expect(page).to have_text("No tokens yet")
    expect(user.personal_access_tokens.count).to eq(0)

    fill_in "personal_access_token[name]", with: "laptop"
    click_button "Generate token"

    expect(page).to have_text(/Token "laptop" generated/)
    raw_token = page.text[/obrl_[A-Za-z0-9_-]+/]
    expect(raw_token).to be_present
    expect(raw_token).to start_with(PersonalAccessToken::PREFIX)
    expect(page).to have_css("code", text: raw_token)
    expect(page).to have_text("laptop")
    expect(page).to have_text(/…#{Regexp.escape(raw_token.last(4))}/)
    expect(user.personal_access_tokens.count).to eq(1)

    visit "/admin/settings/preferences/api_tokens"
    expect(page).not_to have_css("code", text: raw_token)
    expect(page).not_to have_text(raw_token)
    expect(page).to have_text("laptop")
    expect(page).to have_text(/…#{Regexp.escape(raw_token.last(4))}/)

    api_get("/api/v1/cash_transactions", token: raw_token)
    expect(response).to have_http_status(:ok)
    api_titles = JSON.parse(response.body)["data"].map { |row| row["title"] }
    expect(api_titles).to include(own_manual.title)

    list_body = mcp_call(method: "tools/list", token: raw_token)
    expect(response).to have_http_status(:ok)
    tool_names = list_body.dig("result", "tools").map { |t| t["name"] }
    expect(tool_names).to include("transactions.list")

    list_call = mcp_tool_call(name: "transactions.list", token: raw_token, arguments: {})
    expect(response).to have_http_status(:ok)
    tool_payload = JSON.parse(list_call.dig("result", "content").first["text"])
    mcp_titles = tool_payload["transactions"].map { |t| t["title"] }
    expect(mcp_titles).to include(own_manual.title)

    expect(user.personal_access_tokens.first.reload.last_used_at).to be_present

    visit "/admin/settings/preferences/api_tokens"
    click_button "Revoke"
    expect(page).to have_text("Revoked")
    expect(page).to have_button("Delete")
    expect(user.personal_access_tokens.first.reload).to be_revoked

    api_get("/api/v1/cash_transactions", token: raw_token)
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)).to include("message" => "Invalid or missing access token.")

    mcp_call(method: "tools/list", token: raw_token)
    expect(response).to have_http_status(:unauthorized)

    visit "/admin/settings/preferences/api_tokens"
    click_button "Delete"
    expect(page).to have_text("No tokens yet")
    expect(user.personal_access_tokens.count).to eq(0)

    leak = PaperTrail::Version.all.find { |v| "#{v.object}#{v.object_changes}".include?(PersonalAccessToken::PREFIX) }
    expect(leak).to be_nil

    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
  end

  it "issues two tokens with distinct names and proves both authenticate the JSON API in parallel" do
    user = User.create!(email: "two@example.test", password: "Password123!", name: "Two PAT")

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    visit "/admin/settings/preferences/api_tokens"
    fill_in "personal_access_token[name]", with: "claude-desktop"
    click_button "Generate token"
    raw_a = page.text[/obrl_[A-Za-z0-9_-]+/]
    expect(raw_a).to be_present

    visit "/admin/settings/preferences/api_tokens"
    fill_in "personal_access_token[name]", with: "macbook-cli"
    click_button "Generate token"
    raw_b = page.text[/obrl_[A-Za-z0-9_-]+/]
    expect(raw_b).to be_present
    expect(raw_b).not_to eq(raw_a)

    api_get("/api/v1/cash_transactions", token: raw_a)
    expect(response).to have_http_status(:ok)
    api_get("/api/v1/cash_transactions", token: raw_b)
    expect(response).to have_http_status(:ok)

    user.personal_access_tokens.find_each do |pat|
      expect(pat.last_used_at).to be_present
    end
    expect(user.personal_access_tokens.pluck(:name)).to contain_exactly("claude-desktop", "macbook-cli")
  end

  it "blocks user A's PAT from reading user B's transactions on both the JSON API and the MCP server" do
    user_a = User.create!(email: "a@example.test", password: "Password123!", name: "User A")
    user_b = User.create!(email: "b@example.test", password: "Password123!", name: "User B")
    foreign_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user_b))
    foreign_tx = create(:bank_transaction, bank_account: foreign_account, title: "USER_B_TX_PRIVATE_42")

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user_a.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    visit "/admin/settings/preferences/api_tokens"
    fill_in "personal_access_token[name]", with: "laptop-a"
    click_button "Generate token"
    raw = page.text[/obrl_[A-Za-z0-9_-]+/]
    expect(raw).to be_present

    api_get("/api/v1/transactions/BankTransaction/#{foreign_tx.id}", token: raw)
    expect(response).to have_http_status(:not_found)

    body = mcp_tool_call(name: "transactions.get", token: raw, arguments: {
      source_type: "BankTransaction", source_id: foreign_tx.id
    })
    text = body.dig("result", "content").to_a.map { |c| c["text"].to_s }.join
    expect(text).not_to include("USER_B_TX_PRIVATE_42")
    expect(body.dig("result", "isError")).to be(true).or be_nil
  end

  it "rejects a duplicate token name with a 422 form rerender and does not add a second row" do
    user = User.create!(email: "collide@example.test", password: "Password123!", name: "Collide")

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    visit "/admin/settings/preferences/api_tokens"
    fill_in "personal_access_token[name]", with: "duplicate"
    click_button "Generate token"
    expect(page).to have_text(/Token "duplicate" generated/)
    expect(user.personal_access_tokens.count).to eq(1)

    visit "/admin/settings/preferences/api_tokens"
    fill_in "personal_access_token[name]", with: "duplicate"
    click_button "Generate token"

    expect(page.status_code).to eq(422)
    expect(page).to have_text(/has already been taken|Could not generate/i)
    expect(user.personal_access_tokens.count).to eq(1)
  end
end
