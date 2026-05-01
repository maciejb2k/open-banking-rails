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

  # Identity of the other side of the entry, set at sync time by
  # Banking::CounterpartyResolver and projected through from the source
  # tables. `with_external_counterparty` is the canonical filter for
  # "real" transactions — own-account moves are excluded, so analytics
  # don't double-count money that's just shuffling around.
  scope :to_self,                    -> { where(counterparty_kind: "self") }
  scope :with_external_counterparty, -> { where(counterparty_kind: %w[external unknown]) }

  # Layer 1 — subtree containment via the view's `category_path` (ltree
  # projected from categories.path). Pass a Category, ltree string, or
  # array of either. Empty input returns `none` so a missing filter
  # doesn't accidentally widen the scope.
  scope :under_path, ->(path_or_paths) {
    paths = Array(path_or_paths).map { |p| p.is_a?(Category) ? p.path : p.to_s }
    return none if paths.empty?
    where(paths.map { "category_path <@ ?" }.join(" OR "), *paths)
  }

  # Layer 2 — needs vs wants axis. Projected from categories.essential
  # in the view, so analytics can `.essential` without re-joining.
  scope :essential,     -> { where(essential: true) }
  scope :discretionary, -> { where(essential: false) }

  # Layer 2 — recurring (cyclical charge), independent of category. The
  # detector populates this on transaction_enrichments; the view surfaces
  # it on every ledger entry.
  scope :recurring, -> { where(recurring: true) }
  scope :one_off,   -> { where(recurring: false) }

  # Kind-partitioned scopes — the canonical entry points for analytics.
  # `Category#kind` partitions every category into expense/income/transfer/
  # savings/ignored, and analytics MUST always narrow on kind before
  # summing amounts. Summing raw signed_amount_cents across all rows is
  # nonsense (income cancels expense, transfers double-count).
  #
  # `spend` and `income` also pin the direction so a misclassified row
  # (e.g. an incoming top-up that an LLM rule glued to "Cloud Storage"
  # category, kind=expense) can't inflate the spend total. Defense-in-
  # depth: even if classification regresses, totals stay sane.
  scope :spend,     -> { debits.joins(:effective_category).where(categories: { kind: "expense" }) }
  scope :income,    -> { credits.joins(:effective_category).where(categories: { kind: "income" }) }
  scope :transfers, -> { joins(:effective_category).where(categories: { kind: "transfer" }) }
  scope :savings,   -> { joins(:effective_category).where(categories: { kind: "savings" }) }

  # Cross-ownership user scope. Delegates to User#all_bank_account_ids so
  # the union (synced via tpp_credentials + cash via manual_owner_id) lives
  # in one place; analytics services use the same helper directly.
  scope :for_user, ->(user) { where(bank_account_id: user.all_bank_account_ids) }

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
