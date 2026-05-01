# frozen_string_literal: true

# Off-bank ledger entries — cash, IOUs, anything the user types in by hand.
# Shares the polymorphic enrichment pipeline with BankTransaction via the
# LedgerEntry concern, so reports, filters, and rule-matching treat both the
# same.
#
# Why no external_id / uniqueness scope: the user is the source of truth. A
# duplicate row is a UX problem (warn + delete), not a data-integrity problem
# the way it is for synced bank rows.
class ManualTransaction < ApplicationRecord
  include LedgerEntryConcern

  DIRECTIONS = %w[credit debit].freeze
  STATUSES   = %w[booked pending].freeze

  # Distinct namespace from BankTransaction::PAYMENT_METHODS — these only ever
  # appear on manual rows. Each must have a fallback in
  # Enrichment::TransactionEnricher::PAYMENT_METHOD_FALLBACK.
  #
  #   cash                — bare cash spend / income (the default)
  #   cash_atm_topup      — auto-generated when an ATM withdrawal is linked
  #                         (Phase 3); paired with the source bank tx via
  #                         linked_bank_transaction_id
  #   cash_deposit        — user deposited cash to a bank teller (rare)
  #   cash_fx_conversion  — kantor: PLN debit + EUR credit (or similar)
  #   cash_adjustment     — reconciliation correction when wallet balance
  #                         drifts from physical wallet
  PAYMENT_METHODS = %w[cash cash_atm_topup cash_deposit cash_fx_conversion cash_adjustment].freeze

  # Same enum + semantics as BankTransaction::COUNTERPARTY_KINDS.
  # Manual rows have no counterparty_iban, so resolution is name-based
  # (or implied by payment_method for cash_atm_topup / cash_deposit /
  # cash_fx_conversion / cash_adjustment, which are always self).
  COUNTERPARTY_KINDS = %w[self external unknown].freeze

  # Provenance:
  #   manual       — user typed it in
  #   atm_link     — auto-created by Cash::AtmWithdrawalLinker (Phase 3)
  #   csv_import   — bulk import (future)
  #   recurring    — generated from a recurring template (future)
  SOURCES = %w[manual atm_link csv_import recurring].freeze

  belongs_to :bank_account
  belongs_to :linked_bank_transaction, class_name: "BankTransaction", optional: true
  belongs_to :created_by_user, class_name: "User"

  monetize :amount_cents, with_model_currency: :currency

  validates :amount_cents, :currency, :booking_date, presence: true
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :currency, inclusion: { in: Money::Currency.all.map(&:iso_code) }
  validates :direction,      inclusion: { in: DIRECTIONS }
  validates :status,         inclusion: { in: STATUSES }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_nil: true
  validates :source,         inclusion: { in: SOURCES }
  validates :counterparty_kind, inclusion: { in: COUNTERPARTY_KINDS }
  validate  :bank_account_must_be_a_wallet
  validate  :currency_matches_wallet

  has_paper_trail

  # Read-through delegates so admin form helpers (form/_select) can call
  # form.object.merchant_id directly without knowing about the polymorphic
  # enrichment row. Writes still go through Cash::TransactionUpdater, which
  # handles the enrichment side-effects.
  delegate :merchant_id, :category_id, to: :enrichment, allow_nil: true

  scope :booked,  -> { where(status: "booked") }
  scope :pending, -> { where(status: "pending") }
  scope :credits, -> { where(direction: "credit") }
  scope :debits,  -> { where(direction: "debit") }
  scope :in_range, ->(from, to) { where(booking_date: from..to) }
  scope :for_user, ->(user) {
    joins(:bank_account).where(bank_accounts: { manual_owner_id: user.id, manual: true })
  }
  scope :without_enrichment, -> {
    left_joins(:enrichment).where(transaction_enrichments: { id: nil })
  }

  def self.ransackable_attributes(_auth_object = nil)
    %w[id booking_date transaction_date amount_cents currency direction status
       title counterparty_name counterparty_kind payment_method source bank_account_id
       linked_bank_transaction_id created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[bank_account enrichment linked_bank_transaction]
  end

  def signed_amount
    direction == "credit" ? amount : -amount
  end

  # The owner is always reachable via the wallet — cash wallets carry
  # manual_owner_id directly. Useful for authorization checks.
  def user
    bank_account&.manual_owner
  end

  private

  def bank_account_must_be_a_wallet
    return if bank_account.nil?
    errors.add(:bank_account, "must be a manual cash wallet") unless bank_account.manual?
  end

  def currency_matches_wallet
    return if bank_account.nil? || currency.blank? || bank_account.currency.blank?
    return if currency == bank_account.currency
    errors.add(:currency, "must match wallet currency (#{bank_account.currency})")
  end
end
