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
  # Polymorphic `enrichable` covers BankTransaction + ManualTransaction.
  # TransactionEnricher rebuilds touch only rows where source != 'manual' AND
  # category_overridden = false.

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
  # Covers both `unmatched` and `system_fallback` - the right scope for
  # "what can the LLM still help with".
  scope :merchantless, -> { where(merchant_id: nil) }

  scope :for_user, ->(user) {
    where(
      "(enrichable_type = 'BankTransaction' AND enrichable_id IN (?)) OR " \
      "(enrichable_type = 'ManualTransaction' AND enrichable_id IN (?))",
      BankTransaction.for_user(user).select(:id),
      ManualTransaction.for_user(user).select(:id)
    )
  }

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
