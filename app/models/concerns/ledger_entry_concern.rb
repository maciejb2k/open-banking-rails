# frozen_string_literal: true

# Marker + delegation concern for anything that participates in the user's
# financial ledger. Today: BankTransaction, ManualTransaction. Future:
# RecurringTransaction (forecasts).
#
# Carrying the polymorphic `enrichment` association here means callers can
# treat any ledger entry uniformly: `entry.merchant`, `entry.category`,
# `entry.payment_method` work regardless of the concrete class.
#
# NOTE: This concern is the *write-side* of the ledger (persisted records
# with associations + callbacks). The *read-side* for analytics lives in
# the `LedgerEntry` model (PG view at db/views/ledger_entries_v01.sql),
# which UNIONs both ledger sources into a single read-only relation.
module LedgerEntryConcern
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
