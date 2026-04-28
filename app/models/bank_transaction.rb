# frozen_string_literal: true

class BankTransaction < ApplicationRecord
  DIRECTIONS = %w[credit debit].freeze
  STATUSES   = %w[booked pending].freeze

  belongs_to :bank_account
  has_one :tpp_credential, through: :bank_account
  has_one :user, through: :tpp_credential

  encrypts :raw_payload

  validates :external_id, presence: true, uniqueness: { scope: :bank_account_id }
  validates :booking_date, :amount, :currency, presence: true
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :status,    inclusion: { in: STATUSES }

  scope :booked,  -> { where(status: "booked") }
  scope :pending, -> { where(status: "pending") }
  scope :credits, -> { where(direction: "credit") }
  scope :debits,  -> { where(direction: "debit") }
  scope :in_range, ->(from, to) { where(booking_date: from..to) }
  scope :for_user, ->(user) { joins(bank_account: :tpp_credential).where(tpp_credentials: { user_id: user.id }) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[id external_id booking_date value_date transaction_date amount currency
       direction status title type_hint counterparty_name counterparty_iban
       bank_transaction_code bank_account_id created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[bank_account]
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
