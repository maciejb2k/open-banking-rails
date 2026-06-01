# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings change reflects in analytics journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "flips a category's essential flag through the categories form and updates the dashboard split immediately" do
    user, account = seed_user_with_account
    restaurants = user.categories.find_by!(path: "food.eating_out.restaurant")
    expect(restaurants.essential?).to be(false)
    restaurant_amount_cents = 60_00
    create_restaurant_transactions(user, account, category: restaurants, count: 3, each_cents: restaurant_amount_cents / 3)

    sign_in_as(user)
    visit admin_analytics_root_path
    expect(page).to have_text("Essentials vs discretionary")
    expect(page).to have_text("0.0% of spend covers needs")
    discretionary_money = Money.new(restaurant_amount_cents, "PLN").format(no_cents_if_whole: true)
    expect(page).to have_text(discretionary_money)

    visit admin_categories_path
    within "tr", text: "Restauracje" do
      expect(page).not_to have_text("essential")
    end

    visit edit_admin_category_path(restaurants)
    check "category[essential]"
    click_button "Save changes"

    expect(page).to have_current_path(admin_categories_path)
    expect(page).to have_text("Category updated.")
    within "tr", text: "Restauracje" do
      expect(page).to have_text("essential")
    end
    expect(restaurants.reload.essential?).to be(true)

    visit admin_analytics_root_path
    expect(page).to have_text("100.0% of spend covers needs")
    expect(LedgerEntry.for_user(user).booked.spend.essential.sum(:amount_cents)).to eq(restaurant_amount_cents)
    expect(LedgerEntry.for_user(user).booked.spend.discretionary.sum(:amount_cents)).to eq(0)

    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
  end

  it "keeps an archived category attributing spend to the same enrichment rows in analytics" do
    user, account = seed_user_with_account
    restaurants = user.categories.find_by!(path: "food.eating_out.restaurant")
    restaurant_amount_cents = 90_00
    create_restaurant_transactions(user, account, category: restaurants, count: 3, each_cents: restaurant_amount_cents / 3)

    sign_in_as(user)
    restaurants.archive!
    expect(restaurants.reload.archived?).to be(true)

    visit admin_categories_path
    expect(page).to have_text("Restauracje")

    spend_cents = LedgerEntry.for_user(user).booked.spend.where(currency: "PLN").sum(:amount_cents)
    expect(spend_cents).to eq(restaurant_amount_cents)

    breakdown = Analytics::SpendBreakdown.by_category(
      LedgerEntry.for_user(user).booked, user: user, currency: "PLN"
    )
    restaurant_row = breakdown.find { |r| r.path == restaurants.path.to_s }
    expect(restaurant_row).to be_present
    expect(restaurant_row.amount_cents).to eq(restaurant_amount_cents)

    visit admin_analytics_root_path
    money_text = Money.new(restaurant_amount_cents, "PLN").format(no_cents_if_whole: true)
    expect(page).to have_text(money_text)

    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
  end

  it "redirects back to the edit form with a 422 and surfaces the presence error when the name is blank" do
    user, _account = seed_user_with_account
    restaurants = user.categories.find_by!(path: "food.eating_out.restaurant")

    sign_in_as(user)
    visit edit_admin_category_path(restaurants)
    fill_in "category[name]", with: ""
    click_button "Save changes"

    expect(page).to have_text(/can't be blank/i)
    expect(restaurants.reload.name).to eq("Restauracje")
  end

  it "renders a friendly 422 instead of a 500 when the slug fails its format and would compose a malformed ltree path" do
    user, _account = seed_user_with_account
    restaurants = user.categories.find_by!(path: "food.eating_out.restaurant")

    sign_in_as(user)
    visit edit_admin_category_path(restaurants)
    fill_in "category[slug]", with: "Has Spaces!"
    click_button "Save changes"

    expect(page).to have_text(/lowercase letters/i)
    expect(restaurants.reload.slug).to eq("food_eating_out_restaurant")
  end

  def seed_user_with_account
    attempts = 0
    begin
      attempts += 1
      user = User.create!(email: "owner-#{SecureRandom.hex(4)}@example.test",
                          password: "Password123!", name: "Owner")
      Seeders::Categories.call(user)
      Seeders::MerchantRules.call(user)
      credential = user.tpp_credentials.create!(
        name: "Test TPP", provider: "enable_banking", environment: "SANDBOX",
        status: "active", primary: true, application_id: "fake-app",
        redirect_url: "http://localhost:3000/admin/oauth/enable_banking/callback",
        private_key_pem: OpenSSL::PKey::RSA.new(2048).to_pem
      )
      connection = BankConnection.create!(
        tpp_credential: credential, bank_slug: "pko_pl", bank_name: "PKO BP",
        bank_country: "PL", status: "authorized", psu_type: "personal",
        session_id: "sess-#{SecureRandom.hex(4)}", valid_until: 30.days.from_now,
        authorized_at: Time.current
      )
      account = BankAccount.create!(
        tpp_credential: credential, current_bank_connection: connection,
        uid: "acct-#{SecureRandom.hex(4)}", iban: "PL61109010140000071219812874",
        currency: "PLN", name: "Konto Osobiste", product: "Personal",
        cash_account_type: "CACC", status: "active", manual: false,
        all_account_ids: []
      )
      [ user, account ]
    rescue ActiveRecord::InvalidForeignKey, ActiveRecord::Deadlocked, ActiveRecord::RecordNotUnique, RuntimeError => e
      raise e if attempts > 40
      sleep(0.5 + (rand * 0.5))
      truncate_db rescue nil
      retry
    end
  end

  def create_restaurant_transactions(user, account, category:, count:, each_cents:)
    # Anchor every tx to the first of the month: the analytics "this month"
    # window is [beginning_of_month, today], so on the 1st it's a single day.
    # Spreading dates forward (booking + i.days) pushed txs past the window
    # end whenever the suite ran early in the month, dropping them from totals.
    booking = Date.current.beginning_of_month
    Array.new(count) do |i|
      tx = BankTransaction.create!(
        bank_account:      account,
        external_id:       "rest-#{i}-#{SecureRandom.hex(4)}",
        amount_cents:      each_cents,
        currency:          "PLN",
        direction:         "debit",
        status:            "booked",
        payment_method:    "card",
        counterparty_kind: "external",
        booking_date:      booking,
        transaction_date:  booking,
        title:             "RESTAURACJA NUMER #{i + 1}",
        raw_payload:       "{}",
        fetched_at:        Time.current
      )
      TransactionEnrichment.create!(
        enrichable: tx, category: category,
        category_overridden: true, source: "manual", enriched_at: Time.current
      )
      tx
    end
  end
end
