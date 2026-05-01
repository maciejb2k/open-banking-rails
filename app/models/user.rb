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

  # Audit log of every long-running operation the user triggered (sync, LLM
  # enrichment, connection test). Cascade on delete — the FK is NOT NULL so
  # without :destroy a user delete would be blocked by the constraint, and
  # a vanished user's run history isn't useful on its own.
  has_many :operation_runs, foreign_key: :triggered_by_user_id, dependent: :destroy

  # Always-on (no separate toggle). The act of selecting a category in
  # /admin/settings/preferences IS the hide trigger; the topbar
  # privacy_mode is orthogonal and broader (everything sensitive at once).
  #
  # Subtree-aware: hiding `food` hides every descendant
  # (`food.cooking.*`, `food.eating_out.*`). The user-selected ids are
  # widened to "any descendant of a hidden path" via an ltree subtree
  # query. Memoized per-request — the answer is fixed within a render
  # and the expansion is two queries (hidden ids → paths → descendants).
  def hides_category?(category_or_id)
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
