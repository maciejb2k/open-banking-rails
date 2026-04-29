# frozen_string_literal: true

module Admin
  # Read-only visualization of the enrichment pipeline:
  #   1) MerchantRule list in execution order (source > priority > id)
  #   2) PAYMENT_METHOD_FALLBACK map (catches what no rule matched)
  #   3) Counts of matched transactions per rule + per fallback
  #
  # Helps the user understand why a given transaction landed where it did.
  class MatchingEngineController < BaseController
    def show
      @rules = MerchantRule.includes(merchant: :default_category).to_a
                           .sort_by { |r| [ -r.source_rank, -r.priority, r.id ] }

      # Per-rule match count via TransactionEnrichment association.
      rule_ids = @rules.map(&:id)
      @rule_match_counts = TransactionEnrichment.where(merchant_rule_id: rule_ids)
                                                .group(:merchant_rule_id).count

      @fallback_map     = Enrichment::TransactionEnricher::PAYMENT_METHOD_FALLBACK
      @fallback_counts  = TransactionEnrichment.where(source: "system_fallback")
                                               .joins("INNER JOIN bank_transactions ON bank_transactions.id = transaction_enrichments.enrichable_id AND transaction_enrichments.enrichable_type = 'BankTransaction'")
                                               .group("bank_transactions.payment_method").count
      @fallback_categories = Category.where(slug: @fallback_map.values.uniq).index_by(&:slug)

      @unmatched_count = TransactionEnrichment.unmatched.count
      @total_count     = TransactionEnrichment.count
    end
  end
end
