# frozen_string_literal: true

module EnableBanking
  # Signal precedence (most specific first): type_hint → bank_transaction_code
  # → heuristic fallback. Returns one of BankTransaction::PAYMENT_METHODS or
  # nil. Keep TYPE_HINT_MAP narrow - fall through to nil + WARN rather than
  # guess on unfamiliar codes; silent miscategorization is worse than an
  # explicit "unmatched" we can find in logs.
  class PaymentMethodInferer
    TYPE_HINT_MAP = {
      # ── PKO (English keys in remittance_information[1]) ──
      "CARD-PAYMENT"                       => "card",
      "CARD-PAYMENT-RETURN"                => "card",              # refund; direction=credit carries the sign
      "CARD-ATM"                           => "blik_atm",          # ATM withdrawal (channel agnostic - shares fallback path)
      "PAYCARD-TRANSFER"                   => "internal_transfer", # spłata karty kredytowej (PKO docs)
      "MOBILE-PAYMENT-POS-NO-CARD-TX-CODE" => "blik_pos",
      "MOBILE-PAYMENT-POS-TX-CODE"         => "blik_pos",          # variant - defensive
      "MOBILE-PAYMENT-POS-RETURN"          => "blik_pos",          # BLIK POS refund
      "MOBILE-PAYMENT-ATM-TX-CODE"         => "blik_atm",
      "MOBILE-PAYMENT-C2C"                 => "blik_p2p",
      "MOBILE-PAYMENT-C2C-EXTERNAL"        => "blik_p2p",          # variant - defensive
      "TRANSFER-IN"                        => "transfer",          # PKO incoming wire (e.g. salary)
      "TRANSFER-EXPRESS-ELIXIR-IN"         => "transfer",          # PKO Express Elixir incoming

      # ── mBank (Polish keys in remittance_information[1]) ──
      "PRZELEW ZEWNĘTRZNY PRZYCHODZĄCY"    => "transfer",
      "PRZELEW ZEWNĘTRZNY WYCHODZĄCY"      => "transfer",
      "PRZELEW WEWNĘTRZNY PRZYCHODZĄCY"    => "transfer",          # mBank → mBank (different person)
      "PRZELEW WEWNĘTRZNY WYCHODZĄCY"      => "transfer",
      "PRZELEW WŁASNY"                     => "internal_transfer", # mBank → user's other bank account
      "BLIK P2P-PRZYCHODZĄCY"              => "blik_p2p",
      "BLIK P2P-WYCHODZĄCY"                => "blik_p2p",
      "BLIK ZAKUP E-COMMERCE"              => "blik_pos",          # BLIK online purchase (Allegro etc.)

      # ── Generic / observed in real sync data not yet attributed to a bank ──
      "TRANSFER"                           => "transfer"
    }.freeze

    BANK_CODE_EXACT = {
      "CARD_PAYMENT" => "card",
      "TOPUP"        => "topup"
    }.freeze

    # Order matters: more specific first. Cash regex matches WTHD/ATM only,
    # not "CASH-DEPT" (deposit), so a deposit isn't mislabeled as ATM.
    # Anchors are deliberately absent so nested codes like "PMNT-CCRD-POSP"
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

    def from_type_hint
      return nil if @type_hint.blank?
      mapped = TYPE_HINT_MAP[@type_hint]
      log_unmapped("type_hint", @type_hint) if mapped.nil?
      mapped
    end

    def from_bank_code
      return nil if @code.blank?
      upcased = @code.upcase

      return BANK_CODE_EXACT[upcased] if BANK_CODE_EXACT.key?(upcased)

      pair = BANK_CODE_REGEX.find { |re, _| re.match?(upcased) }
      return pair.last if pair

      log_unmapped("bank_transaction_code", @code)
      nil
    end

    # Always logs - heuristic firings should trend toward zero as
    # deterministic mappings expand.
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
