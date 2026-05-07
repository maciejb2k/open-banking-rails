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
end
