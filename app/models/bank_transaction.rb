# frozen_string_literal: true

# == Schema Information
#
# Table name: bank_transactions
#
#  id                    :bigint           not null, primary key
#  amount_cents          :bigint           not null
#  bank_transaction_code :string
#  booking_date          :date             not null
#  counterparty_iban     :string
#  counterparty_kind     :string           default("unknown"), not null
#  counterparty_name     :string
#  currency              :string(3)        not null
#  direction             :string           not null
#  fetched_at            :datetime         not null
#  payment_method        :string
#  raw_payload           :text             not null
#  status                :string           default("booked"), not null
#  title                 :text
#  transaction_date      :date
#  type_hint             :string
#  value_date            :date
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  bank_account_id       :bigint           not null
#  external_id           :string           not null
#
# Indexes
#
#  index_bank_transactions_on_bank_account_id                   (bank_account_id)
#  index_bank_transactions_on_bank_account_id_and_booking_date  (bank_account_id,booking_date)
#  index_bank_transactions_on_bank_account_id_and_external_id   (bank_account_id,external_id) UNIQUE
#  index_bank_transactions_on_counterparty_kind                 (counterparty_kind)
#  index_bank_transactions_on_payment_method                    (payment_method)
#  index_bank_transactions_on_status                            (status)
#
# Foreign Keys
#
#  fk_rails_...  (bank_account_id => bank_accounts.id)
#
class BankTransaction < ApplicationRecord
  include LedgerEntryConcern

  DIRECTIONS = %w[credit debit].freeze
  STATUSES   = %w[booked pending].freeze
  # Single source of truth for payment_method values. Set by
  # EnableBanking::PaymentMethodInferer at sync time. Each entry must have a
  # mapping in PaymentMethodInferer (or be reachable via heuristics) AND a
  # fallback category in Enrichment::TransactionEnricher::PAYMENT_METHOD_FALLBACK
  # — otherwise unmatched transactions disappear into the "unmatched" bucket.
  #
  #   card                 — POS / online card payment, card-on-file SaaS
  #   card_authorization   — preauth block (paliwo, hotel) — not a real charge
  #   blik_pos             — BLIK at merchant terminal
  #   blik_p2p             — BLIK to phone (direction tells in vs out)
  #   blik_atm             — BLIK ATM withdrawal (PKO MOBILE-PAYMENT-ATM)
  #   transfer             — external bank transfer (PRZELEW ZEWNĘTRZNY)
  #   internal_transfer    — between own accounts, incl. credit-card payback
  #   topup                — Revolut TOPUP (Google Pay → Revolut)
  #   fee                  — bank fee / commission
  #   other                — explicitly classified, but doesn't fit above
  PAYMENT_METHODS = %w[
    card card_authorization
    blik_pos blik_p2p blik_atm
    transfer internal_transfer topup
    fee other
  ].freeze

  # Set by Banking::CounterpartyResolver at sync time. See that service for
  # signal priority. "self" means the counterparty is one of the user's own
  # accounts; "external" means a third party; "unknown" means we can't tell
  # (no IBAN, no name).
  COUNTERPARTY_KINDS = %w[self external unknown].freeze

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
  validates :counterparty_kind, inclusion: { in: COUNTERPARTY_KINDS }

  scope :booked,  -> { where(status: "booked") }
  scope :pending, -> { where(status: "pending") }
  scope :credits, -> { where(direction: "credit") }
  scope :debits,  -> { where(direction: "debit") }
  scope :in_range, ->(from, to) { where(booking_date: from..to) }
  scope :for_user, ->(user) { joins(bank_account: :tpp_credential).where(tpp_credentials: { user_id: user.id }) }
  scope :without_enrichment, -> { left_joins(:enrichment).where(transaction_enrichments: { id: nil }) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[id external_id booking_date value_date transaction_date amount_cents currency
       direction status title type_hint counterparty_name counterparty_iban counterparty_kind
       payment_method bank_transaction_code bank_account_id created_at updated_at]
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
