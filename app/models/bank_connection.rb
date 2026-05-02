# frozen_string_literal: true

# == Schema Information
#
# Table name: bank_connections
#
#  id                  :bigint           not null, primary key
#  access_balances     :boolean          default(TRUE), not null
#  access_transactions :boolean          default(TRUE), not null
#  authorized_at       :datetime
#  bank_country        :string           default("PL")
#  bank_name           :string
#  bank_slug           :string           not null
#  closed_at           :datetime
#  last_error          :text
#  last_refreshed_at   :datetime
#  last_synced_at      :datetime
#  psu_id_hash         :text
#  psu_type            :string           default("personal")
#  raw_session_payload :text
#  status              :string           default("pending"), not null
#  valid_until         :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  replaces_id         :bigint
#  session_id          :text
#  tpp_credential_id   :bigint           not null
#
# Indexes
#
#  index_bank_connections_lookup                (tpp_credential_id,bank_slug,status)
#  index_bank_connections_on_replaces_id        (replaces_id)
#  index_bank_connections_on_status             (status)
#  index_bank_connections_on_tpp_credential_id  (tpp_credential_id)
#  index_bank_connections_on_valid_until        (valid_until)
#
# Foreign Keys
#
#  fk_rails_...  (replaces_id => bank_connections.id)
#  fk_rails_...  (tpp_credential_id => tpp_credentials.id)
#
class BankConnection < ApplicationRecord
  STATUSES = %w[pending authorized expired revoked replaced error closed].freeze
  PSU_TYPES = %w[personal business].freeze

  belongs_to :tpp_credential
  belongs_to :replaces, class_name: "BankConnection", optional: true
  has_one :user, through: :tpp_credential
  has_many :current_bank_accounts, class_name: "BankAccount",
                                   foreign_key: :current_bank_connection_id,
                                   dependent: :nullify,
                                   inverse_of: :current_bank_connection
  has_one :sync_schedule, dependent: :destroy

  encrypts :session_id, :psu_id_hash, :raw_session_payload

  validates :bank_slug, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :psu_type, inclusion: { in: PSU_TYPES }, allow_blank: true

  has_paper_trail skip: %i[session_id psu_id_hash raw_session_payload]

  # Ransack — explicit allowlist. Encrypted columns deliberately excluded.
  def self.ransackable_attributes(_auth_object = nil)
    %w[id bank_slug bank_country bank_name status psu_type valid_until authorized_at
       last_refreshed_at last_synced_at closed_at access_balances access_transactions
       tpp_credential_id replaces_id created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[tpp_credential replaces]
  end

  scope :active,    -> { where(status: "authorized") }
  scope :inactive,  -> { where.not(status: "authorized") }
  scope :for_bank,  ->(slug) { where(bank_slug: slug) }
  scope :for_user,  ->(user) { joins(:tpp_credential).where(tpp_credentials: { user_id: user.id }) }
  scope :expiring_within, ->(duration) { active.where(valid_until: ..duration.from_now) }
  scope :expired,   -> { where("valid_until < ?", Time.current) }

  def to_breadcrumb
    bank_name.presence || bank_slug
  end

  def days_until_expiry
    return nil if valid_until.blank?

    ((valid_until - Time.current) / 1.day).to_i
  end

  def expired?
    valid_until.present? && valid_until < Time.current
  end

  def expiring_soon?(within: 7.days)
    valid_until.present? && valid_until < within.from_now
  end

  # Convenience for views — friendly badge color hint
  def status_tone
    case status
    when "authorized" then expiring_soon? ? :warning : :success
    when "pending"    then :info
    when "expired", "revoked", "error" then :danger
    when "replaced"   then :muted
    else :muted
    end
  end
end
