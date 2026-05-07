# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categorization workflow journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "rebuilds historical enrichments to point at a user merchant when a user rule is added on top of a system rule" do
    user, account = seed_user_with_account
    seeded_zabka = user.merchants.find_by!(slug: "zabka")
    transactions = create_zabka_transactions(account, count: 5)
    Enrichment::TransactionEnricher.enrich_pending(user: user)

    expect(transactions.map { |t| t.reload.enrichment.merchant_id }.uniq).to eq([ seeded_zabka.id ])
    expect(transactions.first.enrichment.source).to eq("system_rule")

    sign_in_as(user)
    supermarket = user.categories.find_by!(path: "food.cooking.supermarket")

    visit new_admin_merchant_path
    fill_in "merchant[name]", with: "Zabka local"
    find("#merchant_default_category_id", visible: :all).set(supermarket.id.to_s)
    click_button "Create merchant"

    new_merchant = user.merchants.find_by!(slug: "zabka_local")
    expect(page).to have_current_path(admin_merchant_path(new_merchant))
    expect(page).to have_text("Zabka local")

    select "title",    from: "merchant_rule[field]"
    select "contains", from: "merchant_rule[kind]"
    fill_in "merchant_rule[pattern]", with: "ZABKA"
    click_button "Add"

    expect(page).to have_current_path(admin_merchant_path(new_merchant))
    expect(page).to have_text(/Rule added.*re-classified/i)

    expect(transactions.map { |t| t.reload.enrichment.merchant_id }.uniq).to eq([ new_merchant.id ])
    expect(transactions.map { |t| t.enrichment.source }.uniq).to eq([ "user_rule" ])

    visit admin_bank_transactions_path(merchant_id: new_merchant.id)
    expect(page).to have_text("ZABKA NANO", count: 5)
    expect(page).to have_text("Supermarkety", minimum: 5)

    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
    assert_no_orphaned_enrichments!(user)
  end

  it "preserves a manual category override when an unrelated user rule fires a rebuild" do
    user, account = seed_user_with_account
    transactions = create_zabka_transactions(account, count: 5)
    Enrichment::TransactionEnricher.enrich_pending(user: user)

    pinned     = transactions.first
    pinned_cat = user.categories.find_by!(path: "food.eating_out.fastfood")
    Enrichment::ClassificationApplier.call(
      transaction: pinned,
      actor:       user,
      input:       Enrichment::ClassificationApplier::Input.new(
        mode:     :only_this,
        merchant: pinned.enrichment.merchant,
        category: pinned_cat
      )
    )
    pinned.reload
    expect(pinned.enrichment.category_overridden?).to be(true)
    expect(pinned.enrichment.category_id).to eq(pinned_cat.id)

    sign_in_as(user)
    supermarket = user.categories.find_by!(path: "food.cooking.supermarket")

    visit new_admin_merchant_path
    fill_in "merchant[name]", with: "Zabka local"
    find("#merchant_default_category_id", visible: :all).set(supermarket.id.to_s)
    click_button "Create merchant"

    select "title",    from: "merchant_rule[field]"
    select "contains", from: "merchant_rule[kind]"
    fill_in "merchant_rule[pattern]", with: "ZABKA"
    click_button "Add"

    new_merchant = user.merchants.find_by!(slug: "zabka_local")
    pinned.reload
    expect(pinned.enrichment.category_id).to eq(pinned_cat.id)
    expect(pinned.enrichment.category_overridden?).to be(true)

    rebuilt = transactions[1..]
    expect(rebuilt.map { |t| t.reload.enrichment.merchant_id }.uniq).to eq([ new_merchant.id ])
    expect(rebuilt.map { |t| t.enrichment.source }.uniq).to eq([ "user_rule" ])

    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
  end

  it "lets a user rule beat an LLM-source rule that already covers the same pattern" do
    user, account = seed_user_with_account
    transactions = create_zabka_transactions(account, count: 5)

    llm_merchant = user.merchants.create!(
      name: "Zabka (AI guess)", slug: "zabka_ai", source: "llm",
      default_category: user.categories.find_by!(path: "food.cooking.convenience"),
      confidence: 0.7, approved_at: Time.current
    )
    llm_merchant.merchant_rules.create!(
      user: user, source: "llm", field: "title", kind: "contains",
      pattern: "ZABKA", priority: 50, enabled: true, confidence: 0.7
    )

    user.merchants.find_by!(slug: "zabka").merchant_rules.update_all(enabled: false)
    Enrichment::TransactionEnricher.enrich_pending(user: user)

    expect(transactions.map { |t| t.reload.enrichment.merchant_id }.uniq).to eq([ llm_merchant.id ])
    expect(transactions.first.enrichment.source).to eq("llm_rule")

    sign_in_as(user)
    supermarket = user.categories.find_by!(path: "food.cooking.supermarket")

    visit new_admin_merchant_path
    fill_in "merchant[name]", with: "Zabka local"
    find("#merchant_default_category_id", visible: :all).set(supermarket.id.to_s)
    click_button "Create merchant"

    select "title",    from: "merchant_rule[field]"
    select "contains", from: "merchant_rule[kind]"
    fill_in "merchant_rule[pattern]", with: "ZABKA"
    click_button "Add"

    new_merchant = user.merchants.find_by!(slug: "zabka_local")
    expect(transactions.map { |t| t.reload.enrichment.merchant_id }.uniq).to eq([ new_merchant.id ])
    expect(transactions.map { |t| t.enrichment.source }.uniq).to eq([ "user_rule" ])

    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
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

  def create_zabka_transactions(account, count:)
    Array.new(count) do |i|
      BankTransaction.create!(
        bank_account:      account,
        external_id:       "zabka-#{i}-#{SecureRandom.hex(4)}",
        amount_cents:      12_50,
        currency:          "PLN",
        direction:         "debit",
        status:            "booked",
        payment_method:    "card",
        counterparty_kind: "external",
        booking_date:      Date.current - i.days,
        transaction_date:  Date.current - i.days,
        title:             "ZABKA NANO #{1000 + i}",
        raw_payload:       "{}",
        fetched_at:        Time.current
      )
    end
  end
end
