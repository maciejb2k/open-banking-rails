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
      # Replicate the in-memory `[-source_rank, -priority, id]` ordering
      # in SQL so we can paginate. SOURCE_RANK = {user:2, llm:1, system:0};
      # lower value = sorted later, so we map and ORDER BY DESC, DESC, ASC.
      ordered = current_user.merchant_rules.includes(merchant: :default_category)
                            .order(Arel.sql("CASE source WHEN 'user' THEN 2 WHEN 'llm' THEN 1 WHEN 'system' THEN 0 ELSE -1 END DESC, priority DESC, id ASC"))

      @pagy, @rules = pagy(:offset, ordered)
      @total_rules_count = ordered.count

      # Per-rule match count for the visible page (rendered next to each
      # row) AND the total across ALL rules (for the summary card —
      # otherwise the "Classified by rule" total would change with
      # pagination, which is misleading).
      rule_ids = @rules.map(&:id)
      user_enrichments = TransactionEnrichment.for_user(current_user)
      @rule_match_counts = user_enrichments.where(merchant_rule_id: rule_ids)
                                           .group(:merchant_rule_id).count
      @total_rule_matches = user_enrichments.where.not(merchant_rule_id: nil).count

      # Fallback map: keyed by [direction, payment_method] tuples, values
      # are full ltree paths. Hydrate categories by path (not slug).
      @fallback_map        = Enrichment::TransactionEnricher::PAYMENT_METHOD_FALLBACK
      @fallback_categories = current_user.categories.where(path: @fallback_map.values.uniq)
                                                    .index_by { |c| c.path.to_s }

      # Per-fallback match count: a fallback fired when source=system_fallback,
      # so we group by (direction, payment_method) joined to the source
      # transaction. Both bank and manual rows can hit fallbacks.
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
