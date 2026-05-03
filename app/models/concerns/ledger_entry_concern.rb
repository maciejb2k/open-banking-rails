# frozen_string_literal: true

# Write-side of the ledger. Read-side for analytics is the `LedgerEntry` PG
# view (db/views/ledger_entries_v01.sql) which UNIONs both sources.
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

  def effective_category
    return nil if enrichment.nil?
    enrichment.category || enrichment.merchant&.default_category
  end
end
