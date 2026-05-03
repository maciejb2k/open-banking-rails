# frozen_string_literal: true

# == Schema Information
#
# Table name: merchant_rules
#
#  id             :bigint           not null, primary key
#  approved_at    :datetime
#  case_sensitive :boolean          default(FALSE), not null
#  confidence     :decimal(4, 3)
#  enabled        :boolean          default(TRUE), not null
#  field          :string           not null
#  kind           :string           not null
#  model          :string
#  pattern        :string           not null
#  priority       :integer          default(0), not null
#  source         :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  approved_by_id :bigint
#  merchant_id    :bigint           not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_merchant_rules_on_approved_by_id        (approved_by_id)
#  index_merchant_rules_on_enabled_and_priority  (enabled,priority)
#  index_merchant_rules_on_field_and_pattern     (field,pattern)
#  index_merchant_rules_on_merchant_id           (merchant_id)
#  index_merchant_rules_on_source                (source)
#  index_merchant_rules_on_user_id               (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (approved_by_id => users.id)
#  fk_rails_...  (merchant_id => merchants.id)
#  fk_rails_...  (user_id => users.id)
#
class MerchantRule < ApplicationRecord
  # Source tier (user > llm > system) sorts first, then priority DESC, id ASC.
  # LLM-generated rules below the auto-apply threshold are saved disabled
  # and surfaced in a review queue.

  KINDS   = %w[contains regex exact prefix iban].freeze
  # payment_method is included so normalized signals like blik_atm don't need
  # bank-specific title patterns.
  FIELDS  = %w[title counterparty_name counterparty_iban payment_method].freeze
  SOURCES = %w[system user llm].freeze

  SOURCE_RANK = { "user" => 2, "llm" => 1, "system" => 0 }.freeze

  belongs_to :user
  belongs_to :merchant
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :transaction_enrichments, dependent: :nullify

  validates :kind,    inclusion: { in: KINDS }
  validates :field,   inclusion: { in: FIELDS }
  validates :source,  inclusion: { in: SOURCES }
  validates :pattern, presence: true
  validates :confidence, numericality: { in: 0.0..1.0 }, allow_nil: true
  validate  :regex_compiles

  scope :enabled,  -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :for_field, ->(field) { where(field: field) }
  scope :for_user, ->(user) { where(user_id: user.id) }

  def matches?(value)
    return false if value.blank?
    haystack = case_sensitive? ? value.to_s : value.to_s.downcase
    needle   = case_sensitive? ? pattern : pattern.downcase

    case kind
    when "contains" then haystack.include?(needle)
    when "exact"    then haystack == needle
    when "prefix"   then haystack.start_with?(needle)
    when "iban"     then value.to_s.gsub(/\s+/, "").upcase == pattern.gsub(/\s+/, "").upcase
    when "regex"    then !!(value.to_s =~ compiled_regex)
    end
  end

  def source_rank = SOURCE_RANK.fetch(source, -1)

  private

  def compiled_regex
    @compiled_regex ||= Regexp.new(pattern, case_sensitive? ? 0 : Regexp::IGNORECASE)
  end

  def regex_compiles
    return unless kind == "regex" && pattern.present?
    Regexp.new(pattern)
  rescue RegexpError => e
    errors.add(:pattern, "is not a valid regex: #{e.message}")
  end
end
