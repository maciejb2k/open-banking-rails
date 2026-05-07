# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cash transaction + ATM link journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "logs a 50 PLN cash expense in the wallet that already holds yesterday's BLIK ATM topup, surfaces the success notice, and updates the manual transactions list" do
    user, _wallet, atm_topup, atm_debit = build_cash_user_with_linked_atm_withdrawal

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    visit "/admin/cash_transactions/new"
    fill_in "cash_transaction[amount]", with: "50"
    fill_in "cash_transaction[title]",  with: "Coffee at the corner shop"
    click_button "Save transaction"

    expect(page).to have_current_path("/admin/cash_transactions", ignore_query: true)
    expect(page).to have_text(/Saved expense/)

    new_row = ManualTransaction.for_user(user).where(source: "manual").order(:id).last
    expect(new_row).to be_present
    expect(new_row.amount_cents).to eq(50_00)
    expect(new_row.currency).to eq("PLN")
    expect(new_row.direction).to eq("debit")
    expect(new_row.title).to eq("Coffee at the corner shop")

    expect(atm_topup.reload.linked_bank_transaction_id).to eq(atm_debit.id)
    expect(ManualTransaction.for_user(user).count).to eq(2)

    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
    assert_no_orphaned_enrichments!(user)
  end

  it "lists existing manual transactions including the linked ATM topup on the cash index" do
    user, _wallet, atm_topup, _atm_debit = build_cash_user_with_linked_atm_withdrawal

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    visit "/admin/cash_transactions"
    expect(page.status_code).to eq(200)
    expect(page).to have_text(atm_topup.title)
  end

  it "renders the cash index for a user without track_cash enabled (empty list, no flash error)" do
    user = User.create!(email: "no-cash@example.test", password: "Password123!", name: "NoCash")
    Seeders::Categories.call(user)
    Seeders::MerchantRules.call(user)

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    visit "/admin/cash_transactions"
    expect(page.status_code).to eq(200)
    expect(ManualTransaction.for_user(user).count).to eq(0)
  end

  def build_cash_user_with_linked_atm_withdrawal
    user = User.create!(
      email:    "cash-#{SecureRandom.hex(4)}@example.test",
      password: "Password123!",
      name:     "Cash User"
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
    atm_debit = BankTransaction.create!(
      bank_account:     account,
      external_id:      "atm-#{SecureRandom.hex(4)}",
      amount_cents:     200_00,
      currency:         "PLN",
      direction:        "debit",
      status:           "booked",
      payment_method:   "blik_atm",
      booking_date:     Date.current - 1.day,
      transaction_date: Date.current - 1.day,
      title:            "WYP. BANKOMAT",
      raw_payload:      "{}",
      fetched_at:       Time.current,
      counterparty_kind: "external"
    )

    user.update!(track_cash: true)
    result = Cash::Tracking.enable!(user: user, currency: "PLN")
    wallet = result.wallet
    expect(result.linked).to eq(1), "expected the BLIK ATM debit to be backfilled into a cash topup"
    atm_topup = ManualTransaction.where(linked_bank_transaction_id: atm_debit.id).first

    [ user, wallet, atm_topup, atm_debit ]
  end
end
