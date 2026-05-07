# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP tool families", type: :request do
  it "cash.* family — cash.create_transaction goes through Cash::TransactionCreator" do
    user = create(:user)
    raw, _ = issue_pat(user)
    tx = build_stubbed(:manual_transaction, user: user, amount_cents: 1500, currency: "PLN", direction: "debit", booking_date: Date.current, title: "From spec")
    success = Cash::TransactionCreator::Result.new(success?: true, transaction: tx)
    allow(Cash::TransactionCreator).to receive(:call).and_return(success)

    body = mcp_tool_call(name: "cash.create_transaction", token: raw, arguments: {
      amount: "15.00", currency: "PLN", direction: "debit", booking_date: Date.current.to_s
    })

    expect(Cash::TransactionCreator).to have_received(:call) do |kwargs|
      expect(kwargs[:user]).to eq(user)
      expect(kwargs[:input]).to be_a(Cash::TransactionCreator::Input)
    end
    payload = JSON.parse(body.dig("result", "content").first["text"])
    expect(payload).to include("id" => tx.id, "currency" => "PLN", "direction" => "debit")
  end

  it "transactions.* family — transactions.list returns LedgerEntry rows scoped to the user" do
    user = create(:user)
    other = create(:user)
    own_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    foreign_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: other))
    own_tx = create(:bank_transaction, bank_account: own_account, title: "OWN-MCP-LIST")
    create(:bank_transaction, bank_account: foreign_account, title: "FOREIGN-MCP-LIST")
    raw, _ = issue_pat(user)

    body = mcp_tool_call(name: "transactions.list", token: raw, arguments: {})

    payload = JSON.parse(body.dig("result", "content").first["text"])
    titles = payload["transactions"].map { |t| t["title"] }
    expect(titles).to include(own_tx.title)
    expect(titles).not_to include("FOREIGN-MCP-LIST")
    expect(payload["count"]).to eq(payload["transactions"].size)
  end

  it "categories.* family — categories.create goes through Categories::Creator" do
    user = create(:user)
    raw, _ = issue_pat(user)
    saved = create(:category, user: user, name: "Snacks", slug: "snacks", path: "snacks")
    success = Categories::Creator::Result.new(success?: true, category: saved)
    allow(Categories::Creator).to receive(:call).and_return(success)

    body = mcp_tool_call(name: "categories.create", token: raw, arguments: {
      name: "Snacks", kind: "expense"
    })

    expect(Categories::Creator).to have_received(:call) do |kwargs|
      expect(kwargs[:user]).to eq(user)
      expect(kwargs[:attributes][:name]).to eq("Snacks")
    end
    payload = JSON.parse(body.dig("result", "content").first["text"])
    expect(payload).to include("id" => saved.id, "name" => "Snacks", "kind" => "expense")
  end

  it "merchants.* family — merchants.approve goes through Merchants::Approver" do
    user = create(:user)
    merch = create(:merchant, :llm, user: user)
    raw, _ = issue_pat(user)
    allow(Merchants::Approver).to receive(:call).and_return(
      Merchants::Approver::Result.new(success?: true, merchant: merch)
    )

    body = mcp_tool_call(name: "merchants.approve", token: raw, arguments: { id: merch.id })

    expect(Merchants::Approver).to have_received(:call).with(merchant: merch, actor: user)
    text = body.dig("result", "content").first["text"]
    expect(text).to match(/Approved/)
  end

  it "merchants.* family — merchants.approve on an unknown id returns the tool-error envelope" do
    user = create(:user)
    raw, _ = issue_pat(user)

    body = mcp_tool_call(name: "merchants.approve", token: raw, arguments: { id: 999_999 })

    expect(body.dig("result", "isError")).to be(true)
  end

  it "bank_accounts.* family — bank_accounts.refresh_balances goes through RefreshAccountBalances" do
    user = create(:user)
    account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    raw, _ = issue_pat(user)
    allow(EnableBanking::Operations::RefreshAccountBalances).to receive(:call)

    body = mcp_tool_call(name: "bank_accounts.refresh_balances", token: raw, arguments: { id: account.id })

    expect(EnableBanking::Operations::RefreshAccountBalances).to have_received(:call).with(account)
    text = body.dig("result", "content").first["text"]
    expect(text).to match(/Balances refreshed/)
  end

  it "bank_connections.* family — bank_connections.refresh goes through RefreshConnection" do
    user = create(:user)
    connection = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user))
    raw, _ = issue_pat(user)
    allow(EnableBanking::Operations::RefreshConnection).to receive(:call)

    body = mcp_tool_call(name: "bank_connections.refresh", token: raw, arguments: { id: connection.id })

    expect(EnableBanking::Operations::RefreshConnection).to have_received(:call).with(connection)
    text = body.dig("result", "content").first["text"]
    expect(text).to match(/Refreshed/)
  end

  it "analytics.* family — analytics.cash_flow returns totals + period for a brand-new user" do
    user = create(:user)
    raw, _ = issue_pat(user)

    body = mcp_tool_call(name: "analytics.cash_flow", token: raw, arguments: {})

    payload = JSON.parse(body.dig("result", "content").first["text"])
    expect(payload).to include("currency", "period", "totals", "series")
    expect(payload["totals"]).to include("spend_cents", "income_cents", "net_cents")
  end

  it "operations.* family — transaction_syncs.create goes through TransactionSyncs::Queuer" do
    user = create(:user)
    raw, _ = issue_pat(user)
    run = create(:operation_run, kind: "transaction_sync", triggered_by_user: user, subject: user)
    success = TransactionSyncs::Queuer::Result.new(success?: true, run: run)
    allow(TransactionSyncs::Queuer).to receive(:call).and_return(success)

    body = mcp_tool_call(name: "transaction_syncs.create", token: raw, arguments: {})

    expect(TransactionSyncs::Queuer).to have_received(:call) do |kwargs|
      expect(kwargs[:user]).to eq(user)
      expect(kwargs[:input]).to be_a(TransactionSyncs::Queuer::Input)
    end
    payload = JSON.parse(body.dig("result", "content").first["text"])
    expect(payload).to include("run_id" => run.id, "status" => run.status)
  end
end
