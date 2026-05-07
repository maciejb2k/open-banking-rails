# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cross-user isolation journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "shows user B an empty bank-transactions index when user A has transactions and they sign in as B" do
    user_a, user_b = build_two_users
    seed_bank_transaction(user_a, title: "BIEDRONKA WARSZAWA")

    sign_in_via_form(user_b)
    visit admin_bank_transactions_path

    expect(page).to have_http_status(:ok)
    expect(page).not_to have_text("BIEDRONKA WARSZAWA")
    expect(BankTransaction.for_user(user_b).count).to eq(0)
  end

  it "404s when user B deep-links to user A's bank_connection show page" do
    user_a, user_b = build_two_users
    foreign_connection = user_a.bank_connections.first

    sign_in_via_form(user_b)
    visit admin_bank_connection_path(foreign_connection)

    expect(page).to have_http_status(:not_found)
  end

  it "404s when user B deep-links to user A's tpp_credential show page" do
    user_a, user_b = build_two_users
    foreign_credential = user_a.tpp_credentials.first

    sign_in_via_form(user_b)
    visit admin_tpp_credential_path(foreign_credential)

    expect(page).to have_http_status(:not_found)
  end

  it "404s when user B deep-links to user A's bank_account show page" do
    user_a, user_b = build_two_users
    foreign_account = user_a.bank_connections.first.current_bank_accounts.first

    sign_in_via_form(user_b)
    visit admin_bank_account_path(foreign_account)

    expect(page).to have_http_status(:not_found)
  end

  it "404s when user B deep-links to a single bank_transaction owned by user A" do
    user_a, user_b = build_two_users
    foreign_tx = seed_bank_transaction(user_a, title: "FOREIGN TX")

    sign_in_via_form(user_b)
    visit admin_bank_transaction_path(foreign_tx)

    expect(page).to have_http_status(:not_found)
  end

  it "lists only user B's seeded categories on /admin/categories and does not leak user A's category names" do
    user_a, user_b = build_two_users

    sign_in_via_form(user_b)
    visit admin_categories_path

    expect(page).to have_http_status(:ok)
    a_category = user_a.categories.where(kind: "expense").first
    b_category = user_b.categories.where(kind: "expense").first
    expect(a_category).to be_present
    expect(b_category).to be_present
    expect(Category.where(user: user_b).pluck(:id)).not_to include(a_category.id)
    expect(Category.where(user: user_b).pluck(:id)).to include(b_category.id)
  end

  it "404s when user B deep-links to user A's llm_enrichment OperationRun show page" do
    user_a, user_b = build_two_users
    foreign_run = OperationRun.create!(
      kind: "llm_enrichment", status: "succeeded", trigger: "manual",
      started_at: 2.minutes.ago, finished_at: 1.minute.ago,
      triggered_by_user: user_a, subject: user_a, params: {}, summary: { "enriched" => 0 }
    )

    sign_in_via_form(user_b)
    visit admin_llm_enrichment_path(foreign_run)

    expect(page).to have_http_status(:not_found)
  end

  it "404s when user B deep-links to a category slug that exists only on user A's tree" do
    user_a, user_b = build_two_users
    private_slug = "a_private_branch_#{SecureRandom.hex(4)}"
    user_a.categories.create!(
      name: "A Private Branch",
      slug: private_slug,
      path: "spending.#{private_slug}",
      kind: "expense"
    )

    sign_in_via_form(user_b)
    visit admin_analytics_category_path(private_slug)

    expect(page).to have_http_status(:not_found)
  end

  def build_two_users
    user_a = build_user_with_banking(prefix: "isolation-a", name: "Isolation A")
    user_b = User.create!(
      email:    "isolation-b-#{SecureRandom.hex(4)}@example.test",
      password: "Password123!",
      name:     "Isolation B"
    )
    Seeders::Categories.call(user_b)
    Seeders::MerchantRules.call(user_b)
    [ user_a, user_b ]
  end

  def build_user_with_banking(prefix:, name:)
    user = User.create!(
      email:    "#{prefix}-#{SecureRandom.hex(4)}@example.test",
      password: "Password123!",
      name:     name
    )
    Seeders::Categories.call(user)
    Seeders::MerchantRules.call(user)
    credential = user.tpp_credentials.create!(
      name:            "#{name} TPP",
      provider:        "enable_banking",
      environment:     "SANDBOX",
      status:          "active",
      primary:         true,
      application_id:  "fake-app-#{SecureRandom.hex(4)}",
      redirect_url:    "http://localhost:3000/admin/oauth/enable_banking/callback",
      private_key_pem: "fake-pem"
    )
    connection = credential.bank_connections.create!(
      bank_slug:           "#{prefix}_bank",
      bank_country:        "PL",
      bank_name:           "#{name} Bank",
      status:              "authorized",
      psu_type:            "personal",
      session_id:          "sess-#{SecureRandom.hex(4)}",
      valid_until:         30.days.from_now,
      authorized_at:       Time.current,
      access_balances:     true,
      access_transactions: true
    )
    BankAccount.create!(
      uid:                     "iso-uid-#{prefix}",
      iban:                    "PL61109010140000071219#{format('%06d', user.id)}",
      currency:                "PLN",
      name:                    "#{name} Account",
      product:                 "Personal",
      cash_account_type:       "CACC",
      status:                  "active",
      tpp_credential:          credential,
      current_bank_connection: connection,
      all_account_ids:         []
    )
    user
  end

  def seed_bank_transaction(user, title:)
    account = user.bank_connections.first.current_bank_accounts.first
    BankTransaction.create!(
      bank_account:     account,
      external_id:      "iso-tx-#{SecureRandom.hex(6)}",
      amount_cents:     42_99,
      currency:         "PLN",
      direction:        "debit",
      status:           "booked",
      payment_method:   "card",
      booking_date:     Date.current,
      transaction_date: Date.current,
      title:            title,
      raw_payload:      "{}",
      fetched_at:       Time.current,
      counterparty_kind: "external"
    )
  end

  def sign_in_via_form(user)
    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"
  end
end
