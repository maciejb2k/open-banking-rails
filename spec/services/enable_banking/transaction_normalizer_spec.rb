# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::TransactionNormalizer do
  def pko_credit_payload(overrides = {})
    {
      "transaction_id" => "pko-tx-001",
      "credit_debit_indicator" => "CRDT",
      "transaction_amount" => { "amount" => "123.45", "currency" => "PLN" },
      "booking_date" => "2026-05-03",
      "value_date"   => "2026-05-04",
      "transaction_date" => "2026-05-03",
      "status" => "BOOK",
      "remittance_information" => [ "Salary", "PRZELEW ZEWNĘTRZNY PRZYCHODZĄCY" ],
      "debtor" => { "name" => "Acme Sp. z o.o." },
      "debtor_account" => { "iban" => "PL61109010140000071219812874" },
      "bank_transaction_code" => { "code" => "PMNT-RCDT-XBCT" }
    }.merge(overrides)
  end

  it "normalizes a PKO credit transfer payload into the persistence-ready Hash" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp, currency: "PLN")

    result = described_class.call(pko_credit_payload, bank_account: account)

    expect(result).to include(
      bank_account_id: account.id,
      external_id: "pko-tx-001",
      direction: "credit",
      amount_cents: 12345,
      currency: "PLN",
      title: "Salary",
      type_hint: "PRZELEW ZEWNĘTRZNY PRZYCHODZĄCY",
      counterparty_name: "Acme Sp. z o.o.",
      counterparty_iban: "PL61109010140000071219812874",
      bank_transaction_code: "PMNT-RCDT-XBCT",
      payment_method: "transfer",
      status: "booked"
    )
  end

  it "falls back to entry_reference for external_id when transaction_id is nil (Revolut)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)

    payload = pko_credit_payload("transaction_id" => nil, "entry_reference" => "abc-123")
    result = described_class.call(payload, bank_account: account)

    expect(result[:external_id]).to eq("abc-123")
  end

  it "raises ArgumentError when both transaction_id and entry_reference are absent" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    payload = pko_credit_payload("transaction_id" => nil, "entry_reference" => nil)

    expect {
      described_class.call(payload, bank_account: account)
    }.to raise_error(ArgumentError, /transaction_id nor entry_reference/)
  end

  it "transforms a BBAN counterparty under debtor_account.other into a PL-prefixed IBAN (mBank)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    payload = pko_credit_payload(
      "debtor_account" => { "other" => { "scheme_name" => "BBAN", "identification" => "60114020040000310205800001" } }
    )

    result = described_class.call(payload, bank_account: account)
    expect(result[:counterparty_iban]).to eq("PL60114020040000310205800001")
  end

  it "passes through other.identification verbatim when scheme_name is IBAN" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    payload = pko_credit_payload(
      "debtor_account" => { "other" => { "scheme_name" => "IBAN", "identification" => "DE89370400440532013000" } }
    )

    result = described_class.call(payload, bank_account: account)
    expect(result[:counterparty_iban]).to eq("DE89370400440532013000")
  end

  it "yields nil counterparty_iban and counterparty_name when the account node is missing (PKO null creditor)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    payload = pko_credit_payload("debtor" => nil, "debtor_account" => nil)

    result = described_class.call(payload, bank_account: account)

    expect(result[:counterparty_iban]).to be_nil
    expect(result[:counterparty_name]).to be_nil
  end

  it "switches counterparty_node to creditor when credit_debit_indicator is DBIT" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    payload = pko_credit_payload(
      "credit_debit_indicator" => "DBIT",
      "debtor" => nil, "debtor_account" => nil,
      "creditor" => { "name" => "Coffee Shop" },
      "creditor_account" => { "iban" => "PL00000000000000000000000001" }
    )

    result = described_class.call(payload, bank_account: account)
    expect(result[:direction]).to eq("debit")
    expect(result[:counterparty_name]).to eq("Coffee Shop")
    expect(result[:counterparty_iban]).to eq("PL00000000000000000000000001")
  end

  it "raises ArgumentError when credit_debit_indicator is unknown" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    payload = pko_credit_payload("credit_debit_indicator" => "FOO")

    expect {
      described_class.call(payload, bank_account: account)
    }.to raise_error(ArgumentError, /Unknown credit_debit_indicator/)
  end

  it "maps status PDNG to pending and falls back to booked for unrecognized values" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)

    pending = described_class.call(pko_credit_payload("status" => "PDNG"), bank_account: account)
    fallback = described_class.call(pko_credit_payload("status" => "INFO"), bank_account: account)

    expect(pending[:status]).to eq("pending")
    expect(fallback[:status]).to eq("booked")
  end

  it "stores amount_cents as the absolute magnitude regardless of a leading minus sign" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    payload = pko_credit_payload("transaction_amount" => { "amount" => "-123.45", "currency" => "PLN" })

    result = described_class.call(payload, bank_account: account)
    expect(result[:amount_cents]).to eq(12345)
  end

  it "raises ArgumentError when transaction_amount.amount or currency are blank" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    blank_amount = pko_credit_payload("transaction_amount" => { "amount" => "", "currency" => "PLN" })
    blank_currency = pko_credit_payload("transaction_amount" => { "amount" => "1.00", "currency" => "" })

    expect { described_class.call(blank_amount,   bank_account: account) }.to raise_error(ArgumentError, /Missing transaction_amount.amount/)
    expect { described_class.call(blank_currency, bank_account: account) }.to raise_error(ArgumentError, /Missing transaction_amount.currency/)
  end

  it "rescues malformed dates per field, returning nil without aborting the whole normalization" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    payload = pko_credit_payload("booking_date" => "not-a-date", "value_date" => "2026-05-04")

    result = described_class.call(payload, bank_account: account)

    expect(result[:booking_date]).to be_nil
    expect(result[:value_date]).to eq(Date.new(2026, 5, 4))
  end

  it "round-trips raw_payload as JSON and uses the supplied fetched_at" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    payload = pko_credit_payload
    at = Time.utc(2026, 5, 7, 12, 0, 0)

    result = described_class.call(payload, bank_account: account, fetched_at: at)

    expect(JSON.parse(result[:raw_payload])).to eq(payload)
    expect(result[:fetched_at]).to eq(at)
  end

  it "normalizes every payload shape observed in the PoC dataset to a canonical payment_method without warnings" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)

    cases = [
      { bank: "pko", payload: { "transaction_id" => "p1", "credit_debit_indicator" => "DBIT", "transaction_amount" => { "amount" => "44.05", "currency" => "PLN" }, "booking_date" => "2026-04-26", "status" => "BOOK", "remittance_information" => [ "RZESZOWJMP S.A. BIEDRONKA 4957PL", "CARD-PAYMENT" ] }, expected_pm: "card" },
      { bank: "pko", payload: { "transaction_id" => "p2", "credit_debit_indicator" => "CRDT", "transaction_amount" => { "amount" => "208.63", "currency" => "PLN" }, "booking_date" => "2026-04-20", "status" => "BOOK", "remittance_information" => [ "01007956474609054353500004250188", "CARD-PAYMENT-RETURN" ] }, expected_pm: "card" },
      { bank: "pko", payload: { "transaction_id" => "p3", "credit_debit_indicator" => "DBIT", "transaction_amount" => { "amount" => "700.00", "currency" => "PLN" }, "booking_date" => "2026-04-20", "status" => "BOOK", "remittance_information" => [ "RZESZOWUL. REJTANA 53 BPL", "CARD-ATM" ] }, expected_pm: "blik_atm" },
      { bank: "pko", payload: { "transaction_id" => "p4", "credit_debit_indicator" => "DBIT", "transaction_amount" => { "amount" => "5.00", "currency" => "PLN" }, "booking_date" => "2026-04-26", "status" => "BOOK", "remittance_information" => [ "", "MOBILE-PAYMENT-POS-NO-CARD-TX-CODE" ] }, expected_pm: "blik_pos" },
      { bank: "pko", payload: { "transaction_id" => "p5", "credit_debit_indicator" => "CRDT", "transaction_amount" => { "amount" => "1.00", "currency" => "PLN" }, "booking_date" => "2026-04-26", "status" => "BOOK", "remittance_information" => [ "", "MOBILE-PAYMENT-POS-RETURN" ] }, expected_pm: "blik_pos" },
      { bank: "pko", payload: { "transaction_id" => "p6", "credit_debit_indicator" => "CRDT", "transaction_amount" => { "amount" => "7000.00", "currency" => "PLN" }, "booking_date" => "2026-03-15", "status" => "BOOK", "remittance_information" => [ "RACHUNEK DO UMOWY ZLECENIA NR 1/03/2026", "TRANSFER-IN" ] }, expected_pm: "transfer" },
      { bank: "pko", payload: { "transaction_id" => "p7", "credit_debit_indicator" => "CRDT", "transaction_amount" => { "amount" => "43.05", "currency" => "PLN" }, "booking_date" => "2026-04-10", "status" => "BOOK", "remittance_information" => [ "MACIEJ BIEL WYSLANO Z REVOLUT", "TRANSFER-EXPRESS-ELIXIR-IN" ] }, expected_pm: "transfer" },
      { bank: "mbank", payload: { "transaction_id" => "m1", "credit_debit_indicator" => "DBIT", "transaction_amount" => { "amount" => "2.61", "currency" => "PLN" }, "booking_date" => "2025-12-09", "status" => "BOOK", "remittance_information" => [ "PRZELEW ŚRODKÓW", "PRZELEW WŁASNY" ], "creditor" => { "name" => "MACIEJ BIEL" }, "creditor_account" => { "other" => { "scheme_name" => "BBAN", "identification" => "08114020040000350275622273" } } }, expected_pm: "internal_transfer" },
      { bank: "mbank", payload: { "transaction_id" => "m2", "credit_debit_indicator" => "DBIT", "transaction_amount" => { "amount" => "299.00", "currency" => "PLN" }, "booking_date" => "2025-11-03", "status" => "BOOK", "remittance_information" => [ "/OPT/X/////TR-2KN4-K47AVCX", "PRZELEW WEWNĘTRZNY WYCHODZĄCY" ] }, expected_pm: "transfer" },
      { bank: "mbank", payload: { "transaction_id" => "m3", "credit_debit_indicator" => "CRDT", "transaction_amount" => { "amount" => "300.01", "currency" => "PLN" }, "booking_date" => "2025-07-22", "status" => "BOOK", "remittance_information" => [ "NA ŻYCIE JAK W MADRYCIE", "PRZELEW WEWNĘTRZNY PRZYCHODZĄCY" ] }, expected_pm: "transfer" },
      { bank: "mbank", payload: { "transaction_id" => "m4", "credit_debit_indicator" => "DBIT", "transaction_amount" => { "amount" => "199.90", "currency" => "PLN" }, "booking_date" => "2026-03-12", "status" => "BOOK", "remittance_information" => [ "ALLEGRO.PL", "BLIK ZAKUP E-COMMERCE" ] }, expected_pm: "blik_pos" },
      { bank: "mbank", payload: { "transaction_id" => "m5", "credit_debit_indicator" => "DBIT", "transaction_amount" => { "amount" => "16.39", "currency" => "PLN" }, "booking_date" => "2026-01-06", "status" => "BOOK", "remittance_information" => [ "PRZELEW ŚRODKÓW", "BLIK P2P-WYCHODZĄCY" ] }, expected_pm: "blik_p2p" },
      { bank: "revolut", payload: { "transaction_id" => nil, "entry_reference" => "69e73c30-547d-a139-be41-c59809b6679e", "credit_debit_indicator" => "DBIT", "transaction_amount" => { "amount" => "20.00", "currency" => "PLN" }, "booking_date" => "2026-04-15", "status" => "BOOK", "remittance_information" => [ "Claude.ai Subscription" ], "bank_transaction_code" => { "code" => "CARD_PAYMENT" }, "creditor" => { "name" => "Claude.ai Subscription" } }, expected_pm: "card" },
      { bank: "revolut", payload: { "transaction_id" => nil, "entry_reference" => "abc-3901", "credit_debit_indicator" => "CRDT", "transaction_amount" => { "amount" => "100.00", "currency" => "PLN" }, "booking_date" => "2026-04-12", "status" => "BOOK", "remittance_information" => [ "Google Pay Top-Up by *6181" ], "bank_transaction_code" => { "code" => "TOPUP" } }, expected_pm: "topup" }
    ]

    allow(Rails.logger).to receive(:warn)

    aggregate_failures do
      cases.each do |c|
        result = described_class.call(c[:payload], bank_account: account)
        expect(result[:payment_method]).to eq(c[:expected_pm]),
          "expected #{c[:bank]} #{c[:payload]['remittance_information']&.last.inspect} to map to #{c[:expected_pm].inspect}, got #{result[:payment_method].inspect}"
        expect(BankTransaction::PAYMENT_METHODS).to include(result[:payment_method])
      end
    end

    expect(Rails.logger).not_to have_received(:warn).with(/PaymentMethodInferer.*(unmapped|heuristic)/)
  end
end
