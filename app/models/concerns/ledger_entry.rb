# frozen_string_literal: true

# Marker + delegation concern for anything that participates in the user's
# financial ledger. Today: BankTransaction. Tomorrow: ManualTransaction
# (cash), potentially RecurringTransaction (forecasts).
#
# Carrying the polymorphic `enrichment` association here means callers can
# treat any ledger entry uniformly: `entry.merchant`, `entry.category`,
# `entry.payment_method` work regardless of the concrete class. The eventual
# `ledger_entries` Postgres view (Phase 4) joins on `enrichable_type` /
# `enrichable_id` directly.
module LedgerEntry
  extend ActiveSupport::Concern

  included do
    has_one :enrichment,
            as: :enrichable,
            class_name: "TransactionEnrichment",
            dependent: :destroy

    delegate :merchant, :category, :enrichment_source, :enrichment_confidence,
             to: :enrichment, allow_nil: true
  end

  # Effective category: explicit override on the enrichment, or fallback to
  # the merchant's default. Returns nil if neither is set.
  def effective_category
    return nil if enrichment.nil?
    enrichment.category || enrichment.merchant&.default_category
  end
end
