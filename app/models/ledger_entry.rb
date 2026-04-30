# frozen_string_literal: true

# Read-only unified ledger for analytics. Backed by the `ledger_entries`
# Postgres view (db/views/ledger_entries_v01.sql) which UNIONs
# BankTransaction + ManualTransaction and pre-resolves enrichment +
# effective category in SQL.
#
# This model is the *read-side* of the ledger — analytics queries should
# always go through here, not through the source tables, so they never
# duplicate the union/enrichment-resolution boilerplate. Writes happen on
# the source models (BankTransaction, ManualTransaction) which include
# LedgerEntryConcern.
#
# To extend the view (new ledger source, new analytics column), see the
# header comment in db/views/ledger_entries_v01.sql and the "Analytics
# data access" section in AGENTS.md.
#
# Performance note: the view is non-materialized (always fresh, no
# maintenance). For the personal-app scale (≤ 10⁵ rows) Postgres uses the
# underlying indexes — `(bank_account_id, booking_date)` and
# `(enrichable_type, enrichable_id)` — through the view. If aggregations
# ever get slow, the upgrade path is `change_view :ledger_entries,
# materialized: true` + a refresh cron; nothing else changes.
class LedgerEntry < ApplicationRecord
  self.primary_key = nil

  # The view has no PK; Rails 8 needs an order column for `.first`/`.last`
  # to avoid raising ActiveRecord::MissingRequiredOrderError. source_id
  # isn't unique across source_types but is good enough for inspection —
  # analytics queries always specify their own ORDER BY.
  self.implicit_order_column = :source_id

  # Postgres rejects UPDATE/DELETE on a plain view without INSTEAD OF
  # triggers. `readonly?` is the Rails-side guard that surfaces a clean
  # ActiveRecord::ReadOnlyRecord instead of a database error.
  def readonly?
    true
  end

  monetize :amount_cents,        with_model_currency: :currency
  monetize :signed_amount_cents, with_model_currency: :currency

  belongs_to :bank_account
  belongs_to :merchant, optional: true
  belongs_to :effective_category,
             class_name:  "Category",
             foreign_key: :effective_category_id,
             optional:    true

  scope :booked,   -> { where(status: "booked") }
  scope :pending,  -> { where(status: "pending") }
  scope :credits,  -> { where(direction: "credit") }
  scope :debits,   -> { where(direction: "debit") }
  scope :in_range, ->(from, to) { where(booking_date: from..to) }

  # Kind-partitioned scopes — the canonical entry points for analytics.
  # `Category#kind` partitions every category into expense/income/transfer/
  # savings/ignored, and analytics MUST always narrow on kind before
  # summing amounts. Summing raw signed_amount_cents across all rows is
  # nonsense (income cancels expense, transfers double-count).
  scope :spend,     -> { joins(:effective_category).where(categories: { kind: "expense" }) }
  scope :income,    -> { joins(:effective_category).where(categories: { kind: "income" }) }
  scope :transfers, -> { joins(:effective_category).where(categories: { kind: "transfer" }) }
  scope :savings,   -> { joins(:effective_category).where(categories: { kind: "savings" }) }

  # Cross-ownership user scope. Synced bank accounts are reachable via
  # tpp_credentials; cash wallets via bank_accounts.manual_owner_id.
  # The OR is collapsed into a single `bank_account_id IN (...)` so the
  # view stays in a flat plan.
  scope :for_user, ->(user) {
    account_ids = BankAccount.where(tpp_credential_id: user.tpp_credentials.select(:id))
                             .or(BankAccount.where(manual_owner_id: user.id))
                             .select(:id)
    where(bank_account_id: account_ids)
  }

  # Resolve back to the underlying record when a caller needs a field that
  # isn't projected in the view (raw_payload, note, external_id, etc.) or
  # needs to mutate. Polymorphic by source_type — keep this off the hot
  # path; analytics queries should use view columns directly.
  def source_record
    source_type.constantize.find(source_id)
  end

  def signed_amount
    Money.new(signed_amount_cents, currency)
  end
end
