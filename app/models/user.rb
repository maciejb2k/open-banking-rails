class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  validates :name, presence: true

  has_many :tpp_credentials, dependent: :destroy
  has_many :bank_connections, through: :tpp_credentials
  has_many :bank_accounts, through: :tpp_credentials
  has_many :cash_wallets, -> { where(manual: true) },
           class_name: "BankAccount", foreign_key: :manual_owner_id, dependent: :destroy
  has_many :manual_transactions, through: :cash_wallets

  def primary_tpp_credential
    tpp_credentials.find_by(primary: true)
  end

  # Every BankAccount the user owns — synced (via tpp_credentials) plus
  # cash wallets (via manual_owner_id). The `has_many :bank_accounts,
  # through:` association only covers synced accounts; this is the
  # union, used wherever analytics needs "all of the user's accounts".
  def all_bank_account_ids
    BankAccount.where(tpp_credential_id: tpp_credentials.select(:id))
               .or(BankAccount.where(manual_owner_id: id))
               .pluck(:id)
  end

  def initials
    return "?" if name.blank?

    name.split(/\s+/).first(2).map { |part| part[0]&.upcase }.join
  end

  def display_name
    name.presence || email
  end
end
