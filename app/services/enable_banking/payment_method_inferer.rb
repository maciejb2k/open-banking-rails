# frozen_string_literal: true

module EnableBanking
  # Pure function: derive a normalized payment_method string from a bank
  # transaction's raw fields. Deterministic, no LLM.
  #
  # Signal precedence (most specific first):
  #   1. type_hint  — bank's free-text remittance line (PKO: English keys
  #                   like CARD-PAYMENT; mBank: Polish keys like
  #                   "PRZELEW ZEWNĘTRZNY PRZYCHODZĄCY")
  #   2. bank_transaction_code — Berlin Group code (Revolut populates;
  #                   PKO/mBank don't)
  #   3. counterparty_name + title — heuristic last resort. Returns "card"
  #                   for any non-blank input. Logs a warning so we can
  #                   measure how often heuristics fire vs deterministic
  #                   mapping.
  #
  # Returns one of BankTransaction::PAYMENT_METHODS, or nil if signals are
  # genuinely empty (caller can backfill later).
  class PaymentMethodInferer
    # type_hint values per bank, all observed in PoC samples.
    # Keep this map narrow: fall through to nil + WARN log rather than
    # guess on unfamiliar codes — silent miscategorization is worse than
    # an explicit "unmatched" we can find in logs.
    TYPE_HINT_MAP = {
      # ── PKO (English keys in remittance_information[1]) ──
      "CARD-PAYMENT"                       => "card",
      "PAYCARD-TRANSFER"                   => "internal_transfer", # spłata karty kredytowej (PKO docs)
      "MOBILE-PAYMENT-POS-NO-CARD-TX-CODE" => "blik_pos",
      "MOBILE-PAYMENT-POS-TX-CODE"         => "blik_pos",          # variant — defensive
      "MOBILE-PAYMENT-ATM-TX-CODE"         => "blik_atm",
      "MOBILE-PAYMENT-C2C"                 => "blik_p2p",
      "MOBILE-PAYMENT-C2C-EXTERNAL"        => "blik_p2p",           # variant — defensive

      # ── mBank (Polish keys in remittance_information[1]) ──
      "PRZELEW ZEWNĘTRZNY PRZYCHODZĄCY"    => "transfer",
      "PRZELEW ZEWNĘTRZNY WYCHODZĄCY"      => "transfer",
      "BLIK P2P-PRZYCHODZĄCY"              => "blik_p2p",
      "BLIK P2P-WYCHODZĄCY"                => "blik_p2p",

      # ── Generic / observed in real sync data not yet attributed to a bank ──
      "TRANSFER"                           => "transfer"
    }.freeze

    # Berlin Group bank_transaction_code mapping. Revolut sets this;
    # PKO/mBank don't. Exact matches first, then loose regex fallbacks
    # for unobserved Berlin Group sub-types.
    BANK_CODE_EXACT = {
      "CARD_PAYMENT" => "card",
      "TOPUP"        => "topup"
    }.freeze

    # Loose regex fallbacks for unobserved bank_transaction_code values.
    # Order matters: more specific first. Crucially: cash regex matches
    # WTHD/ATM only — not "CASH-DEPT" (deposit) — so a deposit doesn't get
    # mislabeled as an ATM withdrawal. Anchors are deliberately absent so
    # nested Berlin Group codes like "PMNT-CCRD-POSP" or "PMNT-TRSF-CRTR"
    # are still recognized.
    BANK_CODE_REGEX = [
      [ /CARD/,        "card" ],
      [ /WTHD|ATM/,    "blik_atm" ],
      [ /TRSF|TRANSFER/, "transfer" ],
      [ /FEE|CHRG/,    "fee" ]
    ].freeze

    def self.call(...) = new(...).call

    def initialize(type_hint:, bank_transaction_code:, title:, counterparty_name:, direction:)
      @type_hint    = type_hint.to_s.strip
      @code         = bank_transaction_code.to_s.strip
      @title        = title.to_s
      @counterparty = counterparty_name.to_s
      @direction    = direction
    end

    def call
      from_type_hint || from_bank_code || from_heuristics
    end

    private

    # Direct mapping with telemetry. If a non-blank type_hint isn't in the
    # map, log it — that's how we discover new bank-specific codes.
    def from_type_hint
      return nil if @type_hint.blank?
      mapped = TYPE_HINT_MAP[@type_hint]
      log_unmapped("type_hint", @type_hint) if mapped.nil?
      mapped
    end

    # Berlin Group bank_transaction_code. Exact match first, then loose
    # regex fallback. Like type_hint, an unmapped non-blank value is logged.
    def from_bank_code
      return nil if @code.blank?
      upcased = @code.upcase

      return BANK_CODE_EXACT[upcased] if BANK_CODE_EXACT.key?(upcased)

      pair = BANK_CODE_REGEX.find { |re, _| re.match?(upcased) }
      return pair.last if pair

      log_unmapped("bank_transaction_code", @code)
      nil
    end

    # Last-resort heuristic. When neither hint is set but there is a
    # title or counterparty (Revolut SaaS subscriptions, edge cases), default
    # to "card". Always logs — heuristic firings should trend toward zero
    # as deterministic mappings expand.
    def from_heuristics
      return nil if @counterparty.blank? && @title.blank?
      Rails.logger.warn(
        "[PaymentMethodInferer] heuristic fallback → card " \
        "(direction=#{@direction.inspect}, " \
        "title=#{truncate(@title)}, counterparty=#{truncate(@counterparty)})"
      )
      "card"
    end

    def log_unmapped(field, value)
      Rails.logger.warn(
        "[PaymentMethodInferer] unmapped #{field}=#{value.inspect} " \
        "(direction=#{@direction.inspect}, title=#{truncate(@title)}, counterparty=#{truncate(@counterparty)})"
      )
    end

    def truncate(str, max = 80)
      s = str.to_s
      s.length > max ? "#{s[0, max]}…".inspect : s.inspect
    end
  end
end
