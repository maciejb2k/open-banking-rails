# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auto-sync circuit breaker journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
    Sidekiq::Testing.fake!
  end

  it "trips the breaker after FAILURE_THRESHOLD consecutive scheduled failures, sets paused_until, and surfaces a Paused badge on the syncs index" do
    user = create_seeded_user(email: "breaker-trip@example.test")
    connection, account_uid = attach_authorized_connection(user, slug: "pko_bp", aspsp_name: "PKO BP", country: "PL", iban_suffix: "020")
    schedule = SyncSchedule.create!(
      bank_connection: connection,
      enabled:         true,
      cadence:         "daily",
      preferred_hour:  8,
      next_run_at:     1.minute.ago
    )
    fake_eb.simulate_failure(method: :get, path: "/accounts/#{account_uid}/transactions", status: 500, error: "Upstream is angry", count: SyncSchedule::FAILURE_THRESHOLD)
    sign_in_as(user)

    SyncSchedule::FAILURE_THRESHOLD.times do
      Sidekiq::Testing.inline! do
        AutoSync::DispatcherJob.perform_now
      end
      schedule.update_columns(next_run_at: 1.minute.ago, paused_until: nil) if schedule.reload.consecutive_failures < SyncSchedule::FAILURE_THRESHOLD
    end

    failed_runs = OperationRun.where(triggered_by_user: user, trigger: "scheduled", status: "failed")
    expect(failed_runs.count).to eq(SyncSchedule::FAILURE_THRESHOLD)

    schedule.reload
    expect(schedule.consecutive_failures).to eq(SyncSchedule::FAILURE_THRESHOLD)
    expect(schedule.paused_until).to be_present
    expect(schedule.paused_until).to be_within(2.minutes).of(AutoSync::CircuitBreaker::COOLDOWN.from_now)

    visit "/admin/transaction_syncs"
    expect(page).to have_text("PKO BP")
    expect(page).to have_text("Paused")
  end

  it "skips a tripped schedule on the next due tick without creating a new OperationRun while leaving an unrelated connection's schedule running" do
    user = create_seeded_user(email: "breaker-skip@example.test")
    tripped_conn, tripped_uid = attach_authorized_connection(user, slug: "pko_bp", aspsp_name: "PKO BP", country: "PL", iban_suffix: "030")
    healthy_conn, healthy_uid = attach_authorized_connection(user, slug: "revolut_lt", aspsp_name: "Revolut LT", country: "LT", iban_suffix: "031", currency: "EUR")
    SyncSchedule.create!(
      bank_connection:      tripped_conn,
      enabled:              true,
      cadence:              "daily",
      preferred_hour:       8,
      next_run_at:          1.minute.ago,
      consecutive_failures: SyncSchedule::FAILURE_THRESHOLD,
      paused_until:         AutoSync::CircuitBreaker::COOLDOWN.from_now
    )
    SyncSchedule.create!(
      bank_connection: healthy_conn,
      enabled:         true,
      cadence:         "daily",
      preferred_hour:  8,
      next_run_at:     1.minute.ago
    )
    fake_eb.add_transaction(account_uid: healthy_uid, amount_cents: -10_00, currency: "EUR", direction: "debit", booking_date: Date.current, title: "Spotify AB")
    sign_in_as(user)

    Sidekiq::Testing.inline! do
      AutoSync::DispatcherJob.perform_now
    end

    runs = OperationRun.where(triggered_by_user: user, trigger: "scheduled").order(:id)
    expect(runs.pluck(:subject_id, :status)).to eq([ [ healthy_conn.id, "succeeded" ] ])
    expect(OperationRun.where(subject: tripped_conn, trigger: "scheduled")).to be_empty
    expect(BankTransaction.where(bank_account_id: BankAccount.where(uid: tripped_uid).select(:id))).to be_empty
  end

  it "still runs a manual sync triggered from the admin UI while the breaker is tripped (manual trigger is exempt from the breaker gate)" do
    user = create_seeded_user(email: "breaker-manual@example.test")
    connection, account_uid = attach_authorized_connection(user, slug: "pko_bp", aspsp_name: "PKO BP", country: "PL", iban_suffix: "040")
    SyncSchedule.create!(
      bank_connection:      connection,
      enabled:              true,
      cadence:              "daily",
      preferred_hour:       8,
      next_run_at:          1.minute.ago,
      consecutive_failures: SyncSchedule::FAILURE_THRESHOLD,
      paused_until:         AutoSync::CircuitBreaker::COOLDOWN.from_now
    )
    fake_eb.add_transaction(account_uid: account_uid, amount_cents: -42_99, direction: "debit", booking_date: Date.current, title: "MCDONALD'S 5230", payment_method_hint: "card")
    sign_in_as(user)

    Sidekiq::Testing.inline! do
      visit "/admin/transaction_syncs/new"
      select "PKO BP", from: "bank_connection_id"
      click_button "Start sync"
    end

    manual_run = OperationRun.where(triggered_by_user: user, trigger: "manual", subject: connection).order(:id).last
    expect(manual_run).to be_present
    expect(manual_run.status).to eq("succeeded")
    expect(BankTransaction.for_user(user).count).to eq(1)

    expect(connection.sync_schedule.reload.consecutive_failures).to eq(SyncSchedule::FAILURE_THRESHOLD)
    expect(connection.sync_schedule.paused_until).to be_present
  end

  def create_seeded_user(email:)
    user = User.create!(email: email, password: "Password123!", name: "Breaker User")
    Seeders::Categories.call(user)
    Seeders::MerchantRules.call(user)
    user
  end

  def attach_authorized_connection(user, slug:, aspsp_name:, country:, iban_suffix:, currency: "PLN")
    credential = user.tpp_credentials.find_or_create_by!(name: "#{aspsp_name} (Breaker)") do |c|
      c.provider        = "enable_banking"
      c.environment     = "SANDBOX"
      c.status          = "active"
      c.primary         = user.tpp_credentials.none?
      c.application_id  = "fake-app-#{slug}"
      c.redirect_url    = "http://localhost:3000/admin/oauth/enable_banking/callback"
      c.private_key_pem = "fake-pem"
    end
    connection = credential.bank_connections.create!(
      bank_slug:           slug,
      bank_country:        country,
      bank_name:           aspsp_name,
      status:              "authorized",
      psu_type:            "personal",
      session_id:          "sess-#{SecureRandom.hex(4)}",
      valid_until:         30.days.from_now,
      authorized_at:       Time.current,
      access_balances:     true,
      access_transactions: true
    )
    session_id = fake_eb.add_session(aspsp_name: aspsp_name, country: country, valid_until: 30.days.from_now)
    iban = "PL61109010140000071219#{iban_suffix.rjust(6, '0')}"
    uid = fake_eb.add_account(
      session_id:    session_id,
      uid:           "acc-#{slug}-#{SecureRandom.hex(3)}",
      currency:      currency,
      balance_cents: 100_00,
      holder_name:   user.name,
      iban:          iban
    )
    BankAccount.create!(
      uid:                     uid,
      iban:                    iban,
      currency:                currency,
      name:                    "#{aspsp_name} Personal",
      product:                 "Personal",
      cash_account_type:       "CACC",
      status:                  "active",
      tpp_credential:          credential,
      current_bank_connection: connection,
      all_account_ids:         []
    )
    [ connection, uid ]
  end
end
