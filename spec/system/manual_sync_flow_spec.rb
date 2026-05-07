# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manual sync flow journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "queues a sync from the new sync form, runs it inline through TransactionSyncJob, and lands on a succeeded run page with the new bank transaction listed" do
    user, _credential, connection, account = build_synced_user_with_history
    fake_eb.add_aspsp(name: "PKO BP", country: "PL")
    fake_eb.add_session(aspsp_name: "PKO BP", country: "PL", id: connection.session_id)
    fake_eb.add_account(
      session_id:    connection.session_id,
      uid:           account.uid,
      currency:      "PLN",
      balance_cents: 25_000_00,
      holder_name:   "Sync User",
      iban:          account.iban
    )
    fake_eb.add_transaction(
      account_uid:         account.uid,
      amount_cents:        -19_99,
      direction:           "debit",
      booking_date:        Date.current,
      title:               "BIEDRONKA WARSZAWA",
      payment_method_hint: "card"
    )

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    Sidekiq::Testing.inline! do
      visit "/admin/transaction_syncs/new"
      select "PKO BP (PL)", from: "bank_connection_id"
      click_button "Start sync"
    end

    run = OperationRun.where(triggered_by_user_id: user.id, kind: "transaction_sync").order(:id).last
    expect(page).to have_current_path(admin_transaction_sync_path(run), ignore_query: true)
    expect(run.status).to eq("succeeded")
    expect(run.trigger).to eq("manual")
    accounts = Array(run.summary["accounts"])
    expect(accounts.size).to eq(1)
    expect(accounts.first["status"]).to eq("succeeded")
    expect(accounts.first["inserted"]).to eq(1)

    expect(BankTransaction.for_user(user).count).to eq(1)
    new_tx = BankTransaction.for_user(user).first
    expect(new_tx.title).to include("BIEDRONKA")

    visit "/admin/bank_transactions"
    expect(page).to have_text("BIEDRONKA")

    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
    assert_no_orphaned_enrichments!(user)
  ensure
    Sidekiq::Testing.fake!
  end

  it "marks the run as failed when the only account in scope errors out and surfaces the failure in the per-account breakdown" do
    user, _credential, connection, account = build_synced_user_with_history
    fake_eb.add_aspsp(name: "PKO BP", country: "PL")
    fake_eb.add_session(aspsp_name: "PKO BP", country: "PL", id: connection.session_id)
    fake_eb.add_account(
      session_id:    connection.session_id,
      uid:           account.uid,
      currency:      "PLN",
      balance_cents: 25_000_00,
      holder_name:   "Sync User",
      iban:          account.iban
    )
    fake_eb.simulate_failure(
      method: :get,
      path:   %r{\A/accounts/#{Regexp.escape(account.uid)}/transactions\z},
      status: 500,
      error:  "Bank under maintenance"
    )

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    Sidekiq::Testing.inline! do
      visit "/admin/transaction_syncs/new"
      select "PKO BP (PL)", from: "bank_connection_id"
      click_button "Start sync"
    end

    run = OperationRun.where(triggered_by_user_id: user.id, kind: "transaction_sync").order(:id).last
    expect(run.status).to eq("failed")
    expect(run.error).to include("All 1 account(s) failed")
    accounts = Array(run.summary["accounts"])
    expect(accounts.first["status"]).to eq("failed")
    expect(accounts.first["error"]).to include("Bank under maintenance")
    expect(BankTransaction.for_user(user).count).to eq(0)

    assert_no_running_operation_runs!
  ensure
    Sidekiq::Testing.fake!
  end

  it "shows the previous succeeded run on the index alongside the newly queued one" do
    user, _credential, connection, _account = build_synced_user_with_history(prior_runs: 1)

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    visit "/admin/transaction_syncs"
    expect(page.status_code).to eq(200)
    expect(page).to have_text(connection.bank_name)
  end

  def build_synced_user_with_history(prior_runs: 0)
    user = User.create!(
      email:    "sync-#{SecureRandom.hex(4)}@example.test",
      password: "Password123!",
      name:     "Sync User"
    )
    Seeders::Categories.call(user)
    Seeders::MerchantRules.call(user)

    credential = user.tpp_credentials.create!(
      name:            "Primary",
      provider:        "enable_banking",
      environment:     "SANDBOX",
      status:          "active",
      primary:         true,
      application_id:  "fake-app",
      redirect_url:    "http://localhost:3000/admin/oauth/enable_banking/callback",
      private_key_pem: "fake-pem"
    )
    connection = credential.bank_connections.create!(
      bank_slug: "pko_bp", bank_country: "PL", bank_name: "PKO BP",
      status: "authorized", psu_type: "personal",
      session_id: "sess-#{SecureRandom.hex(4)}",
      valid_until: 30.days.from_now, authorized_at: Time.current,
      access_balances: true, access_transactions: true
    )
    account = BankAccount.create!(
      uid:                     "acc-#{SecureRandom.hex(4)}",
      iban:                    "PL61109010140000071219#{format('%06d', user.id)}",
      currency:                "PLN",
      name:                    "Konto Osobiste",
      product:                 "Personal",
      cash_account_type:       "CACC",
      status:                  "active",
      tpp_credential:          credential,
      current_bank_connection: connection,
      all_account_ids:         []
    )
    prior_runs.times do
      OperationRun.create!(
        kind:              "transaction_sync",
        status:            "succeeded",
        trigger:           "manual",
        triggered_by_user: user,
        subject:           connection,
        params:            {},
        summary:           { "accounts" => [] },
        started_at:        1.day.ago,
        finished_at:       1.day.ago + 5.seconds
      )
    end
    [ user, credential, connection, account ]
  end
end
