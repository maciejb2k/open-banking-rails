# frozen_string_literal: true

class BankAccount < ApplicationRecord
  STATUSES = %w[active inactive revoked].freeze
  CASH_ACCOUNT_TYPES = %w[CACC CARD CASH LOAN OTHR SVGS].freeze

  # Two ownership shapes, mutually exclusive (DB-enforced via
  # bank_accounts_ownership_xor check constraint):
  #   - Synced bank account: tpp_credential set, manual_owner nil, manual=false
  #   - Cash wallet:         manual_owner set, tpp_credential nil, manual=true
  belongs_to :tpp_credential, optional: true
  belongs_to :manual_owner, class_name: "User", optional: true
  belongs_to :current_bank_connection, class_name: "BankConnection", optional: true

  has_one :synced_user, through: :tpp_credential, source: :user
  has_many :bank_transactions, dependent: :destroy
  has_many :manual_transactions, dependent: :destroy

  encrypts :raw_balances

  validates :uid, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :cash_account_type, inclusion: { in: CASH_ACCOUNT_TYPES }, allow_blank: true
  validate  :ownership_consistency

  has_paper_trail

  scope :active, -> { where(status: "active") }
  scope :synced, -> { where(manual: false) }
  scope :wallets, -> { where(manual: true) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[id uid iban bban currency name product details cash_account_type usage
       status manual details_fetched_at balances_synced_at transactions_synced_at
       tpp_credential_id manual_owner_id current_bank_connection_id created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[tpp_credential current_bank_connection manual_owner]
  end

  def display_name
    name.presence || product.presence || details.presence || iban.presence || uid
  end

  # Resolves the human owner irrespective of ownership shape. Use this instead
  # of `tpp_credential.user` whenever cash wallets might be in scope.
  def owner
    manual? ? manual_owner : tpp_credential&.user
  end

  def cash_wallet?
    manual?
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

  private

  # Mirrors the DB check constraint so AR surfaces a friendly message.
  def ownership_consistency
    if manual?
      errors.add(:tpp_credential_id, "must be blank for a cash wallet") if tpp_credential_id.present?
      errors.add(:manual_owner_id, "is required for a cash wallet") if manual_owner_id.blank?
    else
      errors.add(:manual_owner_id, "must be blank for a synced account") if manual_owner_id.present?
      errors.add(:tpp_credential_id, "is required for a synced account") if tpp_credential_id.blank?
    end
  end
end
