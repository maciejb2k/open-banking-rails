# frozen_string_literal: true

class BankAccount < ApplicationRecord
  STATUSES = %w[active inactive revoked].freeze
  CASH_ACCOUNT_TYPES = %w[CACC CARD CASH LOAN OTHR SVGS].freeze

  belongs_to :tpp_credential
  belongs_to :current_bank_connection, class_name: "BankConnection", optional: true
  has_one :user, through: :tpp_credential

  encrypts :raw_balances

  validates :uid, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :cash_account_type, inclusion: { in: CASH_ACCOUNT_TYPES }, allow_blank: true

  has_paper_trail

  scope :active, -> { where(status: "active") }

  def self.ransackable_attributes(_auth_object = nil)
    %w[id uid iban bban currency name product details cash_account_type usage
       status details_fetched_at balances_synced_at transactions_synced_at
       tpp_credential_id current_bank_connection_id created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[tpp_credential current_bank_connection]
  end

  def display_name
    name.presence || product.presence || details.presence || iban.presence || uid
  end

  def alternate_ibans
    Array(all_account_ids).filter_map do |id|
      next nil unless id["scheme_name"] == "IBAN"
      next nil if id["identification"] == iban
      id["identification"]
    end
  end

  def bic
    account_servicer&.dig("bic_fi")
  end

  def needs_details_refresh?
    details_fetched_at.blank? || details_fetched_at < 7.days.ago
  end

  # Convenience for parsing latest balances snapshot.
  def parsed_balances
    return [] if raw_balances.blank?
    payload = raw_balances.is_a?(String) ? JSON.parse(raw_balances) : raw_balances
    Array(payload["balances"])
  rescue JSON::ParserError
    []
  end

  def self.bban_from(account_id_payload)
    other = account_id_payload&.dig("other")
    return nil unless other.is_a?(Hash) && other["scheme_name"] == "BBAN"
    other["identification"]
  end
end
