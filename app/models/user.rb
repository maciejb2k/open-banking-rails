# == Schema Information
#
# Table name: users
#
#  id                       :bigint           not null, primary key
#  email                    :string           default(""), not null
#  encrypted_password       :string           default(""), not null
#  name                     :string
#  remember_created_at      :datetime
#  reset_password_sent_at   :datetime
#  reset_password_token     :string
#  reveal_hidden_categories :boolean          default(FALSE), not null
#  track_cash               :boolean          default(FALSE), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#
class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  validates :name, presence: true

  has_many :tpp_credentials, dependent: :destroy
  has_many :bank_connections, through: :tpp_credentials
  has_many :bank_accounts, through: :tpp_credentials
  has_many :cash_wallets, -> { where(manual: true) },
           class_name: "BankAccount", foreign_key: :manual_owner_id, dependent: :destroy
  has_many :manual_transactions, through: :cash_wallets

  has_many :user_hidden_categories, dependent: :destroy
  has_many :hidden_categories, through: :user_hidden_categories, source: :category

  has_many :categories,      dependent: :destroy
  has_many :merchants,       dependent: :destroy
  has_many :merchant_rules,  dependent: :destroy

  has_one :llm_setting, dependent: :destroy

  has_many :personal_access_tokens, dependent: :destroy

  has_many :operation_runs, foreign_key: :triggered_by_user_id, dependent: :destroy

  # Subtree-aware: hiding `food` hides every descendant. The user-selected
  # ids widen to "any descendant of a hidden path" via ltree.
  def hides_category?(category_or_id)
    return false if reveal_hidden_categories
    return false if category_or_id.blank?
    id = category_or_id.respond_to?(:id) ? category_or_id.id : category_or_id
    hidden_subtree_ids.include?(id)
  end

  def hidden_subtree_ids
    @hidden_subtree_ids ||= begin
      hidden_paths = categories.where(id: hidden_category_ids).pluck(:path).compact
      if hidden_paths.empty?
        Set.new
      else
        sql = hidden_paths.map { "path <@ ?" }.join(" OR ")
        Set.new(categories.where(sql, *hidden_paths).pluck(:id))
      end
    end
  end

  def primary_tpp_credential
    tpp_credentials.find_by(primary: true)
  end

  # `has_many :bank_accounts, through:` only covers synced - this is the
  # union with cash wallets.
  def all_bank_account_ids
    BankAccount.where(tpp_credential_id: tpp_credentials.select(:id))
               .or(BankAccount.where(manual_owner_id: id))
               .pluck(:id)
  end

  def owned_bank_accounts
    BankAccount.where(id: all_bank_account_ids)
  end

  # Banks fill `name` differently (mBank uppercase, Revolut titlecase, PKO
  # sometimes empty) - match against this normalized set, not a single value.
  def own_holder_names
    owned_bank_accounts.pluck(:name).compact_blank.map { |n| n.strip.upcase }.uniq
  end

  def own_ibans
    accounts = owned_bank_accounts
    (accounts.pluck(:iban).compact + accounts.find_each.flat_map(&:alternate_ibans))
      .compact_blank.map { |i| i.gsub(/\s+/, "").upcase }.uniq
  end

  def initials
    return "?" if name.blank?

    name.split(/\s+/).first(2).map { |part| part[0]&.upcase }.join
  end

  def display_name
    name.presence || email
  end
end
