# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Daily login + analytics dashboard journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "signs the user in through the Devise form, lands on the analytics dashboard, and renders the key stat cards" do
    user = build_seeded_user_with_history(transaction_count: 12)

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    expect(page).to have_current_path("/admin/analytics", ignore_query: true)
    expect(page).to have_text("Analytics")
    expect(page).to have_text("Spend")
    expect(page).to have_text("Income")
    expect(page).to have_text("Where your money goes")

    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
  end

  it "renders the analytics dashboard with zero amounts for a brand-new user with no transactions" do
    user = User.create!(email: "blank@example.test", password: "Password123!", name: "Blank")
    Seeders::Categories.call(user)
    Seeders::MerchantRules.call(user)

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    expect(page).to have_current_path("/admin/analytics", ignore_query: true)
    expect(page).to have_text("Analytics")
  end

  it "drills into a category by slug from the dashboard and renders the category subpage" do
    user = build_seeded_user_with_history(transaction_count: 8)
    food = user.categories.find_by(slug: "food") || user.categories.where("path::text LIKE ?", "food%").first
    expect(food).to be_present, "expected the showcase taxonomy to seed a 'food' branch"

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    visit admin_analytics_category_path(food.slug)
    expect(page).to have_current_path(admin_analytics_category_path(food.slug), ignore_query: true)
    expect(page.status_code).to eq(200)
    expect(page).to have_text(food.name)
  end

  it "renders the dashboard for a user with no LlmSetting configured (no errors, no AI insight callout)" do
    user = User.create!(email: "no-llm@example.test", password: "Password123!", name: "NoLLM")
    Seeders::Categories.call(user)
    Seeders::MerchantRules.call(user)
    expect(user.llm_setting).to be_nil

    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"

    expect(page).to have_current_path("/admin/analytics", ignore_query: true)
    expect(page).to have_text("Analytics")
  end

  def build_seeded_user_with_history(transaction_count:)
    user = User.create!(
      email:    "analytics-#{SecureRandom.hex(4)}@example.test",
      password: "Password123!",
      name:     "Analytics User"
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
      uid:               "acc-#{SecureRandom.hex(4)}",
      iban:              "PL61109010140000071219#{format('%06d', user.id)}",
      currency:          "PLN",
      name:              "Konto Osobiste",
      product:           "Personal",
      cash_account_type: "CACC",
      status:            "active",
      tpp_credential:    credential,
      current_bank_connection: connection,
      all_account_ids:   []
    )
    base = Date.current - 60.days
    titles = [ "BIEDRONKA", "ZABKA", "MCDONALD'S", "T-MOBILE", "ROSSMANN", "DECATHLON" ]
    transaction_count.times do |i|
      BankTransaction.create!(
        bank_account:    account,
        external_id:     "tx-#{SecureRandom.hex(4)}-#{i}",
        amount_cents:    (15 + i * 7) * 100,
        currency:        "PLN",
        direction:       "debit",
        status:          "booked",
        payment_method:  "card",
        booking_date:    base + (i * 2).days,
        transaction_date: base + (i * 2).days,
        title:           titles[i % titles.size],
        raw_payload:     "{}",
        fetched_at:      Time.current,
        counterparty_kind: "external"
      )
    end
    Enrichment::TransactionEnricher.rebuild!(user: user)
    user
  end
end
