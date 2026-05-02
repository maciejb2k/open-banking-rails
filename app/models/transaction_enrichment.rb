# frozen_string_literal: true

# == Schema Information
#
# Table name: transaction_enrichments
#
#  id                  :bigint           not null, primary key
#  category_overridden :boolean          default(FALSE), not null
#  confidence          :decimal(4, 3)
#  enrichable_type     :string           not null
#  enriched_at         :datetime
#  model               :string
#  notes               :text
#  recurrence_interval :string
#  recurring           :boolean          default(FALSE), not null
#  source              :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  category_id         :bigint
#  enrichable_id       :bigint           not null
#  merchant_id         :bigint
#  merchant_rule_id    :bigint
#
# Indexes
#
#  idx_enrichments_on_enrichable                      (enrichable_type,enrichable_id) UNIQUE
#  index_transaction_enrichments_on_category_id       (category_id)
#  index_transaction_enrichments_on_enrichable        (enrichable_type,enrichable_id)
#  index_transaction_enrichments_on_merchant_id       (merchant_id)
#  index_transaction_enrichments_on_merchant_rule_id  (merchant_rule_id)
#  index_transaction_enrichments_on_recurring         (recurring) WHERE (recurring = true)
#  index_transaction_enrichments_on_source            (source)
#
# Foreign Keys
#
#  fk_rails_...  (category_id => categories.id)
#  fk_rails_...  (merchant_id => merchants.id)
#  fk_rails_...  (merchant_rule_id => merchant_rules.id)
#
class TransactionEnrichment < ApplicationRecord
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
  #
  # Layer 2/3 fields (orthogonal to merchant + category):
  #   * `recurring` (bool) + `recurrence_interval` (weekly/monthly/yearly)
  #     — populated by Recurrence::Detector. Treated as a property of the
  #     transaction, not a category — Spotify's enrichment lands in
  #     `lifestyle.entertainment.streaming` AND has `recurring: true`.
  #   * `tags` via gutentag — free-form labels for cross-cuts ("vacation 2026",
  #     "renovation"). Independent of category.

  Gutentag::ActiveRecord.call self

  SOURCES = %w[unmatched system_rule user_rule llm_rule llm_pending manual system_fallback].freeze
  RECURRENCE_INTERVALS = %w[weekly monthly yearly].freeze

  belongs_to :enrichable, polymorphic: true
  belongs_to :merchant, optional: true
  belongs_to :category, optional: true
  belongs_to :merchant_rule, optional: true

  validates :source, inclusion: { in: SOURCES }
  validates :confidence, numericality: { in: 0.0..1.0 }, allow_nil: true
  validates :recurrence_interval, inclusion: { in: RECURRENCE_INTERVALS }, allow_nil: true

  scope :rebuildable, -> { where.not(source: "manual").where(category_overridden: false) }
  scope :unmatched,   -> { where(source: "unmatched") }
  scope :pending,     -> { where(source: "llm_pending") }
  scope :recurring,   -> { where(recurring: true) }
  scope :one_off,     -> { where(recurring: false) }
  # Anything without a merchant — covers `unmatched` AND `system_fallback`
  # (the latter has a generic payment-method category but no concrete seller).
  # This is the right scope for "what can the LLM still help with" — both
  # cases lack merchant_id and may have signal in title / counterparty_name.
  scope :merchantless, -> { where(merchant_id: nil) }

  # Cross-ownership user scope for the polymorphic enrichable. Mirrors
  # LedgerEntry#for_user — scoping has to walk both source tables. Pluck
  # materializes IDs in Ruby, which is fine at the personal-app scale
  # (≤ 10⁵ tx); if it ever gets hot, push it down into a UNION subquery.
  scope :for_user, ->(user) {
    where(
      "(enrichable_type = 'BankTransaction' AND enrichable_id IN (?)) OR " \
      "(enrichable_type = 'ManualTransaction' AND enrichable_id IN (?))",
      BankTransaction.for_user(user).select(:id),
      ManualTransaction.for_user(user).select(:id)
    )
  }

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
    %w[id source merchant_id category_id recurring recurrence_interval]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[merchant category tags]
  end
end
