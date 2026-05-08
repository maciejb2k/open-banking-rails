# frozen_string_literal: true

# == Schema Information
#
# Table name: ledger_entries
#
#  amount_cents          :bigint
#  booking_date          :date
#  category_path         :ltree
#  counterparty_kind     :string
#  counterparty_name     :string
#  currency              :string(3)
#  direction             :string
#  enrichment_source     :string
#  essential             :boolean
#  payment_method        :string
#  signed_amount_cents   :bigint
#  source_type           :text
#  status                :string
#  title                 :text
#  transaction_date      :date
#  bank_account_id       :bigint
#  effective_category_id :bigint
#  enrichment_id         :bigint
#  merchant_id           :bigint
#  source_id             :bigint
#
class LedgerEntry < ApplicationRecord
  # Read-side of the ledger. Analytics queries go through here, not the
  # source tables. Extension path is documented in db/views/ledger_entries_v01.sql
  # and AGENTS.md "Analytics data access".

  self.primary_key = nil

  # Rails 8 needs an order column for `.first`/`.last`. source_id isn't unique
  # across source_types but suffices for inspection - analytics specify ORDER BY.
  self.implicit_order_column = :source_id

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

  scope :to_self,                    -> { where(counterparty_kind: "self") }
  scope :with_external_counterparty, -> { where(counterparty_kind: %w[external unknown]) }

  # Empty input returns `none` so a missing filter doesn't widen scope.
  scope :under_path, ->(path_or_paths) {
    paths = Array(path_or_paths).map { |p| p.is_a?(Category) ? p.path : p.to_s }
    return none if paths.empty?
    where(paths.map { "category_path <@ ?" }.join(" OR "), *paths)
  }

  scope :essential,     -> { where(essential: true) }
  scope :discretionary, -> { where(essential: false) }

  # `spend` / `income` also pin direction - defense-in-depth so a
  # misclassified row (an incoming top-up the LLM glued to expense kind)
  # can't inflate the spend total.
  scope :spend,     -> { debits.joins(:effective_category).where(categories: { kind: "expense" }) }
  scope :income,    -> { credits.joins(:effective_category).where(categories: { kind: "income" }) }
  scope :transfers, -> { joins(:effective_category).where(categories: { kind: "transfer" }) }
  scope :savings,   -> { joins(:effective_category).where(categories: { kind: "savings" }) }

  scope :for_user, ->(user) { where(bank_account_id: user.all_bank_account_ids) }

  # Off the hot path - analytics queries should use view columns directly.
  def source_record
    source_type.constantize.find(source_id)
  end

  def signed_amount
    Money.new(signed_amount_cents, currency)
  end
end
