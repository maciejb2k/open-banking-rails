# frozen_string_literal: true

module EnableBanking
  # Pure function: derive a normalized payment_method string from a bank
  # transaction's raw fields. Deterministic, no LLM.
  #
  # Signal precedence (most specific first):
  #   1. type_hint  — mBank's free-text remittance line (CARD-PAYMENT,
  #                   MOBILE-PAYMENT-POS-NO-CARD-TX-CODE, MOBILE-PAYMENT-C2C, etc.)
  #   2. bank_transaction_code — Berlin Group code (Revolut populates;
  #                   PKO/mBank usually don't)
  #   3. counterparty_name + title — heuristic last resort for SaaS / recurring
  #                   card charges that arrive with neither hint set
  #
  # Returns one of BankTransaction::PAYMENT_METHODS, or nil if the signal
  # is genuinely ambiguous (caller can backfill later).
  class PaymentMethodInferer
    # mBank type_hint values seen in the wild. Keep this map narrow — fall
    # through to nil rather than guess on unfamiliar codes.
    TYPE_HINT_MAP = {
      "CARD-PAYMENT"                          => "card",
      "PAYCARD-TRANSFER"                      => "card_authorization",
      "MOBILE-PAYMENT-POS-NO-CARD-TX-CODE"    => "blik_pos",
      "MOBILE-PAYMENT-POS-TX-CODE"            => "blik_pos",
      "MOBILE-PAYMENT-ATM-TX-CODE"            => "blik_atm",
      "MOBILE-PAYMENT-C2C"                    => "blik_p2p",
      "MOBILE-PAYMENT-C2C-EXTERNAL"           => "blik_p2p",
      "TRANSFER"                              => "transfer"
    }.freeze

    def self.call(...) = new(...).call

    def initialize(type_hint:, bank_transaction_code:, title:, counterparty_name:, direction:)
      @type_hint = type_hint.to_s.strip
      @code      = bank_transaction_code.to_s.strip
      @title     = title.to_s
      @counterparty = counterparty_name.to_s
      @direction = direction
    end

    def call
      from_type_hint || from_bank_code || from_heuristics
    end

    private

    def from_type_hint
      TYPE_HINT_MAP[@type_hint]
    end

    # Berlin Group bank_transaction_code is usually "PMNT-..." sub-types.
    # Revolut sets it; mBank/PKO almost never. Keep mapping conservative.
    def from_bank_code
      return nil if @code.blank?
      case @code.upcase
      when /CARD/ then "card"
      when /CASH/ then "blik_atm"
      when /TRSF|TRANSFER/ then "transfer"
      when /FEES?|CHRG/ then "fee"
      end
    end

    # When neither hint is present, the transaction is typically a
    # foreign card charge / SaaS subscription posted by the issuer
    # (Revolut style: title and counterparty_name carry the merchant).
    # We classify those as card unless the counterparty looks like a
    # person (private transfer with empty type_hint — rare, but possible).
    def from_heuristics
      return nil if @counterparty.blank? && @title.blank?
      "card"
    end
  end
end
