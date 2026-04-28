# frozen_string_literal: true

module EnableBanking
  # Maps a single Enable Banking transaction payload onto BankTransaction
  # column attributes. Pure function, no DB writes — caller decides how to
  # persist (single insert, upsert, bulk).
  #
  # Centralizes the per-bank quirks documented in the PoC:
  #   - Revolut: transaction_id is always null → fall back to entry_reference
  #   - mBank: counterparty IBAN comes as BBAN under {"other": {scheme_name: "BBAN"}}
  #            → convert "PL" + bban (26 digits → 28-char IBAN)
  #   - PKO: card payments have null creditor — title comes from remittance_information[0]
  #
  # See PoC docs/banks/comparison.md for the full field-by-field matrix.
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

      {
        bank_account_id: @bank_account.id,
        external_id: extract_external_id,
        booking_date: parse_date(@payload["booking_date"]),
        value_date: parse_date(@payload["value_date"]),
        transaction_date: parse_date(@payload["transaction_date"]),
        amount: @payload.dig("transaction_amount", "amount"),
        currency: @payload.dig("transaction_amount", "currency"),
        direction: direction,
        status: STATUS_MAP.fetch(@payload["status"], "booked"),
        title: Array(@payload["remittance_information"])[0],
        type_hint: Array(@payload["remittance_information"])[1],
        counterparty_name: counterparty_node&.dig("name"),
        counterparty_iban: extract_iban(counterparty_account_node),
        bank_transaction_code: @payload.dig("bank_transaction_code", "code"),
        raw_payload: @payload.to_json,
        fetched_at: @fetched_at
      }
    end

    private

    # Revolut: transaction_id is always null, fall back to entry_reference (UUID-like).
    # PKO/mBank: transaction_id is base64(entry_reference) — both are stable, prefer
    # transaction_id for consistency where available.
    def extract_external_id
      id = @payload["transaction_id"].presence || @payload["entry_reference"].presence
      raise ArgumentError, "Transaction has neither transaction_id nor entry_reference" if id.nil?
      id
    end

    # Counterparty IBAN extraction. mBank quirk: when iban is null, scheme_name "BBAN"
    # under "other" carries the 26-digit account number — prepend "PL" for a valid IBAN.
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

    # PL BBAN (26 digits) → IBAN by prepending the country code.
    # Other countries' BBANs would need a different transform; we only see PL banks today.
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
  end
end
