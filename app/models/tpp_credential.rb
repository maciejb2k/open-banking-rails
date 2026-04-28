# frozen_string_literal: true

class TppCredential < ApplicationRecord
  PROVIDERS = %w[enable_banking].freeze
  ENVIRONMENTS = %w[PRODUCTION SANDBOX].freeze
  STATUSES = %w[pending active error].freeze

  belongs_to :user
  has_many :bank_connections, dependent: :restrict_with_error
  has_many :bank_accounts, dependent: :restrict_with_error

  encrypts :application_id, :private_key_pem

  validates :name, presence: true
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :environment, inclusion: { in: ENVIRONMENTS }, allow_blank: true
  validates :application_id, presence: true
  validates :private_key_pem, presence: true
  validates :redirect_url, presence: true

  before_save :extract_cert_metadata

  has_paper_trail skip: %i[application_id private_key_pem]

  scope :primary_for, ->(user) { where(user: user, primary: true) }

  # Ransack — explicit allowlist. Encrypted secrets are deliberately excluded.
  def self.ransackable_attributes(_auth_object = nil)
    %w[id name provider environment status primary redirect_url cert_expires_at
       last_verified_at user_id created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[user bank_connections]
  end

  # Enforce only one primary per user. The DB-level partial unique index is the
  # ultimate guard; this AR-level guard ensures the failure mode is a clean
  # validation message rather than a constraint violation.
  validate :only_one_primary_per_user, if: :primary?

  def to_breadcrumb
    name
  end

  def cert_info
    return nil if public_cert_pem.blank?

    cert = OpenSSL::X509::Certificate.new(public_cert_pem)
    {
      subject: cert.subject.to_s,
      issuer: cert.issuer.to_s,
      not_before: cert.not_before,
      not_after: cert.not_after,
      days_remaining: ((cert.not_after - Time.current) / 1.day).to_i,
      serial: cert.serial.to_s,
      signature_algorithm: cert.signature_algorithm,
      key_size: rsa_key_size(cert)
    }
  rescue OpenSSL::X509::CertificateError
    nil
  end

  def cert_expired?
    cert_expires_at.present? && cert_expires_at < Time.current
  end

  def cert_expiring_soon?(within: 30.days)
    cert_expires_at.present? && cert_expires_at < within.from_now
  end

  def make_primary!
    transaction do
      self.class.where(user_id: user_id).where.not(id: id).update_all(primary: false)
      update!(primary: true)
    end
  end

  private

  def rsa_key_size(cert)
    cert.public_key.is_a?(OpenSSL::PKey::RSA) ? cert.public_key.n.num_bits : nil
  end

  def extract_cert_metadata
    info = cert_info
    self.cert_expires_at = info ? info[:not_after] : nil
  end

  def only_one_primary_per_user
    scope = self.class.where(user_id: user_id, primary: true)
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:primary, "another credential is already primary for this user")
  end
end
