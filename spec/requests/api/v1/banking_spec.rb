# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v1 banking resources", type: :request do
  it "GET /api/v1/bank_accounts lists synced accounts and cash wallets owned by the user" do
    user = create(:user)
    other = create(:user)
    own_synced = create(:bank_account, tpp_credential: create(:tpp_credential, user: user), name: "OWN-SYNCED")
    own_cash = create(:bank_account, :cash, manual_owner: user)
    create(:bank_account, tpp_credential: create(:tpp_credential, user: other), name: "FOREIGN-SYNCED")
    raw, _ = issue_pat(user)

    api_get("/api/v1/bank_accounts", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    ids = body["data"].map { |row| row["id"] }
    expect(ids).to include(own_synced.id, own_cash.id)
    expect(body["data"].map { |row| row["name"] }).not_to include("FOREIGN-SYNCED")
  end

  it "GET /api/v1/bank_accounts?manual=true returns only cash wallets" do
    user = create(:user)
    create(:bank_account, tpp_credential: create(:tpp_credential, user: user), name: "synced-account")
    cash = create(:bank_account, :cash, manual_owner: user)
    raw, _ = issue_pat(user)

    api_get("/api/v1/bank_accounts", token: raw, params: { manual: "true" })

    body = JSON.parse(response.body)
    ids = body["data"].map { |row| row["id"] }
    expect(ids).to eq([ cash.id ])
  end

  it "GET /api/v1/bank_accounts/:id fetches a single account scoped to the user" do
    user = create(:user)
    account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    raw, _ = issue_pat(user)

    api_get("/api/v1/bank_accounts/#{account.id}", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["id"]).to eq(account.id)
  end

  it "GET /api/v1/bank_accounts/:id returns 404 for another user's account" do
    user = create(:user)
    other = create(:user)
    foreign = create(:bank_account, tpp_credential: create(:tpp_credential, user: other))
    raw, _ = issue_pat(user)

    api_get("/api/v1/bank_accounts/#{foreign.id}", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "POST /api/v1/bank_accounts/:id/refresh_balances delegates to RefreshAccountBalances and surfaces failure as 422" do
    user = create(:user)
    account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    allow(EnableBanking::Operations::RefreshAccountBalances).to receive(:call)
      .and_raise(EnableBanking::Operations::RefreshAccountBalances::Failed.new("network down"))
    raw, _ = issue_pat(user)

    api_post("/api/v1/bank_accounts/#{account.id}/refresh_balances", token: raw)

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["message"]).to match(/network down/)
  end

  it "POST /api/v1/bank_accounts/:id/refresh_details delegates to RefreshAccountDetails on the happy path" do
    user = create(:user)
    account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    allow(EnableBanking::Operations::RefreshAccountDetails).to receive(:call)
    raw, _ = issue_pat(user)

    api_post("/api/v1/bank_accounts/#{account.id}/refresh_details", token: raw)

    expect(EnableBanking::Operations::RefreshAccountDetails).to have_received(:call).with(account)
    expect(response).to have_http_status(:ok).or have_http_status(:created)
  end

  it "GET /api/v1/bank_connections lists only the current user's connections" do
    user = create(:user)
    other = create(:user)
    own = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user), bank_name: "OwnBank")
    create(:bank_connection, tpp_credential: create(:tpp_credential, user: other), bank_name: "TheirBank")
    raw, _ = issue_pat(user)

    api_get("/api/v1/bank_connections", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["data"].map { |r| r["id"] }).to eq([ own.id ])
  end

  it "GET /api/v1/bank_connections/:id returns 404 for another user's connection" do
    user = create(:user)
    other = create(:user)
    foreign = create(:bank_connection, tpp_credential: create(:tpp_credential, user: other))
    raw, _ = issue_pat(user)

    api_get("/api/v1/bank_connections/#{foreign.id}", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "PATCH /api/v1/bank_connections/:id updates editable fields" do
    user = create(:user)
    connection = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user))
    raw, _ = issue_pat(user)
    new_until = 60.days.from_now

    api_patch("/api/v1/bank_connections/#{connection.id}", token: raw, params: { valid_until: new_until.iso8601 })

    expect(response).to have_http_status(:ok)
    expect(connection.reload.valid_until.to_i).to be_within(1).of(new_until.to_i)
  end

  it "POST /api/v1/bank_connections/:id/refresh delegates to RefreshConnection" do
    user = create(:user)
    connection = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user))
    allow(EnableBanking::Operations::RefreshConnection).to receive(:call)
    raw, _ = issue_pat(user)

    api_post("/api/v1/bank_connections/#{connection.id}/refresh", token: raw)

    expect(EnableBanking::Operations::RefreshConnection).to have_received(:call).with(connection)
  end

  it "DELETE /api/v1/bank_connections/:id closes the connection via CloseConnection" do
    user = create(:user)
    connection = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user))
    allow(EnableBanking::Operations::CloseConnection).to receive(:call)
    raw, _ = issue_pat(user)

    api_delete("/api/v1/bank_connections/#{connection.id}", token: raw)

    expect(EnableBanking::Operations::CloseConnection).to have_received(:call).with(connection)
  end

  it "GET /api/v1/tpp_credentials lists the user's credentials" do
    user = create(:user)
    other = create(:user)
    own = create(:tpp_credential, user: user, name: "OWN-TPP")
    create(:tpp_credential, user: other, name: "FOREIGN-TPP")
    raw, _ = issue_pat(user)

    api_get("/api/v1/tpp_credentials", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    names = body["data"].map { |row| row["name"] }
    expect(names).to include(own.name)
    expect(names).not_to include("FOREIGN-TPP")
  end

  it "POST /api/v1/tpp_credentials creates a credential and 201s" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_post("/api/v1/tpp_credentials", token: raw, params: {
      name: "API TPP", provider: "enable_banking", environment: "SANDBOX",
      redirect_url: "http://localhost:3000/callback",
      application_id: "api-app-1",
      private_key_pem: OpenSSL::PKey::RSA.new(2048).to_pem
    })

    expect(response).to have_http_status(:created)
    expect(user.tpp_credentials.find_by(name: "API TPP")).to be_present
  end

  it "DELETE /api/v1/tpp_credentials/:id refuses when bank connections still reference it" do
    user = create(:user)
    credential = create(:tpp_credential, user: user)
    create(:bank_connection, tpp_credential: credential)
    raw, _ = issue_pat(user)

    expect {
      api_delete("/api/v1/tpp_credentials/#{credential.id}", token: raw)
    }.not_to change(TppCredential, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "POST /api/v1/tpp_credentials/:id/test_connection delegates to VerifyCredential and 422s on failure" do
    user = create(:user)
    credential = create(:tpp_credential, user: user)
    raw, _ = issue_pat(user)
    failed = EnableBanking::Operations::VerifyCredential::VerifyResult.new(status: :failed, message: "Bad cert")
    allow(EnableBanking::Operations::VerifyCredential).to receive(:call).with(credential).and_return(failed)

    api_post("/api/v1/tpp_credentials/#{credential.id}/test_connection", token: raw)

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["message"]).to eq("Bad cert")
  end

  it "POST /api/v1/tpp_credentials/:id/make_primary calls make_primary! on the model" do
    user = create(:user)
    a = create(:tpp_credential, user: user, primary: true)
    b = create(:tpp_credential, user: user, primary: false)
    raw, _ = issue_pat(user)

    api_post("/api/v1/tpp_credentials/#{b.id}/make_primary", token: raw)

    expect(response).to have_http_status(:created).or have_http_status(:ok)
    expect(b.reload.primary?).to be(true)
    expect(a.reload.primary?).to be(false)
  end

  it "GET /api/v1/transaction_syncs lists only runs triggered by the current user" do
    user = create(:user)
    other = create(:user)
    own_run = create(:operation_run, kind: "transaction_sync", triggered_by_user: user, subject: user)
    foreign_run = create(:operation_run, kind: "transaction_sync", triggered_by_user: other, subject: other)
    raw, _ = issue_pat(user)

    api_get("/api/v1/transaction_syncs", token: raw)

    body = JSON.parse(response.body)
    ids = body["data"].map { |row| row["id"] }
    expect(ids).to include(own_run.id)
    expect(ids).not_to include(foreign_run.id)
  end

  it "POST /api/v1/transaction_syncs delegates to TransactionSyncs::Queuer and 201s" do
    user = create(:user)
    run = create(:operation_run, kind: "transaction_sync", triggered_by_user: user, subject: user)
    success = TransactionSyncs::Queuer::Result.new(success?: true, run: run)
    allow(TransactionSyncs::Queuer).to receive(:call).and_return(success)
    raw, _ = issue_pat(user)

    api_post("/api/v1/transaction_syncs", token: raw, params: {})

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["id"]).to eq(run.id)
  end

  it "GET /api/v1/transaction_syncs/:id returns 404 for another user's run" do
    user = create(:user)
    other = create(:user)
    foreign = create(:operation_run, kind: "transaction_sync", triggered_by_user: other, subject: other)
    raw, _ = issue_pat(user)

    api_get("/api/v1/transaction_syncs/#{foreign.id}", token: raw)

    expect(response).to have_http_status(:not_found)
  end
end
