# frozen_string_literal: true

require "rails_helper"

RSpec.describe Banking::CounterpartyResolver do
  it "short-circuits to SELF for any payment_method in SELF_BY_METHOD regardless of IBAN or name" do
    user = create(:user)

    described_class::SELF_BY_METHOD.each do |method|
      result = described_class.call(payment_method: method, counterparty_iban: "PL99 0000 0000", counterparty_name: "Acme", user: user)
      expect(result).to eq(described_class::SELF), "method=#{method.inspect} should short-circuit to SELF"
    end
  end

  it "returns UNKNOWN when payment_method is non-self and both iban and name are blank" do
    user = create(:user)

    expect(described_class.call(payment_method: "card",     counterparty_iban: nil,  counterparty_name: nil, user: user)).to eq("unknown")
    expect(described_class.call(payment_method: "transfer", counterparty_iban: "",   counterparty_name: "",  user: user)).to eq("unknown")
    expect(described_class.call(payment_method: nil,        counterparty_iban: "  ", counterparty_name: nil, user: user)).to eq("unknown")
  end

  it "matches an own_iban after whitespace and case normalization" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    create(:bank_account, tpp_credential: tpp, iban: "PL61109010140000071219812874")

    result = described_class.call(payment_method: "transfer", counterparty_iban: "pl61 1090 1014 0000 0712 1981 2874", counterparty_name: nil, user: user)
    expect(result).to eq("self")
  end

  it "returns EXTERNAL when iban does not match any own_iban and name is blank" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    create(:bank_account, tpp_credential: tpp, iban: "PL61109010140000071219812874")

    result = described_class.call(payment_method: "transfer", counterparty_iban: "PL99000000000000000000000000", counterparty_name: nil, user: user)
    expect(result).to eq("external")
  end

  it "matches an own_holder_name after strip and upcase" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    create(:bank_account, tpp_credential: tpp, name: "JAN KOWALSKI")

    result = described_class.call(payment_method: "transfer", counterparty_iban: nil, counterparty_name: "  jan kowalski  ", user: user)
    expect(result).to eq("self")
  end

  it "prefers IBAN over name when both are present (precedence proof)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    create(:bank_account, tpp_credential: tpp, iban: "PL61109010140000071219812874", name: "Anna Nowak")

    result = described_class.call(payment_method: "transfer", counterparty_iban: "PL61109010140000071219812874", counterparty_name: "Random Vendor", user: user)
    expect(result).to eq("self")
  end

  it "falls back to name match when iban does not match and name does" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    create(:bank_account, tpp_credential: tpp, iban: "PL61109010140000071219812874", name: "JAN KOWALSKI")

    result = described_class.call(payment_method: "transfer", counterparty_iban: "PL99000000000000000000000000", counterparty_name: "Jan Kowalski", user: user)
    expect(result).to eq("self")
  end

  it "short-circuits via SELF_BY_METHOD without calling user.own_ibans" do
    user = create(:user)
    expect(user).not_to receive(:own_ibans)
    expect(user).not_to receive(:own_holder_names)

    result = described_class.call(payment_method: "internal_transfer", counterparty_iban: "PL61109010140000071219812874", counterparty_name: nil, user: user)
    expect(result).to eq("self")
  end

  it "fetches from a Hash with string keys via .for" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    create(:bank_account, tpp_credential: tpp, iban: "PL61109010140000071219812874")
    payload = { "payment_method" => "transfer", "counterparty_iban" => "PL61109010140000071219812874", "counterparty_name" => nil }

    expect(described_class.for(payload, user: user)).to eq("self")
  end

  it "fetches from a BankTransaction record via .for using respond_to?/public_send" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp, iban: "PL61109010140000071219812874")
    tx = create(:bank_transaction, bank_account: account, payment_method: "transfer", counterparty_iban: "PL61109010140000071219812874", counterparty_name: nil)

    expect(described_class.for(tx, user: user)).to eq("self")
  end
end
