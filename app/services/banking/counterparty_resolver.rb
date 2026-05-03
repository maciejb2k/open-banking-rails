# frozen_string_literal: true

module Banking
  # Persisted at sync time, not enrichment time, so analytics + LedgerEntry view
  # read a plain enum. Signal priority (first hit wins): payment_method →
  # IBAN match → name match → external (when either field set) → unknown.
  # Name-based match has false positives on common names - acceptable since
  # per-transaction category override always wins.
  module CounterpartyResolver
    SELF_BY_METHOD = %w[
      internal_transfer
      topup
      cash_atm_topup
      cash_deposit
      cash_fx_conversion
      cash_adjustment
    ].freeze

    SELF     = "self"
    EXTERNAL = "external"
    UNKNOWN  = "unknown"

    def self.call(payment_method:, counterparty_iban:, counterparty_name:, user:)
      return SELF if SELF_BY_METHOD.include?(payment_method.to_s)

      iban = normalize_iban(counterparty_iban)
      name = normalize_name(counterparty_name)

      return UNKNOWN if iban.nil? && name.nil?

      return SELF if iban && user.own_ibans.include?(iban)
      return SELF if name && user.own_holder_names.include?(name)

      EXTERNAL
    end

    def self.for(transaction, user:)
      call(
        payment_method:    fetch(transaction, :payment_method),
        counterparty_iban: fetch(transaction, :counterparty_iban),
        counterparty_name: fetch(transaction, :counterparty_name),
        user:              user
      )
    end

    def self.fetch(source, key)
      if source.is_a?(Hash)
        source[key] || source[key.to_s]
      else
        source.respond_to?(key) ? source.public_send(key) : nil
      end
    end

    def self.normalize_iban(value)
      return nil if value.blank?
      value.to_s.gsub(/\s+/, "").upcase
    end

    def self.normalize_name(value)
      return nil if value.blank?
      value.to_s.strip.upcase
    end
  end
end
