# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::Api::GetAccountTransactions do
  it "follows continuation_key across pages and concatenates transactions in order" do
    credential = create(:tpp_credential)
    fake_eb.add_aspsp(name: "Fake Bank", country: "PL")
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank")
    uid = fake_eb.add_account(session_id: session_id)
    7.times do |i|
      fake_eb.add_transaction(account_uid: uid, amount_cents: (i + 1) * 100, booking_date: Date.current - i, title: "tx#{i}")
    end
    fake_eb.transactions_page_size = 3

    result = described_class.call(credential: credential, uid: uid, date_from: 30.days.ago.to_date, date_to: Date.current)

    expect(result.success?).to be(true)
    expect(result.data["transactions"].length).to eq(7)
    expect(result.data["transactions"].map { |t| t["remittance_information"].first }).to eq(%w[tx0 tx1 tx2 tx3 tx4 tx5 tx6])
    expect(result.data["pages_fetched"]).to eq(3)
    expect(result.data["truncated"]).to be(false)
  end

  it "stops at max_pages and surfaces truncated: true when continuation_key remains" do
    credential = create(:tpp_credential)
    fake_eb.add_aspsp(name: "Fake Bank", country: "PL")
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank")
    uid = fake_eb.add_account(session_id: session_id)
    10.times do |i|
      fake_eb.add_transaction(account_uid: uid, amount_cents: (i + 1) * 100, booking_date: Date.current - i)
    end
    fake_eb.transactions_page_size = 3

    result = described_class.call(credential: credential, uid: uid, date_from: 30.days.ago.to_date, date_to: Date.current, max_pages: 2)

    expect(result.success?).to be(true)
    expect(result.data["pages_fetched"]).to eq(2)
    expect(result.data["truncated"]).to be(true)
    expect(result.data["transactions"].length).to eq(6)
  end

  it "passes the continuation_key back as a request parameter on subsequent calls" do
    credential = create(:tpp_credential)
    fake_eb.add_aspsp(name: "Fake Bank", country: "PL")
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank")
    uid = fake_eb.add_account(session_id: session_id)
    5.times { |i| fake_eb.add_transaction(account_uid: uid, amount_cents: 100, booking_date: Date.current - i) }
    fake_eb.transactions_page_size = 2

    described_class.call(credential: credential, uid: uid, date_from: 30.days.ago.to_date, date_to: Date.current)

    transaction_calls = fake_eb.recorded_calls.select { |c| c[:path].include?("/transactions") }
    expect(transaction_calls.length).to eq(3)
    expect(transaction_calls[0][:params]).not_to have_key(:continuation_key)
    expect(transaction_calls[1][:params][:continuation_key]).to eq("offset:2")
    expect(transaction_calls[2][:params][:continuation_key]).to eq("offset:4")
  end

  it "propagates a failure mid-pagination as a Result(success: false) with no half-merged data" do
    credential = create(:tpp_credential)
    fake_eb.add_aspsp(name: "Fake Bank", country: "PL")
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank")
    uid = fake_eb.add_account(session_id: session_id)
    6.times { fake_eb.add_transaction(account_uid: uid, amount_cents: 100, booking_date: Date.current) }
    fake_eb.transactions_page_size = 2
    fake_eb.simulate_failure(method: :get, path: "/accounts/#{uid}/transactions", count: 1, status: 503, error: "Bank gateway down")

    result = described_class.call(credential: credential, uid: uid, date_from: 30.days.ago.to_date, date_to: Date.current)

    expect(result.success?).to be(false)
    expect(result.status).to eq(503)
    expect(result.error).to match(/Bank gateway down/)
  end
end
