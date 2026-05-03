# frozen_string_literal: true

module Admin
  class MatchingEngineController < BaseController
    def show
      # Replicate the in-memory `[-source_rank, -priority, id]` ordering in SQL.
      # SOURCE_RANK = {user:2, llm:1, system:0}; map and ORDER BY DESC, DESC, ASC.
      ordered = current_user.merchant_rules.includes(merchant: :default_category)
                            .order(Arel.sql("CASE source WHEN 'user' THEN 2 WHEN 'llm' THEN 1 WHEN 'system' THEN 0 ELSE -1 END DESC, priority DESC, id ASC"))

      @pagy, @rules = pagy(:offset, ordered)
      @total_rules_count = ordered.count

      # Per-rule count for the visible page + total across ALL rules - the
      # summary card mustn't change with pagination.
      rule_ids = @rules.map(&:id)
      user_enrichments = TransactionEnrichment.for_user(current_user)
      @rule_match_counts = user_enrichments.where(merchant_rule_id: rule_ids)
                                           .group(:merchant_rule_id).count
      @total_rule_matches = user_enrichments.where.not(merchant_rule_id: nil).count

      @fallback_map        = Enrichment::TransactionEnricher::PAYMENT_METHOD_FALLBACK
      @fallback_categories = current_user.categories.where(path: @fallback_map.values.uniq)
                                                    .index_by { |c| c.path.to_s }

      bank_counts = user_enrichments.where(source: "system_fallback")
                                    .joins("INNER JOIN bank_transactions bt ON bt.id = transaction_enrichments.enrichable_id AND transaction_enrichments.enrichable_type = 'BankTransaction'")
                                    .group("bt.direction", "bt.payment_method").count
      cash_counts = user_enrichments.where(source: "system_fallback")
                                    .joins("INNER JOIN manual_transactions mt ON mt.id = transaction_enrichments.enrichable_id AND transaction_enrichments.enrichable_type = 'ManualTransaction'")
                                    .group("mt.direction", "mt.payment_method").count
      @fallback_counts = bank_counts.merge(cash_counts) { |_k, a, b| a + b }

      @unmatched_count = user_enrichments.unmatched.count
      @total_count     = user_enrichments.count
    end
  end
end
