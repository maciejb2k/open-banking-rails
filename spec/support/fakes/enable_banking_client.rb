# frozen_string_literal: true

module Fakes
  # In-memory implementation of EnableBanking::Client. Mirrors the public
  # interface (get/post/delete returning EnableBanking::Result) and adds
  # UI-faker methods so tests configure the bank's state as if they were
  # operating its UI, then run real production code (Api::*, Operations::*)
  # against the fake.
  #
  # The fake intentionally short-circuits Enable Banking's pagination,
  # JWT signing, PSU header logic, and ASPSP-specific quirks. Wire-format
  # tests in spec/services/enable_banking/adapter_spec.rb cover the real
  # adapter via WebMock; everything else uses this.
  class EnableBankingClient
    SequenceCounter = Class.new do
      def initialize
        @n = 0
      end
      def next!
        @n += 1
      end
    end

    attr_reader :recorded_calls

    def initialize(*_args, **_kwargs)
      @aspsps              = []
      @sessions            = {}
      @accounts            = {}
      @balances            = {}
      @transactions        = Hash.new { |h, k| h[k] = [] }
      @scheduled_failures  = Hash.new { |h, k| h[k] = [] }
      @recorded_calls      = []
      @session_counter     = SequenceCounter.new
      @transaction_counter = SequenceCounter.new
      @transactions_page_size = nil
      @application_redirect_urls = nil
    end

    # Override what /application returns under "redirect_urls". Off by default
    # so existing specs see the legacy single-URL payload; opt-in for
    # VerifyCredential's reconciliation branches.
    attr_writer :application_redirect_urls

    # Opt-in pagination simulation. When set, transactions_page returns
    # `size` items at a time and surfaces a continuation_key the caller
    # must echo back to fetch the next page. Off by default - existing
    # specs that don't care about pagination see the legacy single-page
    # behavior.
    def transactions_page_size=(size)
      @transactions_page_size = size
    end

    def get(path, params = {})
      record_call(:get, path, params)
      failure = pop_failure(:get, path)
      return failure if failure

      case path
      when "/application"
        respond(application_payload)
      when "/aspsps"
        respond({ "aspsps" => @aspsps.select { |a| params[:country].nil? || a["country"] == params[:country] } })
      when %r{\A/sessions/(?<sid>[^/]+)\z}
        sid = Regexp.last_match[:sid]
        session = @sessions[sid]
        return not_found("session #{sid}") unless session
        respond(session_get_payload(session))
      when %r{\A/accounts/(?<uid>[^/]+)/balances\z}
        uid = Regexp.last_match[:uid]
        return not_found("account #{uid}") unless @accounts[uid]
        respond(@balances[uid] || default_balance_payload(@accounts[uid]))
      when %r{\A/accounts/(?<uid>[^/]+)/details\z}
        uid = Regexp.last_match[:uid]
        account = @accounts[uid]
        return not_found("account #{uid}") unless account
        respond(account_details_payload(account))
      when %r{\A/accounts/(?<uid>[^/]+)/transactions\z}
        uid = Regexp.last_match[:uid]
        return not_found("account #{uid}") unless @accounts[uid]
        respond(transactions_page(uid, params))
      else
        not_found(path)
      end
    end

    def post(path, body = {})
      record_call(:post, path, body)
      failure = pop_failure(:post, path)
      return failure if failure

      case path
      when "/auth"
        state = body[:state] || body["state"]
        respond({ "url" => "https://fake.enablebanking.test/auth?state=#{state}" })
      when "/sessions"
        respond(create_session_payload(body))
      else
        not_found(path)
      end
    end

    def delete(path)
      record_call(:delete, path, nil)
      failure = pop_failure(:delete, path)
      return failure if failure

      case path
      when %r{\A/sessions/(?<sid>[^/]+)\z}
        sid = Regexp.last_match[:sid]
        @sessions.delete(sid)
        respond({ "deleted" => true })
      else
        not_found(path)
      end
    end

    def add_aspsp(name:, country:, supported_features: %w[balances transactions], **extra)
      @aspsps << { "name" => name, "country" => country, "supported_features" => supported_features }.merge(extra.transform_keys(&:to_s))
    end

    def add_session(aspsp_name:, country: "PL", status: "AUTHORIZED", valid_until: 30.days.from_now, psu_type: "personal", id: nil)
      sid = id || "fake-session-#{@session_counter.next!}"
      @sessions[sid] = {
        "id"              => sid,
        "aspsp_name"      => aspsp_name,
        "country"         => country,
        "status"          => status,
        "valid_until"     => valid_until,
        "psu_type"        => psu_type,
        "psu_id_hash"     => "psu-hash-#{sid}",
        "authorized_at"   => Time.current,
        "account_uids"    => [],
        "raw_account_ids" => []
      }
      sid
    end

    def add_account(session_id:, uid: nil, currency: "PLN", balance_cents: 0, holder_name: "Account Holder", iban: nil, product: "Personal", cash_account_type: "CACC", details: nil, alternate_ibans: [])
      session = @sessions.fetch(session_id) { raise ArgumentError, "Unknown session #{session_id}" }
      uid ||= "fake-account-#{session_id}-#{session['account_uids'].size + 1}"
      iban ||= "PL#{60 + session['account_uids'].size}1020100000000#{format('%012d', uid.bytes.sum)}"

      account = {
        "uid"               => uid,
        "session_id"        => session_id,
        "currency"          => currency,
        "balance_cents"     => balance_cents,
        "holder_name"       => holder_name,
        "iban"              => iban,
        "product"           => product,
        "cash_account_type" => cash_account_type,
        "details"           => details || product,
        "alternate_ibans"   => Array(alternate_ibans)
      }
      @accounts[uid] = account
      session["account_uids"] << uid
      uid
    end

    def add_transaction(account_uid:, amount_cents:, currency: nil, direction: "debit", status: "booked",
                        booking_date: Date.current, value_date: nil, transaction_date: nil,
                        title: "Test transaction", type_hint: nil,
                        counterparty_name: nil, counterparty_iban: nil,
                        payment_method_hint: nil, bank_transaction_code: nil, external_id: nil)
      account = @accounts.fetch(account_uid) { raise ArgumentError, "Unknown account uid #{account_uid}" }
      eb_currency = currency || account["currency"]
      amount_str  = format("%.2f", amount_cents.to_i.abs / 100.0)

      eid = external_id || "fake-tx-#{@transaction_counter.next!}"
      payload = {
        "transaction_id"          => eid,
        "entry_reference"         => eid,
        "credit_debit_indicator"  => direction == "credit" ? "CRDT" : "DBIT",
        "status"                  => status == "booked" ? "BOOK" : "PDNG",
        "booking_date"            => booking_date.to_s,
        "value_date"              => (value_date || booking_date).to_s,
        "transaction_date"        => (transaction_date || booking_date).to_s,
        "transaction_amount"      => { "amount" => amount_str, "currency" => eb_currency },
        "remittance_information"  => [ title, type_hint ].compact,
        "bank_transaction_code"   => bank_transaction_code ? { "code" => bank_transaction_code } : nil
      }
      if direction == "credit"
        payload["debtor"]         = counterparty_name ? { "name" => counterparty_name } : nil
        payload["debtor_account"] = counterparty_iban ? { "iban" => counterparty_iban } : nil
      else
        payload["creditor"]         = counterparty_name ? { "name" => counterparty_name } : nil
        payload["creditor_account"] = counterparty_iban ? { "iban" => counterparty_iban } : nil
      end
      @transactions[account_uid] << payload.compact
      eid
    end

    def set_balance(account_uid:, balance_cents:, balance_type: "ITAV")
      account = @accounts.fetch(account_uid) { raise ArgumentError, "Unknown account uid #{account_uid}" }
      account["balance_cents"] = balance_cents
      @balances[account_uid] = {
        "balances" => [
          {
            "balance_type"   => balance_type,
            "balance_amount" => { "amount" => format("%.2f", balance_cents / 100.0), "currency" => account["currency"] },
            "reference_date" => Date.current.to_s
          }
        ]
      }
    end

    def expire_session(session_id)
      @sessions.fetch(session_id)["status"] = "EXPIRED"
    end

    def revoke_session(session_id)
      @sessions.fetch(session_id)["status"] = "REVOKED"
    end

    def simulate_failure(method:, path:, status: 500, error: "Simulated failure", count: 1)
      key = [ method.to_sym, path ]
      count.times { @scheduled_failures[key] << { status: status, error: error } }
    end

    def simulate_429(for_endpoint:, count: 1)
      simulate_failure(method: :get, path: for_endpoint, status: 429, error: "Too Many Requests", count: count)
    end

    def simulate_500(for_endpoint:, count: 1)
      simulate_failure(method: :get, path: for_endpoint, status: 500, error: "Internal Server Error", count: count)
    end

    def reset!
      initialize
    end

    private

    def respond(data)
      EnableBanking::Result.new(success: true, status: 200, data: data, headers: {}, error: nil)
    end

    def not_found(what)
      EnableBanking::Result.new(success: false, status: 404, data: { "error" => "not_found", "message" => "Unknown #{what}" }, headers: {}, error: "Unknown #{what}")
    end

    def record_call(method, path, params)
      @recorded_calls << { method: method, path: path, params: params, at: Time.current }
    end

    def pop_failure(method, path)
      key = @scheduled_failures.keys.find { |m, p| m == method && (p == path || (p.is_a?(Regexp) && path =~ p)) }
      return nil unless key
      failure = @scheduled_failures[key].shift
      @scheduled_failures.delete(key) if @scheduled_failures[key].empty?
      EnableBanking::Result.new(success: false, status: failure[:status], data: { "error" => failure[:error] }, headers: {}, error: failure[:error])
    end

    def application_payload
      {
        "name"          => "Fake App",
        "kid"           => "kid-fake",
        "active"        => true,
        "redirect_urls" => @application_redirect_urls || [ "http://localhost:3000/admin/oauth/enable_banking/callback" ]
      }
    end

    def session_get_payload(session)
      {
        "id"           => session["id"],
        "status"       => session["status"],
        "psu_type"     => session["psu_type"],
        "access"       => session_access_payload(session),
        "accounts"     => session["account_uids"],
        "accounts_data" => session["account_uids"].map { |uid| skinny_account_summary(@accounts[uid]) },
        "closed"       => session["status"] == "CLOSED" ? Time.current.utc.iso8601 : nil
      }
    end

    def session_access_payload(session)
      {
        "balances"     => true,
        "transactions" => true,
        "valid_until"  => session["valid_until"].respond_to?(:utc) ? session["valid_until"].utc.iso8601 : session["valid_until"].to_s
      }
    end

    def skinny_account_summary(account)
      {
        "uid"      => account["uid"],
        "iban"     => account["iban"],
        "currency" => account["currency"]
      }
    end

    def create_session_payload(body)
      code = body[:code] || body["code"]
      session = @sessions.values.find { |s| s["status"] == "AUTHORIZED" && s["id"] == code } || @sessions.values.last
      if session.nil?
        sid = add_session(aspsp_name: "Fake Bank", country: "PL")
        session = @sessions[sid]
      end

      {
        "session_id"    => session["id"],
        "psu_type"      => session["psu_type"],
        "psu_id_hash"   => session["psu_id_hash"],
        "authorized"    => session["authorized_at"].respond_to?(:utc) ? session["authorized_at"].utc.iso8601 : session["authorized_at"].to_s,
        "access"        => session_access_payload(session),
        "aspsp"         => { "name" => session["aspsp_name"], "country" => session["country"] },
        "accounts"      => session["account_uids"].map { |uid| account_details_payload(@accounts[uid]) }
      }
    end

    def default_balance_payload(account)
      {
        "balances" => [
          {
            "balance_type"   => "ITAV",
            "balance_amount" => { "amount" => format("%.2f", account["balance_cents"].to_i / 100.0), "currency" => account["currency"] },
            "reference_date" => Date.current.to_s
          }
        ]
      }
    end

    def account_details_payload(account)
      alt_ids = (Array(account["alternate_ibans"]).map { |i| { "scheme_name" => "IBAN", "identification" => i } }) + [
        { "scheme_name" => "IBAN", "identification" => account["iban"] }
      ]
      {
        "uid"               => account["uid"],
        "account_id"        => { "iban" => account["iban"] },
        "all_account_ids"   => alt_ids,
        "currency"          => account["currency"],
        "name"              => account["holder_name"],
        "product"           => account["product"],
        "details"           => account["details"],
        "cash_account_type" => account["cash_account_type"],
        "usage"             => "PRIV",
        "account_servicer"  => { "bic_fi" => "FAKEPLPW" }
      }
    end

    def transactions_page(uid, params)
      txs = @transactions[uid].dup
      from = params[:date_from] && Date.parse(params[:date_from].to_s)
      to   = params[:date_to]   && Date.parse(params[:date_to].to_s)
      txs = txs.select { |t| (from.nil? || Date.parse(t["booking_date"]) >= from) && (to.nil? || Date.parse(t["booking_date"]) <= to) }

      return { "transactions" => txs, "continuation_key" => nil } if @transactions_page_size.nil?

      offset = params[:continuation_key].to_s.start_with?("offset:") ? params[:continuation_key].to_s.delete_prefix("offset:").to_i : 0
      slice = txs.slice(offset, @transactions_page_size) || []
      next_offset = offset + slice.size
      {
        "transactions"    => slice,
        "continuation_key" => (next_offset < txs.size ? "offset:#{next_offset}" : nil)
      }
    end
  end
end
