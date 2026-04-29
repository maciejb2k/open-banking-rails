# frozen_string_literal: true

# Per-transaction derived metadata: which merchant, which category, where the
# decision came from. Polymorphic `enrichable` so the same row shape covers
# BankTransaction (synced) and ManualTransaction (cash, future).
#
# `source` values:
#   unmatched       — no rule fired and no payment_method fallback
#   system_rule     — seeded rule matched
#   user_rule       — user-created rule matched
#   llm_rule        — LLM-proposed rule (enabled, auto-applied above threshold)
#   llm_pending     — LLM proposed, below threshold, awaiting approval
#   manual          — user explicitly set merchant/category on this single tx
#   system_fallback — no rule matched but payment_method has a generic category
#                     (e.g. blik_atm → "Wypłaty z bankomatu")
#
# Rebuild rules: TransactionEnricher only touches rows where
# source != 'manual' AND category_overridden = false.
class TransactionEnrichment < ApplicationRecord
  SOURCES = %w[unmatched system_rule user_rule llm_rule llm_pending manual system_fallback].freeze

  belongs_to :enrichable, polymorphic: true
  belongs_to :merchant, optional: true
  belongs_to :category, optional: true
  belongs_to :merchant_rule, optional: true

  validates :source, inclusion: { in: SOURCES }
  validates :confidence, numericality: { in: 0.0..1.0 }, allow_nil: true

  scope :rebuildable, -> { where.not(source: "manual").where(category_overridden: false) }
  scope :unmatched,   -> { where(source: "unmatched") }
  scope :pending,     -> { where(source: "llm_pending") }

  # Effective category for this enrichment — explicit override or merchant's
  # default. Mirrors LedgerEntry#effective_category for cases where the caller
  # has the enrichment but not the parent transaction.
  def effective_category
    category || merchant&.default_category
  end

  def manual?     = source == "manual"
  def unmatched?  = source == "unmatched"
  def llm?        = source.in?(%w[llm_rule llm_pending])

  def self.ransackable_attributes(_auth_object = nil)
    %w[id source merchant_id category_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[merchant category]
  end
end
