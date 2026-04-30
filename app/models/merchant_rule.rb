# frozen_string_literal: true

# A single pattern → merchant assignment. Matched in priority order by
# TransactionEnricher; first hit wins.
#
# `kind` is the match strategy:
#   contains | exact | prefix — string ops, optional case_sensitive
#   regex                     — Ruby regex, anchored as written
#   iban                      — exact match against counterparty_iban
#
# `source` mirrors Merchant#source for ordering: user > llm > system. Within a
# source tier, higher `priority` wins; within equal priority, lower `id` wins.
#
# LLM-generated rules below the auto-apply confidence threshold are saved
# with `enabled: false` and surfaced in a review queue.
class MerchantRule < ApplicationRecord
  KINDS   = %w[contains regex exact prefix iban].freeze
  # Fields on the ledger entry a rule can match against. payment_method is
  # included so canonical (already-normalized) signals like blik_atm don't
  # need bank-specific title patterns. The enricher tolerates models that
  # don't expose a given field (e.g. ManualTransaction has no counterparty_iban).
  FIELDS  = %w[title counterparty_name counterparty_iban payment_method].freeze
  SOURCES = %w[system user llm].freeze

  # Higher = applied first; matches the precedence we want when sorting in SQL.
  SOURCE_RANK = { "user" => 2, "llm" => 1, "system" => 0 }.freeze

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

  # Returns truthy on match. `value` is the field value from the transaction.
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
