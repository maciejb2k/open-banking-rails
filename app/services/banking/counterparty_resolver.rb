# frozen_string_literal: true

module Banking
  # Resolves whether the other side of a ledger entry is the user themselves
  # ("self") or someone else ("external"), based on payment method and
  # counterparty identity (IBAN, then name). Returns "unknown" when neither
  # field gives a verdict.
  #
  # Why this lives at sync time, not enrichment time:
  # "is this me-to-me?" is a fact about the row, on par with direction or
  # amount. Persisting it once at create-time means enrichment, analytics,
  # and the LedgerEntry view can all read a plain enum instead of each
  # re-deriving it against the user's IBAN/holder set. Single source of
  # truth, queryable in SQL, indexable.
  #
  # Signal priority (first hit wins):
  #   1. payment_method already encodes the answer
  #      (internal_transfer / topup / cash_atm_topup / cash_deposit /
  #       cash_fx_conversion / cash_adjustment) → self
  #   2. counterparty_iban ∈ user.own_ibans → self
  #   3. counterparty_name matches user.own_holder_names → self
  #   4. counterparty_iban or counterparty_name present, neither matches → external
  #   5. neither populated → unknown
  #
  # Known weakness: name-based match has false positives for users with
  # common names ("Anna Kowalska" sending to a different Anna Kowalska).
  # Acceptable for the personal-finance scope — the per-transaction
  # category override always wins, so a misclassification is recoverable.
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

    # Convenience for callers that already have a transaction-shaped object
    # (BankTransaction, ManualTransaction, or a normalizer attribute hash).
    # ManualTransaction has no counterparty_iban — `try` covers that.
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
