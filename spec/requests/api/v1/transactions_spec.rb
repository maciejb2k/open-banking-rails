# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v1 transactions resources", type: :request do
  it "GET /api/v1/transactions returns the user's ledger entries with the LedgerEntry entity shape" do
    user = create(:user)
    other = create(:user)
    own_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    foreign_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: other))
    own_tx = create(:bank_transaction, bank_account: own_account, title: "OWN-TX-API")
    create(:bank_transaction, bank_account: foreign_account, title: "FOREIGN-TX-API")
    raw, _ = issue_pat(user)

    api_get("/api/v1/transactions", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include("data", "pagination")
    titles = body["data"].map { |row| row["title"] }
    expect(titles).to include("OWN-TX-API")
    expect(titles).not_to include("FOREIGN-TX-API")
    row = body["data"].find { |r| r["source_id"] == own_tx.id }
    expect(row).to include("source_type", "source_id", "amount", "direction", "booking_date")
    expect(row["amount"]).to include("cents", "currency")
  end

  it "GET /api/v1/transactions filters by from/to date range" do
    user = create(:user)
    account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    in_range = create(:bank_transaction, bank_account: account, booking_date: Date.new(2026, 1, 15), title: "IN-API")
    out_of_range = create(:bank_transaction, bank_account: account, booking_date: Date.new(2025, 1, 15), title: "OUT-API")
    raw, _ = issue_pat(user)

    api_get("/api/v1/transactions", token: raw, params: { from: "2026-01-01", to: "2026-12-31" })

    body = JSON.parse(response.body)
    titles = body["data"].map { |row| row["title"] }
    expect(titles).to include(in_range.title)
    expect(titles).not_to include(out_of_range.title)
  end

  it "GET /api/v1/transactions/BankTransaction/:id fetches a single ledger entry" do
    user = create(:user)
    account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    tx = create(:bank_transaction, bank_account: account)
    raw, _ = issue_pat(user)

    api_get("/api/v1/transactions/BankTransaction/#{tx.id}", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["source_id"]).to eq(tx.id)
    expect(body["source_type"]).to eq("BankTransaction")
  end

  it "GET /api/v1/transactions/BankTransaction/:id returns 404 for another user's transaction" do
    user = create(:user)
    other = create(:user)
    foreign_tx = create(:bank_transaction, bank_account: create(:bank_account, tpp_credential: create(:tpp_credential, user: other)))
    raw, _ = issue_pat(user)

    api_get("/api/v1/transactions/BankTransaction/#{foreign_tx.id}", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /api/v1/cash_transactions returns the user's manual transactions only" do
    user = create(:user)
    other = create(:user)
    own_tx = create(:manual_transaction, user: user, title: "OWN-MANUAL-API")
    create(:manual_transaction, user: other, title: "FOREIGN-MANUAL-API")
    raw, _ = issue_pat(user)

    api_get("/api/v1/cash_transactions", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    titles = body["data"].map { |row| row["title"] }
    expect(titles).to include(own_tx.title)
    expect(titles).not_to include("FOREIGN-MANUAL-API")
  end

  it "POST /api/v1/cash_transactions creates a manual transaction via Cash::TransactionCreator and returns 201" do
    user = create(:user)
    raw, _ = issue_pat(user)

    expect {
      api_post("/api/v1/cash_transactions", token: raw, params: {
        amount: "50.25", currency: "PLN", direction: "debit",
        booking_date: Date.current.to_s, title: "Lunch"
      })
    }.to change(ManualTransaction, :count).by(1)

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body).to include("id", "amount", "direction", "booking_date")
    expect(body["amount"]).to include("cents" => 5025, "currency" => "PLN")
    expect(body["direction"]).to eq("debit")
  end

  it "POST /api/v1/cash_transactions returns 422 with a details array on validation failure" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_post("/api/v1/cash_transactions", token: raw, params: { amount: "" })

    expect(response).to have_http_status(:unprocessable_content)
    body = JSON.parse(response.body)
    expect(body["details"]).to be_an(Array)
    expect(body["details"]).not_to be_empty
  end

  it "GET /api/v1/cash_transactions/:id returns 404 for an unknown id" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_get("/api/v1/cash_transactions/99999", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /api/v1/cash_transactions/:id returns 404 for another user's manual transaction" do
    user = create(:user)
    other = create(:user)
    foreign = create(:manual_transaction, user: other)
    raw, _ = issue_pat(user)

    api_get("/api/v1/cash_transactions/#{foreign.id}", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "PATCH /api/v1/cash_transactions/:id updates an editable manual row via TransactionUpdater" do
    user = create(:user)
    tx = create(:manual_transaction, user: user, title: "Old title", currency: "PLN")
    raw, _ = issue_pat(user)

    api_patch("/api/v1/cash_transactions/#{tx.id}", token: raw, params: { title: "New title" })

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["title"]).to eq("New title")
    expect(tx.reload.title).to eq("New title")
  end

  it "PATCH /api/v1/cash_transactions/:id refuses an ATM-link row with 422" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user)
    bank_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    bank_tx = create(:bank_transaction, :atm_withdrawal, bank_account: bank_account)
    tx = create(:manual_transaction, user: user, bank_account: wallet,
                                     source: "atm_link", linked_bank_transaction_id: bank_tx.id)
    raw, _ = issue_pat(user)

    api_patch("/api/v1/cash_transactions/#{tx.id}", token: raw, params: { title: "blocked" })

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "DELETE /api/v1/cash_transactions/:id returns 204 and destroys an editable manual row" do
    user = create(:user)
    tx = create(:manual_transaction, user: user)
    raw, _ = issue_pat(user)

    expect {
      api_delete("/api/v1/cash_transactions/#{tx.id}", token: raw)
    }.to change(ManualTransaction, :count).by(-1)
    expect(response).to have_http_status(:no_content)
  end

  it "GET /api/v1/bank_transactions returns the user's bank-synced transactions only" do
    user = create(:user)
    other = create(:user)
    own_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    foreign_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: other))
    own_tx = create(:bank_transaction, bank_account: own_account, title: "OWN-BANK-TX")
    create(:bank_transaction, bank_account: foreign_account, title: "FOREIGN-BANK-TX")
    raw, _ = issue_pat(user)

    api_get("/api/v1/bank_transactions", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["data"].map { |r| r["title"] }).to include(own_tx.title)
    expect(body["data"].map { |r| r["title"] }).not_to include("FOREIGN-BANK-TX")
  end

  it "GET /api/v1/bank_transactions/:id returns 404 for another user's transaction" do
    user = create(:user)
    other = create(:user)
    foreign = create(:bank_transaction, bank_account: create(:bank_account, tpp_credential: create(:tpp_credential, user: other)))
    raw, _ = issue_pat(user)

    api_get("/api/v1/bank_transactions/#{foreign.id}", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "POST /api/v1/bank_transactions/:bt_id/classification applies enrichment via ClassificationApplier and returns the entity" do
    user = create(:user)
    bank_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    bank_tx = create(:bank_transaction, bank_account: bank_account)
    raw, _ = issue_pat(user)

    api_post("/api/v1/bank_transactions/#{bank_tx.id}/classification", token: raw, params: { mode: "only_this" })

    expect(response).to have_http_status(:created).or have_http_status(:ok)
    expect(bank_tx.reload.enrichment).to be_present
  end

  it "POST /api/v1/bank_transactions/:bt_id/classification returns 422 with the applier's message on failure" do
    user = create(:user)
    bank_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    bank_tx = create(:bank_transaction, bank_account: bank_account)
    failure = Enrichment::ClassificationApplier::Result.new(success: false, message: "Pick a merchant")
    allow(Enrichment::ClassificationApplier).to receive(:call).and_return(failure)
    raw, _ = issue_pat(user)

    api_post("/api/v1/bank_transactions/#{bank_tx.id}/classification", token: raw, params: { mode: "only_this" })

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["message"]).to eq("Pick a merchant")
  end

  it "POST /api/v1/bank_transactions/:bt_id/classification returns 404 for another user's transaction" do
    user = create(:user)
    other = create(:user)
    foreign_tx = create(:bank_transaction, bank_account: create(:bank_account, tpp_credential: create(:tpp_credential, user: other)))
    raw, _ = issue_pat(user)

    api_post("/api/v1/bank_transactions/#{foreign_tx.id}/classification", token: raw, params: { mode: "only_this" })

    expect(response).to have_http_status(:not_found)
  end
end
