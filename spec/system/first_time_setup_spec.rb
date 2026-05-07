# frozen_string_literal: true

require "rails_helper"

RSpec.describe "First-time user setup journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "drives the empty-DB setup form, lands signed in on the analytics dashboard, and provisions seeded categories + merchant rules" do
    expect(User.count).to eq(0)

    visit "/"
    expect(page).to have_current_path("/setup", ignore_query: true)
    expect(page).to have_text("Create your admin account")

    fill_in "user[name]",                  with: "Setup Owner"
    fill_in "user[email]",                 with: "owner@example.test"
    fill_in "user[password]",              with: "Password123!"
    fill_in "user[password_confirmation]", with: "Password123!"
    click_button "Create account & sign in"

    expect(page).to have_current_path("/admin/analytics", ignore_query: true)
    expect(page).to have_text("Analytics")

    user = User.find_by(email: "owner@example.test")
    expect(user).to be_present
    expect(user.categories.count).to be > 0
    expect(user.merchant_rules.count).to be > 0
    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
  end

  it "rejects setup with mismatched password confirmation by re-rendering :new without creating a user" do
    expect(User.count).to eq(0)

    visit "/setup"
    fill_in "user[name]",                  with: "Mismatch"
    fill_in "user[email]",                 with: "mismatch@example.test"
    fill_in "user[password]",              with: "Password123!"
    fill_in "user[password_confirmation]", with: "WrongPass456!"
    click_button "Create account & sign in"

    expect(User.count).to eq(0)
    expect(page).to have_current_path("/setup", ignore_query: true)
    expect(page).to have_text(/confirmation/i)
  end

  it "links a primary TPP credential, completes the OAuth callback round-trip, and finishes a manual sync end-to-end" do
    user = User.create!(email: "owner@example.test", password: "Password123!", name: "Setup Owner")
    Seeders::Categories.call(user)
    Seeders::MerchantRules.call(user)

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    visit "/admin/tpp_credentials/new"
    fill_in "tpp_credential[name]",            with: "PKO Showcase"
    fill_in "tpp_credential[redirect_url]",    with: "http://localhost:3000/admin/oauth/enable_banking/callback"
    fill_in "tpp_credential[application_id]",  with: "fake-app-uuid-1234"
    fill_in "tpp_credential[private_key_pem]", with: "test-private-key"
    click_button "Create credential"

    credential = user.tpp_credentials.first
    expect(credential).to be_present
    expect(credential).to be_primary
    expect(page).to have_current_path(%r{/admin/tpp_credentials/#{credential.id}\z})

    fake_eb.add_aspsp(name: "PKO BP", country: "PL")
    session_id = fake_eb.add_session(aspsp_name: "PKO BP", country: "PL", valid_until: 30.days.from_now)
    account_uid = fake_eb.add_account(
      session_id:    session_id,
      currency:      "PLN",
      balance_cents: 10_000_00,
      holder_name:   "Setup Owner",
      iban:          "PL61109010140000071219812874"
    )
    fake_eb.add_transaction(
      account_uid:  account_uid,
      amount_cents: -42_99,
      direction:    "debit",
      booking_date: Date.current,
      title:        "BIEDRONKA WARSZAWA",
      payment_method_hint: "card"
    )

    visit "/admin/bank_connections/new"
    expect(page).to have_select("bank_connection_request_form[aspsp_name]", with_options: [ "PKO BP" ])

    state_token = EnableBanking::State.encode(
      user_id:           user.id,
      tpp_credential_id: credential.id,
      aspsp_name:        "PKO BP",
      aspsp_country:     "PL",
      psu_type:          "personal"
    )

    visit oauth_callback_path(code: session_id, state: state_token)
    connection = user.bank_connections.first
    expect(connection).to be_present
    expect(connection.bank_name).to eq("PKO BP")
    expect(page).to have_current_path(admin_bank_connection_path(connection))
    expect(page).to have_text("PKO BP")

    Sidekiq::Testing.inline! do
      visit "/admin/transaction_syncs/new"
      select "PKO BP (PL)", from: "bank_connection_id"
      click_button "Start sync"
    end

    run = OperationRun.where(triggered_by_user_id: user.id, kind: "transaction_sync").order(:id).last
    expect(run.status).to eq("succeeded")
    expect(run.summary["accounts"]).to be_present

    expect(BankTransaction.for_user(user).count).to eq(1)
    expect(BankTransaction.for_user(user).first.title).to include("BIEDRONKA")

    visit "/admin/bank_transactions"
    expect(page).to have_text("BIEDRONKA")

    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
    assert_no_orphaned_enrichments!(user)
  ensure
    Sidekiq::Testing.fake!
  end
end
