# frozen_string_literal: true

class BankTransaction < ApplicationRecord
  include LedgerEntry

  DIRECTIONS = %w[credit debit].freeze
  STATUSES   = %w[booked pending].freeze
  PAYMENT_METHODS = %w[
    card blik_pos blik_p2p blik_atm transfer p2p_transfer
    card_recurring card_authorization fee internal_transfer other
  ].freeze

  belongs_to :bank_account
  has_one :tpp_credential, through: :bank_account
  has_one :user, through: :tpp_credential

  encrypts :raw_payload

  # `amount` returns a Money built from (amount_cents, currency). Arithmetic
  # between mismatched currencies raises — no silent PLN+EUR sums.
  monetize :amount_cents, with_model_currency: :currency

  validates :external_id, presence: true, uniqueness: { scope: :bank_account_id }
  validates :booking_date, :amount_cents, :currency, presence: true
  validates :currency, inclusion: { in: Money::Currency.all.map(&:iso_code) }
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :status,    inclusion: { in: STATUSES }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_nil: true

  scope :booked,  -> { where(status: "booked") }
  scope :pending, -> { where(status: "pending") }
  scope :credits, -> { where(direction: "credit") }
  scope :debits,  -> { where(direction: "debit") }
  scope :in_range, ->(from, to) { where(booking_date: from..to) }
  scope :for_user, ->(user) { joins(bank_account: :tpp_credential).where(tpp_credentials: { user_id: user.id }) }
  scope :without_enrichment, -> { left_joins(:enrichment).where(transaction_enrichments: { id: nil }) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[id external_id booking_date value_date transaction_date amount_cents currency
       direction status title type_hint counterparty_name counterparty_iban payment_method
       bank_transaction_code bank_account_id created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[bank_account enrichment]
  end

  def parsed_raw_payload
    return nil if raw_payload.blank?
    raw_payload.is_a?(String) ? JSON.parse(raw_payload) : raw_payload
  rescue JSON::ParserError
    nil
  end

  def signed_amount
    direction == "credit" ? amount : -amount
  end
end
