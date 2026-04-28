class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  validates :name, presence: true

  has_many :tpp_credentials, dependent: :destroy
  has_many :bank_connections, through: :tpp_credentials
  has_many :bank_accounts, through: :tpp_credentials

  def primary_tpp_credential
    tpp_credentials.find_by(primary: true)
  end

  def initials
    return "?" if name.blank?

    name.split(/\s+/).first(2).map { |part| part[0]&.upcase }.join
  end

  def display_name
    name.presence || email
  end
end
