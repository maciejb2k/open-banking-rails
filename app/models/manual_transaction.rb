# frozen_string_literal: true

# == Schema Information
#
# Table name: manual_transactions
#
#  id                         :bigint           not null, primary key
#  amount_cents               :bigint           not null
#  booking_date               :date             not null
#  counterparty_kind          :string           default("unknown"), not null
#  counterparty_name          :string
#  currency                   :string(3)        not null
#  direction                  :string           not null
#  note                       :text
#  payment_method             :string
#  source                     :string           default("manual"), not null
#  status                     :string           default("booked"), not null
#  title                      :text
#  transaction_date           :date
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  bank_account_id            :bigint           not null
#  created_by_user_id         :bigint           not null
#  linked_bank_transaction_id :bigint
#
# Indexes
#
#  idx_manual_transactions_one_per_linked_bank_tx                 (linked_bank_transaction_id) UNIQUE WHERE (linked_bank_transaction_id IS NOT NULL)
#  index_manual_transactions_on_bank_account_id                   (bank_account_id)
#  index_manual_transactions_on_bank_account_id_and_booking_date  (bank_account_id,booking_date)
#  index_manual_transactions_on_counterparty_kind                 (counterparty_kind)
#  index_manual_transactions_on_created_by_user_id                (created_by_user_id)
#  index_manual_transactions_on_linked_bank_transaction_id        (linked_bank_transaction_id)
#  index_manual_transactions_on_payment_method                    (payment_method)
#  index_manual_transactions_on_status                            (status)
#
# Foreign Keys
#
#  fk_rails_...  (bank_account_id => bank_accounts.id)
#  fk_rails_...  (created_by_user_id => users.id)
#  fk_rails_...  (linked_bank_transaction_id => bank_transactions.id)
#
class ManualTransaction < ApplicationRecord
  include LedgerEntryConcern

  DIRECTIONS = %w[credit debit].freeze
  STATUSES   = %w[booked pending].freeze

  # Distinct namespace from BankTransaction::PAYMENT_METHODS. Each must have
  # a fallback in Enrichment::TransactionEnricher::PAYMENT_METHOD_FALLBACK.
  PAYMENT_METHODS = %w[cash cash_atm_topup cash_deposit cash_fx_conversion cash_adjustment].freeze

  COUNTERPARTY_KINDS = %w[self external unknown].freeze

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

  # Read-through delegates so form helpers can call form.object.merchant_id
  # directly. Writes go through Cash::TransactionUpdater for the enrichment
  # side-effects.
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
