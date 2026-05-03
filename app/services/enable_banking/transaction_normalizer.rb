# frozen_string_literal: true

module EnableBanking
  # Per-bank quirks:
  #   - Revolut: transaction_id is always null → fall back to entry_reference
  #   - mBank:   counterparty IBAN arrives as BBAN under "other" - prepend PL
  #   - PKO:     card payments have null creditor; title is remittance_information[0]
  class TransactionNormalizer
    DIRECTION_MAP = { "CRDT" => "credit", "DBIT" => "debit" }.freeze
    STATUS_MAP    = { "BOOK" => "booked", "PDNG" => "pending" }.freeze

    def self.call(payload, bank_account:, fetched_at: Time.current)
      new(payload, bank_account: bank_account, fetched_at: fetched_at).call
    end

    def initialize(payload, bank_account:, fetched_at:)
      @payload = payload
      @bank_account = bank_account
      @fetched_at = fetched_at
    end

    def call
      direction = DIRECTION_MAP[@payload["credit_debit_indicator"]]
      raise ArgumentError, "Unknown credit_debit_indicator: #{@payload['credit_debit_indicator'].inspect}" if direction.nil?

      counterparty_node = direction == "credit" ? @payload["debtor"] : @payload["creditor"]
      counterparty_account_node = direction == "credit" ? @payload["debtor_account"] : @payload["creditor_account"]

      currency = @payload.dig("transaction_amount", "currency")
      amount_cents = to_cents(@payload.dig("transaction_amount", "amount"), currency)

      title             = Array(@payload["remittance_information"])[0]
      type_hint         = Array(@payload["remittance_information"])[1]
      counterparty_name = counterparty_node&.dig("name")
      bank_code         = @payload.dig("bank_transaction_code", "code")

      payment_method = PaymentMethodInferer.call(
        type_hint: type_hint,
        bank_transaction_code: bank_code,
        title: title,
        counterparty_name: counterparty_name,
        direction: direction
      )

      {
        bank_account_id: @bank_account.id,
        external_id: extract_external_id,
        booking_date: parse_date(@payload["booking_date"]),
        value_date: parse_date(@payload["value_date"]),
        transaction_date: parse_date(@payload["transaction_date"]),
        amount_cents: amount_cents,
        currency: currency,
        direction: direction,
        status: STATUS_MAP.fetch(@payload["status"], "booked"),
        title: title,
        type_hint: type_hint,
        counterparty_name: counterparty_name,
        counterparty_iban: extract_iban(counterparty_account_node),
        bank_transaction_code: bank_code,
        payment_method: payment_method,
        raw_payload: @payload.to_json,
        fetched_at: @fetched_at
      }
    end

    private

    def extract_external_id
      id = @payload["transaction_id"].presence || @payload["entry_reference"].presence
      raise ArgumentError, "Transaction has neither transaction_id nor entry_reference" if id.nil?
      id
    end

    def extract_iban(account_node)
      return nil if account_node.blank?
      return account_node["iban"] if account_node["iban"].present?

      other = account_node["other"]
      return nil unless other.is_a?(Hash)

      case other["scheme_name"]
      when "IBAN" then other["identification"]
      when "BBAN" then bban_to_iban(other["identification"])
      end
    end

    # PL only - other countries' BBANs need a different transform.
    def bban_to_iban(bban)
      return nil if bban.blank?
      "PL#{bban}"
    end

    def parse_date(value)
      return nil if value.blank?
      Date.parse(value)
    rescue ArgumentError
      nil
    end

    # Some banks signal debits with a leading minus, others rely on
    # credit_debit_indicator - normalize to magnitude and let `direction`
    # carry the sign, so signed_amount is the single source of truth.
    def to_cents(amount_string, currency)
      raise ArgumentError, "Missing transaction_amount.amount" if amount_string.blank?
      raise ArgumentError, "Missing transaction_amount.currency" if currency.blank?
      Money.from_amount(BigDecimal(amount_string.to_s).abs, currency).cents
    end
  end
end
