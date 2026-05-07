# frozen_string_literal: true

module Seeders
  # Builds a realistic, deterministic DB state by running production services
  # against the in-memory fakes. Used by smoke + system specs and by manual
  # exploration via `bin/rails runner 'Seeders::Showcase.call(user: User.first)'`.
  #
  # The seeder calls real Operations / Cash / Categories services - whatever
  # production produces, it produces. That keeps seeded state honest as the
  # production code evolves; the cost is a slow first run (hundreds of DB
  # roundtrips). Mitigation lives in the spec layer (before(:all) + truncation
  # between describe blocks).
  class Showcase
    Input = Struct.new(:user, :fake_eb, :fake_llm, :seed, :reference_time, keyword_init: true)

    Result = Struct.new(
      :success?,
      :user,
      :tpp_credentials,
      :connections,
      :accounts,
      :bank_transactions,
      :cash_transactions,
      :enrichments,
      :operation_runs,
      :sync_schedules,
      :error_messages,
      keyword_init: true
    ) do
      def error
        Array(error_messages).join(", ")
      end
    end

    DEFAULT_SEED           = 20_260_115
    DEFAULT_REFERENCE_TIME = "2026-01-15 12:00:00"

    def self.call(...) = new(...).call

    def initialize(user:, fake_eb: nil, fake_llm: nil, seed: DEFAULT_SEED, reference_time: nil)
      @user           = user
      @fake_eb        = fake_eb
      @fake_llm       = fake_llm
      @seed           = seed
      @reference_time = reference_time
    end

    def call
      validate_inputs!
      seed_random!

      Time.use_zone("Europe/Warsaw") do
        Timecop_or_travel(reference_time_value) do
          with_fake_eb_client_active do
            ActiveRecord::Base.transaction do
              seed_categories
              seed_merchant_rules
              seed_llm_setting
              credentials = seed_tpp_credentials
              configure_fake_eb_state(credentials)
              connections = seed_bank_connections(credentials)
              run_syncs(connections)
              wallet = seed_cash_wallet
              cash_txs = seed_cash_transactions(wallet)
              schedules = seed_sync_schedules(connections)
              seed_hidden_categories

              Result.new(
                success?:          true,
                user:              @user.reload,
                tpp_credentials:   credentials,
                connections:       connections,
                accounts:          BankAccount.where(tpp_credential: credentials).or(BankAccount.where(manual_owner: @user)).to_a,
                bank_transactions: BankTransaction.for_user(@user).to_a,
                cash_transactions: cash_txs,
                enrichments:       TransactionEnrichment.for_user(@user).to_a,
                operation_runs:    OperationRun.where(triggered_by_user: @user).to_a,
                sync_schedules:    schedules
              )
            end
          end
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error_messages: e.record.errors.full_messages)
    rescue StandardError => e
      Result.new(success?: false, error_messages: [ "#{e.class}: #{e.message}" ])
    end

    # Tests use the fakes_helpers stub of EnableBanking::Client.new — that
    # stub isn't active when called from `bin/rails runner`, so the seeder
    # temporarily redirects EnableBanking::Client.new to the supplied fake
    # so Operations::* calls reach the fake without surprise network I/O.
    def with_fake_eb_client_active
      eb_client_class = EnableBanking::Client
      already_stubbed = RSpec.respond_to?(:current_example) && RSpec.current_example
      return yield if already_stubbed

      target = @fake_eb
      original = eb_client_class.method(:new)
      eb_client_class.define_singleton_method(:new) { |*_args, **_kwargs| target }
      yield
    ensure
      eb_client_class.define_singleton_method(:new, original) if defined?(original) && original
    end

    private

    def validate_inputs!
      raise ArgumentError, "user required" if @user.nil?
      raise ArgumentError, "fake_eb required (test fake or production client)" if @fake_eb.nil?
      raise ArgumentError, "fake_llm required (test fake or production client)" if @fake_llm.nil?
    end

    def seed_random!
      srand(@seed)
      Faker::Config.random = Random.new(@seed) if defined?(Faker)
    end

    def reference_time_value
      return @reference_time if @reference_time.is_a?(Time) || @reference_time.is_a?(ActiveSupport::TimeWithZone)
      Time.zone.parse((@reference_time || DEFAULT_REFERENCE_TIME).to_s)
    end

    # ActiveSupport::Testing::TimeHelpers's travel_to is unavailable outside
    # specs, so we fall back to a no-op block for runner-style use.
    def Timecop_or_travel(time, &block)
      if respond_to?(:travel_to)
        travel_to(time, &block)
      else
        block.call
      end
    end

    def seed_categories
      Seeders::Categories.call(@user)
    end

    def seed_merchant_rules
      Seeders::MerchantRules.call(@user)
    end

    def seed_llm_setting
      setting = @user.llm_setting || @user.build_llm_setting
      setting.assign_attributes(provider: "gemini", api_key: "fake-gemini-key", model: "gemini-2.5-flash")
      setting.save!
      setting
    end

    def seed_tpp_credentials
      pko = upsert_credential(
        name: "PKO BP (Showcase)",
        primary: true,
        application_id: "fake-app-pko",
        redirect_url: "http://localhost:3000/admin/oauth/enable_banking/callback"
      )
      revolut = upsert_credential(
        name: "Revolut (Showcase)",
        primary: false,
        application_id: "fake-app-revolut",
        redirect_url: "http://localhost:3000/admin/oauth/enable_banking/callback"
      )
      [ pko, revolut ]
    end

    def upsert_credential(name:, primary:, application_id:, redirect_url:)
      cred = @user.tpp_credentials.find_or_initialize_by(name: name)
      cred.assign_attributes(
        provider:        "enable_banking",
        environment:     "SANDBOX",
        status:          "active",
        primary:         primary,
        application_id:  application_id,
        redirect_url:    redirect_url,
        private_key_pem: rsa_pem,
        public_cert_pem: nil,
        last_verified_at: Time.current
      )
      cred.save!
      cred
    end

    def rsa_pem
      @rsa_pem ||= OpenSSL::PKey::RSA.new(2048).to_pem
    end

    def configure_fake_eb_state(credentials)
      pko_session     = @fake_eb.add_session(aspsp_name: "PKO BP", country: "PL", valid_until: 30.days.from_now)
      revolut_session = @fake_eb.add_session(aspsp_name: "Revolut LT", country: "LT", valid_until: 90.days.from_now)
      expired_session = @fake_eb.add_session(aspsp_name: "PKO BP", country: "PL", valid_until: 1.day.ago)
      @fake_eb.expire_session(expired_session)

      @pko_account_uid     = @fake_eb.add_account(session_id: pko_session,     currency: "PLN", balance_cents: 12_345_67, holder_name: "MACIEJ TEST", iban: "PL61109010140000071219812874", product: "Konto Osobiste")
      @pko_savings_uid     = @fake_eb.add_account(session_id: pko_session,     currency: "PLN", balance_cents: 50_000_00, holder_name: "MACIEJ TEST", iban: "PL61109010140000071219812875", product: "Konto Oszczędnościowe")
      @revolut_eur_uid     = @fake_eb.add_account(session_id: revolut_session, currency: "EUR", balance_cents: 1_500_00,  holder_name: "Maciej Test", iban: "LT123456789012345678",         product: "EUR Pocket", alternate_ibans: [ "PL00000000000000000000000099" ])
      @revolut_usd_uid     = @fake_eb.add_account(session_id: revolut_session, currency: "USD", balance_cents: 250_00,    holder_name: "Maciej Test", iban: "LT123456789012345678",         product: "USD Pocket")

      seed_pko_transactions
      seed_revolut_transactions

      @sessions = { pko: pko_session, revolut: revolut_session, expired: expired_session }
    end

    def seed_pko_transactions
      base = Date.current - 80.days
      30.times do |i|
        date = base + (i * 2).days
        @fake_eb.add_transaction(
          account_uid: @pko_account_uid,
          amount_cents: -([ 19_99, 45_00, 12_50, 156_00, 8_99, 220_00 ][i % 6]),
          direction: "debit",
          booking_date: date,
          title: [ "BIEDRONKA WARSZAWA", "ZABKA NANO", "MCDONALD'S 5230", "T-MOBILE POLSKA", "ROSSMANN 0123", "DECATHLON" ][i % 6],
          payment_method_hint: "card"
        )
      end

      6.times do |i|
        @fake_eb.add_transaction(
          account_uid: @pko_account_uid,
          amount_cents: -200_00,
          direction: "debit",
          booking_date: base + (i * 12).days,
          title: "WYP. BANKOMAT",
          type_hint: "BLIK ATM",
          bank_transaction_code: "ATM"
        )
      end

      3.times do |i|
        @fake_eb.add_transaction(
          account_uid: @pko_account_uid,
          amount_cents: 6_500_00,
          direction: "credit",
          booking_date: base + (i * 28).days + 5,
          title: "WYNAGRODZENIE",
          counterparty_name: "Some Company sp. z o.o."
        )
      end
    end

    def seed_revolut_transactions
      base = Date.current - 80.days
      15.times do |i|
        date = base + (i * 5).days
        @fake_eb.add_transaction(
          account_uid: @revolut_eur_uid,
          amount_cents: -([ 9_99, 14_99, 5_00, 25_00 ][i % 4]),
          currency: "EUR",
          direction: "debit",
          booking_date: date,
          title: [ "Spotify", "Netflix", "OpenAI", "Anthropic" ][i % 4],
          counterparty_name: [ "Spotify AB", "Netflix Intl.", "Openai LLC", "Anthropic" ][i % 4]
        )
      end
    end

    def seed_bank_connections(credentials)
      pko, revolut = credentials
      conn_pko     = create_connection(pko, code: @sessions[:pko], aspsp_name: "PKO BP", aspsp_country: "PL", psu_type: "personal")
      conn_revolut = create_connection(revolut, code: @sessions[:revolut], aspsp_name: "Revolut LT", aspsp_country: "LT", psu_type: "personal")
      [ conn_pko, conn_revolut ]
    end

    def create_connection(credential, code:, aspsp_name:, aspsp_country:, psu_type:)
      ::EnableBanking::Operations::CreateConnection.call(
        credential: credential,
        code:       code,
        state:      { aspsp_name: aspsp_name, aspsp_country: aspsp_country, psu_type: psu_type }
      )
    end

    def run_syncs(connections)
      connections.each do |connection|
        run = OperationRun.create!(
          kind: "transaction_sync", status: "running", trigger: "manual",
          started_at: Time.current, triggered_by_user: @user, subject: connection,
          params: { connection_id: connection.id }, summary: {}
        )
        ::EnableBanking::Operations::SyncConnectionTransactions.call(connection)
        ::Enrichment::TransactionEnricher.rebuild!(user: @user)
        run.succeed!(summary: { synced_at: Time.current })
      rescue StandardError => e
        run&.fail!(error: e.message)
      end
    end

    def seed_cash_wallet
      @user.update!(track_cash: true) unless @user.track_cash?
      ::Cash::Tracking.enable!(user: @user, currency: "PLN").wallet
    end

    def seed_cash_transactions(_wallet)
      base = Date.current - 4.months
      created = []
      [ "Coffee at office", "Tip at restaurant", "Newspaper", "Charity coin", "Lottery", "Parking meter" ].each_with_index do |title, i|
        result = ::Cash::TransactionCreator.call(
          user:  @user,
          input: ::Cash::TransactionCreator::Input.new(
            amount:         (5 + i * 3).to_s,
            currency:       "PLN",
            direction:      "debit",
            booking_date:   (base + (i * 7).days).to_s,
            title:          title,
            payment_method: "cash"
          )
        )
        created << result.transaction if result.success?
      end
      created
    end

    def seed_sync_schedules(connections)
      connections.map.with_index do |connection, i|
        ::AutoSync::ScheduleUpserter.call(
          connection: connection,
          user:       @user,
          input:      ::AutoSync::ScheduleUpserter::Input.new(
            enabled:        i.zero?,
            cadence:        "daily",
            preferred_hour: 8
          )
        ).schedule
      end
    end

    def seed_hidden_categories
      hidden = @user.categories.where(slug: %w[noise_authorizations noise_adjustments_fx]).to_a
      hidden.each do |cat|
        UserHiddenCategory.find_or_create_by!(user: @user, category: cat)
      end
    end
  end
end
