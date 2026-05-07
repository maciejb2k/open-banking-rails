# frozen_string_literal: true

require "rails_helper"

RSpec.describe "LLM enrichment confidence gate journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "auto-applies high-confidence proposals, queues low-confidence ones for review, and reclassifies transactions accordingly", :sidekiq_inline do
    user, account = seed_user_with_account
    user.create_llm_setting!(provider: "gemini", api_key: "fake-key", model: "gemini-2.5-flash")

    auto_high   = create_merchantless(account, title: "WWW.DEVSTYLE.PL")
    auto_high_2 = create_merchantless(account, title: "P.U.N.K.T 0123")
    pending_low = create_merchantless(account, title: "RZESZOWJANUSZEX 7745PL")
    pending_low_2 = create_merchantless(account, title: "MOSO POZNAN")
    Enrichment::TransactionEnricher.enrich_pending(user: user)

    fake_llm.respond_for_merchant_suggester(items: [
      build_suggestion(index: 0, name: "Devstyle",  pattern: "DEVSTYLE",  category_path: "lifestyle.tools.saas",         confidence: 0.95),
      build_suggestion(index: 1, name: "P.U.N.K.T", pattern: "P.U.N.K.T", category_path: "food.cooking.convenience",     confidence: 0.92),
      build_suggestion(index: 2, name: "Januszex",  pattern: "JANUSZEX",  category_path: "food.eating_out.fastfood",     confidence: 0.6),
      build_suggestion(index: 3, name: "Moso",      pattern: "MOSO",      category_path: "food.eating_out.restaurant",   confidence: 0.7)
    ])

    sign_in_as(user)
    visit admin_llm_enrichments_path
    expect(page).to have_text("AI Enrichment")
    click_button "Generate proposals"

    run = OperationRun.where(kind: "llm_enrichment", triggered_by_user: user).last
    expect(run.status).to eq("succeeded")
    expect(run.summary["auto_applied"]).to eq(2)
    expect(run.summary["pending_review"]).to eq(2)
    expect(run.summary["total_groups"]).to eq(4)
    expect(page).to have_current_path(admin_llm_enrichment_path(run))
    expect(page).to have_text("Auto-applied")
    expect(page).to have_text("Pending review")

    enabled_rules  = user.merchant_rules.where(source: "llm", enabled: true)
    disabled_rules = user.merchant_rules.where(source: "llm", enabled: false)
    expect(enabled_rules.pluck(:pattern)).to match_array(%w[DEVSTYLE P.U.N.K.T])
    expect(disabled_rules.pluck(:pattern)).to match_array(%w[JANUSZEX MOSO])

    expect(auto_high.reload.enrichment.merchant&.slug).to eq("devstyle")
    expect(auto_high_2.reload.enrichment.merchant&.slug).to eq("p_u_n_k_t")
    expect(pending_low.reload.enrichment.merchant_id).to be_nil
    expect(pending_low_2.reload.enrichment.merchant_id).to be_nil

    visit admin_llm_enrichments_path
    expect(page).to have_text("Awaiting approval (2)")
    expect(page).to have_text("Januszex")
    expect(page).to have_text("Moso")

    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
    assert_no_orphaned_enrichments!(user)
  end

  it "marks the run as failed with a clear error message when every batch raises Llm::Client::Error", :sidekiq_inline do
    user, account = seed_user_with_account
    user.create_llm_setting!(provider: "gemini", api_key: "fake-key", model: "gemini-2.5-flash")
    create_merchantless(account, title: "WWW.DEVSTYLE.PL")
    Enrichment::TransactionEnricher.enrich_pending(user: user)
    fake_llm.set_failure(message: "rate limit exceeded")

    sign_in_as(user)
    visit admin_llm_enrichments_path
    click_button "Generate proposals"

    run = OperationRun.where(kind: "llm_enrichment", triggered_by_user: user).last
    expect(run.status).to eq("failed")
    expect(run.error).to match(/All batches failed/)
    expect(run.error).to include("rate limit exceeded")
    expect(user.merchant_rules.where(source: "llm")).to be_empty

    expect(page).to have_current_path(admin_llm_enrichment_path(run))
    expect(page).to have_text("failed")
    expect(page).to have_text(/rate limit/i)

    assert_no_running_operation_runs!
  end

  it "marks the run as partial when some items in a batch raise RecordInvalid", :sidekiq_inline do
    user, account = seed_user_with_account
    user.create_llm_setting!(provider: "gemini", api_key: "fake-key", model: "gemini-2.5-flash")
    create_merchantless(account, title: "WWW.DEVSTYLE.PL")
    create_merchantless(account, title: "P.U.N.K.T 0123")
    Enrichment::TransactionEnricher.enrich_pending(user: user)

    fake_llm.respond_for_merchant_suggester(items: [
      build_suggestion(index: 0, name: "Devstyle",  pattern: "DEVSTYLE",  category_path: "lifestyle.tools.saas",     confidence: 0.95),
      build_suggestion(index: 1, name: "P.U.N.K.T", pattern: "P.U.N.K.T", category_path: "food.cooking.convenience", confidence: 0.92)
    ])
    allow_any_instance_of(MerchantRule).to receive(:save!).and_wrap_original do |original, *args|
      raise ActiveRecord::RecordInvalid.new(MerchantRule.new.tap { |r| r.errors.add(:pattern, "blew up") }) if original.receiver.pattern == "P.U.N.K.T"
      original.call(*args)
    end

    sign_in_as(user)
    visit admin_llm_enrichments_path
    click_button "Generate proposals"

    run = OperationRun.where(kind: "llm_enrichment", triggered_by_user: user).last
    expect(run.status).to eq("partial")
    expect(run.summary["auto_applied"]).to eq(1)
    expect(run.error).to match(/1 item\(s\) failed/)
    expect(user.merchant_rules.where(source: "llm").pluck(:pattern)).to eq([ "DEVSTYLE" ])

    assert_no_running_operation_runs!
  end

  it "refuses to enqueue a run with a clear flash when no LLM provider is configured" do
    user, _account = seed_user_with_account
    sign_in_as(user)

    visit admin_llm_enrichments_path
    expect(page).to have_text("No LLM provider configured")
    click_button "Generate proposals"

    expect(page).to have_text(/Configure an LLM provider/i)
    expect(OperationRun.where(kind: "llm_enrichment", triggered_by_user: user).count).to eq(0)
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

  def create_merchantless(account, title:)
    BankTransaction.create!(
      bank_account:      account,
      external_id:       "tx-#{SecureRandom.hex(6)}",
      amount_cents:      24_99,
      currency:          "PLN",
      direction:         "debit",
      status:            "booked",
      payment_method:    "card",
      counterparty_kind: "external",
      booking_date:      Date.current,
      transaction_date:  Date.current,
      title:             title,
      raw_payload:       "{}",
      fetched_at:        Time.current
    )
  end

  def build_suggestion(index:, name:, pattern:, category_path:, confidence:)
    {
      "index"         => index,
      "merchant_name" => name,
      "merchant_kind" => "company",
      "category_path" => category_path,
      "rule_field"    => "title",
      "rule_kind"     => "contains",
      "rule_pattern"  => pattern,
      "confidence"    => confidence,
      "reasoning"     => "test"
    }
  end
end
