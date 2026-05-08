# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::PaymentMethodInferer do
  it "maps a known type_hint directly to its canonical payment method" do
    result = described_class.call(type_hint: "CARD-PAYMENT", bank_transaction_code: nil, title: "Coffee", counterparty_name: "Cafe", direction: "debit")
    expect(result).to eq("card")

    result_blik = described_class.call(type_hint: "MOBILE-PAYMENT-POS-NO-CARD-TX-CODE", bank_transaction_code: nil, title: nil, counterparty_name: nil, direction: "debit")
    expect(result_blik).to eq("blik_pos")

    result_internal = described_class.call(type_hint: "PAYCARD-TRANSFER", bank_transaction_code: nil, title: nil, counterparty_name: nil, direction: "debit")
    expect(result_internal).to eq("internal_transfer")
  end

  it "maps mBank Polish type_hint variants to the right canonical kind" do
    result_in  = described_class.call(type_hint: "PRZELEW ZEWNĘTRZNY PRZYCHODZĄCY", bank_transaction_code: nil, title: nil, counterparty_name: nil, direction: "credit")
    result_out = described_class.call(type_hint: "PRZELEW ZEWNĘTRZNY WYCHODZĄCY",   bank_transaction_code: nil, title: nil, counterparty_name: nil, direction: "debit")
    result_p2p = described_class.call(type_hint: "BLIK P2P-WYCHODZĄCY",             bank_transaction_code: nil, title: nil, counterparty_name: nil, direction: "debit")

    expect(result_in).to eq("transfer")
    expect(result_out).to eq("transfer")
    expect(result_p2p).to eq("blik_p2p")
  end

  it "maps mBank PRZELEW WŁASNY to internal_transfer so own-account moves never count as spend" do
    result = described_class.call(type_hint: "PRZELEW WŁASNY", bank_transaction_code: nil, title: "PRZELEW ŚRODKÓW", counterparty_name: "MACIEJ BIEL", direction: "debit")
    expect(result).to eq("internal_transfer")
  end

  it "maps mBank PRZELEW WEWNĘTRZNY (same-bank, different person) variants to transfer" do
    result_out = described_class.call(type_hint: "PRZELEW WEWNĘTRZNY WYCHODZĄCY", bank_transaction_code: nil, title: nil, counterparty_name: nil, direction: "debit")
    result_in  = described_class.call(type_hint: "PRZELEW WEWNĘTRZNY PRZYCHODZĄCY", bank_transaction_code: nil, title: nil, counterparty_name: nil, direction: "credit")

    expect(result_out).to eq("transfer")
    expect(result_in).to eq("transfer")
  end

  it "maps mBank BLIK ZAKUP E-COMMERCE to blik_pos" do
    result = described_class.call(type_hint: "BLIK ZAKUP E-COMMERCE", bank_transaction_code: nil, title: "ALLEGRO.PL", counterparty_name: nil, direction: "debit")
    expect(result).to eq("blik_pos")
  end

  it "maps PKO TRANSFER-IN and TRANSFER-EXPRESS-ELIXIR-IN to transfer (covers salary and Express Elixir incoming)" do
    elixir = described_class.call(type_hint: "TRANSFER-EXPRESS-ELIXIR-IN", bank_transaction_code: nil, title: "MACIEJ BIEL WYSLANO Z REVOLUT", counterparty_name: nil, direction: "credit")
    salary = described_class.call(type_hint: "TRANSFER-IN", bank_transaction_code: nil, title: "RACHUNEK DO UMOWY ZLECENIA", counterparty_name: nil, direction: "credit")

    expect(elixir).to eq("transfer")
    expect(salary).to eq("transfer")
  end

  it "maps PKO CARD-ATM to blik_atm so ATM withdrawals share the cash-out fallback path regardless of channel" do
    result = described_class.call(type_hint: "CARD-ATM", bank_transaction_code: nil, title: "RZESZOWUL. REJTANA 53 BPL", counterparty_name: nil, direction: "debit")
    expect(result).to eq("blik_atm")
  end

  it "maps PKO refund variants to their original channel (direction=credit carries refund-ness)" do
    card_return = described_class.call(type_hint: "CARD-PAYMENT-RETURN", bank_transaction_code: nil, title: nil, counterparty_name: nil, direction: "credit")
    blik_return = described_class.call(type_hint: "MOBILE-PAYMENT-POS-RETURN", bank_transaction_code: nil, title: nil, counterparty_name: nil, direction: "credit")

    expect(card_return).to eq("card")
    expect(blik_return).to eq("blik_pos")
  end

  it "logs and returns nil for an unmapped type_hint" do
    expect(Rails.logger).to receive(:warn).with(/unmapped type_hint=\"UNKNOWN-CODE\"/)

    result = described_class.call(type_hint: "UNKNOWN-CODE", bank_transaction_code: nil, title: nil, counterparty_name: nil, direction: "debit")
    expect(result).to be_nil
  end

  it "falls back to bank_transaction_code exact match when type_hint is blank" do
    result = described_class.call(type_hint: nil, bank_transaction_code: "CARD_PAYMENT", title: nil, counterparty_name: nil, direction: "debit")
    expect(result).to eq("card")

    topup = described_class.call(type_hint: "", bank_transaction_code: "TOPUP", title: nil, counterparty_name: nil, direction: "debit")
    expect(topup).to eq("topup")
  end

  it "falls back to bank_transaction_code regex match for nested codes containing CARD" do
    result = described_class.call(type_hint: nil, bank_transaction_code: "PMNT-CARD-POSP", title: nil, counterparty_name: nil, direction: "debit")
    expect(result).to eq("card")
  end

  it "matches CWDL-WTHD as blik_atm and refuses to label CASH-DEPT as blik_atm" do
    atm = described_class.call(type_hint: nil, bank_transaction_code: "CWDL-WTHD", title: nil, counterparty_name: nil, direction: "debit")
    expect(atm).to eq("blik_atm")

    allow(Rails.logger).to receive(:warn)
    deposit = described_class.call(type_hint: nil, bank_transaction_code: "CASH-DEPT", title: nil, counterparty_name: nil, direction: "credit")
    expect(deposit).not_to eq("blik_atm")
    expect(deposit).to be_nil
  end

  it "logs a warning and falls through to nil for an unrecognized bank_transaction_code" do
    expect(Rails.logger).to receive(:warn).with(/unmapped bank_transaction_code=\"PMNT-RCDT-DMCT\"/)

    result = described_class.call(type_hint: nil, bank_transaction_code: "PMNT-RCDT-DMCT", title: nil, counterparty_name: nil, direction: "debit")
    expect(result).to be_nil
  end

  it "applies the heuristic 'card' fallback only when title or counterparty is present" do
    expect(Rails.logger).to receive(:warn).with(/heuristic fallback/)

    result = described_class.call(type_hint: nil, bank_transaction_code: nil, title: "Some shop", counterparty_name: "ACME LTD", direction: "debit")
    expect(result).to eq("card")
  end

  it "returns nil without logging when every signal is blank" do
    expect(Rails.logger).not_to receive(:warn)

    result = described_class.call(type_hint: nil, bank_transaction_code: nil, title: nil, counterparty_name: nil, direction: "debit")
    expect(result).to be_nil
  end

  it "honors signal precedence: a resolvable type_hint short-circuits the bank_transaction_code path" do
    result = described_class.call(type_hint: "CARD-PAYMENT", bank_transaction_code: "TRSF", title: nil, counterparty_name: nil, direction: "debit")
    expect(result).to eq("card")
  end
end
