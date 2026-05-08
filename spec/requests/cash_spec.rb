# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cash area", type: :request do
  it "GET /admin/cash_transactions returns 200 with only the current user's manual transactions" do
    user = create(:user)
    other = create(:user)
    own = create(:manual_transaction, user: user, title: "OWN MANUAL TX")
    foreign = create(:manual_transaction, user: other, title: "FOREIGN TX 4242")
    sign_in user

    get admin_cash_transactions_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own.title)
    expect(response.body).not_to include(foreign.title)
  end

  it "GET /admin/cash_transactions filters by wallet_id" do
    user = create(:user)
    wallet_a = create(:bank_account, :cash, manual_owner: user, currency: "PLN")
    wallet_b = create(:bank_account, :cash, manual_owner: user, currency: "EUR")
    in_wallet = create(:manual_transaction, user: user, bank_account: wallet_a, currency: "PLN", title: "WALLET-A TX")
    out_of_wallet = create(:manual_transaction, user: user, bank_account: wallet_b, currency: "EUR", title: "WALLET-B TX")
    sign_in user

    get admin_cash_transactions_path, params: { wallet_id: wallet_a.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(in_wallet.title)
    expect(response.body).not_to include(out_of_wallet.title)
  end

  it "GET /admin/cash_transactions filters by direction" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user)
    debit = create(:manual_transaction, user: user, bank_account: wallet, direction: "debit", title: "DEBIT-ONE")
    credit = create(:manual_transaction, user: user, bank_account: wallet, direction: "credit", title: "CREDIT-ONE")
    sign_in user

    get admin_cash_transactions_path, params: { direction: "debit" }

    expect(response.body).to include(debit.title)
    expect(response.body).not_to include(credit.title)
  end

  it "GET /admin/cash_transactions filters by from/to date range" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user)
    in_range = create(:manual_transaction, user: user, bank_account: wallet, booking_date: Date.new(2026, 1, 15), title: "IN-RANGE-TX")
    out_of_range = create(:manual_transaction, user: user, bank_account: wallet, booking_date: Date.new(2025, 1, 15), title: "OUT-OF-RANGE-TX")
    sign_in user

    get admin_cash_transactions_path, params: { from: "2026-01-01", to: "2026-12-31" }

    expect(response.body).to include(in_range.title)
    expect(response.body).not_to include(out_of_range.title)
  end

  it "GET /admin/cash_transactions/new returns 200 with the default debit, current-date defaults" do
    user = create(:user)
    sign_in user

    get new_admin_cash_transaction_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="cash_transaction[amount]"')
  end

  it "GET /admin/cash_transactions/new with ?direction=credit pre-fills the credit direction" do
    user = create(:user)
    sign_in user

    get new_admin_cash_transaction_path, params: { direction: "credit" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('value="credit"')
  end

  it "GET /admin/cash_transactions/:id redirects to the edit page" do
    user = create(:user)
    tx = create(:manual_transaction, user: user)
    sign_in user

    get admin_cash_transaction_path(tx)

    expect(response).to redirect_to(edit_admin_cash_transaction_path(tx))
  end

  it_behaves_like "a cross-user isolated resource",
                  verb: :get,
                  path_for: ->(record) { Rails.application.routes.url_helpers.admin_cash_transaction_path(record) },
                  build_record: ->(user) { create(:manual_transaction, user: user) }

  it "POST /admin/cash_transactions delegates to TransactionCreator and redirects on success with an expense notice" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user)
    saved = build_stubbed(:manual_transaction, user: user, bank_account: wallet, direction: "debit", amount_cents: 25_00, currency: "PLN")
    success = Cash::TransactionCreator::Result.new(success?: true, transaction: saved)
    allow(Cash::TransactionCreator).to receive(:call).and_return(success)
    sign_in user

    post admin_cash_transactions_path, params: {
      cash_transaction: {
        amount: "25.00", currency: "PLN", direction: "debit",
        booking_date: Date.current.to_s, payment_method: "cash"
      }
    }

    expect(Cash::TransactionCreator).to have_received(:call) do |kwargs|
      expect(kwargs[:user]).to eq(user)
      expect(kwargs[:input]).to be_a(Cash::TransactionCreator::Input)
    end
    expect(response).to redirect_to(admin_cash_transactions_path)
    expect(flash[:notice]).to match(/expense/i)
  end

  it "POST /admin/cash_transactions surfaces a credit/income notice on success" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user)
    saved = build_stubbed(:manual_transaction, user: user, bank_account: wallet, direction: "credit", amount_cents: 100_00)
    allow(Cash::TransactionCreator).to receive(:call).and_return(
      Cash::TransactionCreator::Result.new(success?: true, transaction: saved)
    )
    sign_in user

    post admin_cash_transactions_path, params: {
      cash_transaction: { amount: "100", currency: "PLN", direction: "credit", booking_date: Date.current.to_s }
    }

    expect(flash[:notice]).to match(/income/i)
  end

  it "POST /admin/cash_transactions re-renders :new with 422 when the creator fails, exposing the half-built record" do
    user = create(:user)
    invalid = ManualTransaction.new(currency: "PLN", direction: "debit")
    failure = Cash::TransactionCreator::Result.new(success?: false, transaction: invalid, error_messages: [ "boom" ])
    allow(Cash::TransactionCreator).to receive(:call).and_return(failure)
    sign_in user

    post admin_cash_transactions_path, params: {
      cash_transaction: { amount: "", currency: "PLN", direction: "debit", booking_date: Date.current.to_s }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("boom")
  end

  it "POST /admin/cash_transactions falls back to a new ManualTransaction when the creator returns no record" do
    user = create(:user)
    failure = Cash::TransactionCreator::Result.new(success?: false, transaction: nil, error_messages: [ "boom" ])
    allow(Cash::TransactionCreator).to receive(:call).and_return(failure)
    sign_in user

    post admin_cash_transactions_path, params: {
      cash_transaction: { amount: "", currency: "PLN", direction: "debit", booking_date: Date.current.to_s }
    }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "GET /admin/cash_transactions/:id/edit returns 200 for an editable manual row" do
    user = create(:user)
    tx = create(:manual_transaction, user: user)
    sign_in user

    get edit_admin_cash_transaction_path(tx)

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/cash_transactions/:id/edit redirects with an alert when the row is an ATM-link (non-manual)" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user)
    bank_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    bank_tx = create(:bank_transaction, :atm_withdrawal, bank_account: bank_account)
    tx = create(:manual_transaction, user: user, bank_account: wallet,
                                     source: "atm_link", linked_bank_transaction_id: bank_tx.id)
    sign_in user

    get edit_admin_cash_transaction_path(tx)

    expect(response).to redirect_to(admin_cash_transactions_path)
    expect(flash[:alert]).to match(/auto-generated|isn't editable/i)
  end

  it "PATCH /admin/cash_transactions/:id delegates to TransactionUpdater dropping :currency from the Input" do
    user = create(:user)
    tx = create(:manual_transaction, user: user, currency: "PLN", amount_cents: 50_00)
    success = Cash::TransactionUpdater::Result.new(success?: true, transaction: tx)
    allow(Cash::TransactionUpdater).to receive(:call).and_return(success)
    sign_in user

    patch admin_cash_transaction_path(tx), params: {
      cash_transaction: {
        amount: "75.00", currency: "USD", direction: "debit",
        booking_date: Date.current.to_s, payment_method: "cash"
      }
    }

    expect(Cash::TransactionUpdater).to have_received(:call) do |kwargs|
      expect(kwargs[:transaction]).to eq(tx)
      expect(kwargs[:input]).to be_a(Cash::TransactionUpdater::Input)
      expect(kwargs[:input].members).not_to include(:currency)
    end
    expect(response).to redirect_to(admin_cash_transactions_path)
  end

  it "PATCH /admin/cash_transactions/:id re-renders :edit with 422 when the updater fails" do
    user = create(:user)
    tx = create(:manual_transaction, user: user)
    failure = Cash::TransactionUpdater::Result.new(success?: false, transaction: tx, error_messages: [ "no good" ])
    allow(Cash::TransactionUpdater).to receive(:call).and_return(failure)
    sign_in user

    patch admin_cash_transaction_path(tx), params: {
      cash_transaction: { amount: "5.00", direction: "debit", booking_date: Date.current.to_s }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("no good")
  end

  it "PATCH /admin/cash_transactions/:id on a non-manual ATM-link row redirects with an alert without invoking the updater" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user)
    bank_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    bank_tx = create(:bank_transaction, :atm_withdrawal, bank_account: bank_account)
    tx = create(:manual_transaction, user: user, bank_account: wallet,
                                     source: "atm_link", linked_bank_transaction_id: bank_tx.id)
    allow(Cash::TransactionUpdater).to receive(:call)
    sign_in user

    patch admin_cash_transaction_path(tx), params: {
      cash_transaction: { amount: "1.00", direction: "debit", booking_date: Date.current.to_s }
    }

    expect(Cash::TransactionUpdater).not_to have_received(:call)
    expect(response).to redirect_to(admin_cash_transactions_path)
  end

  it "DELETE /admin/cash_transactions/:id deletes a manual transaction and redirects with notice" do
    user = create(:user)
    tx = create(:manual_transaction, user: user)
    sign_in user

    expect {
      delete admin_cash_transaction_path(tx)
    }.to change(ManualTransaction, :count).by(-1)
    expect(response).to redirect_to(admin_cash_transactions_path)
    expect(flash[:notice]).to match(/deleted/i)
  end

  it "DELETE /admin/cash_transactions/:id on a non-manual row redirects with alert and keeps the row" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user)
    bank_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    bank_tx = create(:bank_transaction, :atm_withdrawal, bank_account: bank_account)
    tx = create(:manual_transaction, user: user, bank_account: wallet,
                                     source: "atm_link", linked_bank_transaction_id: bank_tx.id)
    sign_in user

    expect {
      delete admin_cash_transaction_path(tx)
    }.not_to change(ManualTransaction, :count)
    expect(response).to redirect_to(admin_cash_transactions_path)
  end

  it "GET /admin/cash_transactions without sign-in redirects to /admin/sign_in" do
    create(:user)
    get admin_cash_transactions_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
