# frozen_string_literal: true

module Enrichment
  # Idempotent rule-based enricher.
  #
  # Modes:
  #   .call(transaction)        — enrich a single ledger entry
  #   .enrich_pending(scope)    — enrich every entry without an enrichment row
  #   .rebuild!(scope)          — reset and re-enrich (preserves manual decisions)
  #
  # Rule resolution order: enabled rules sorted by
  #   (source_rank DESC: user > llm > system,
  #    priority DESC,
  #    id ASC)
  # First matching rule wins. Source-rank ordering guarantees user
  # corrections beat LLM proposals beat seeded system rules — the
  # exact precedence we want for analytics stability.
  #
  # `manual` rows and `category_overridden` rows are never touched by
  # enrich_pending/rebuild — those represent explicit user decisions
  # that the user expects to survive sync + rule edits.
  class TransactionEnricher
    SOURCE_TO_ENRICHMENT = {
      "system" => "system_rule",
      "user"   => "user_rule",
      "llm"    => "llm_rule"
    }.freeze

    # Fallback when no MerchantRule matched: assign a generic category based
    # on payment_method. Catches BLIK without merchant info, card auths, etc.
    # Every value in BankTransaction::PAYMENT_METHODS that has a meaningful
    # generic bucket should appear here — anything missing falls into
    # `unmatched` and won't surface in monthly stats.
    PAYMENT_METHOD_FALLBACK = {
      "blik_pos"           => "blik_pos_unmatched",
      "blik_atm"           => "blik_atm_withdrawal",
      "blik_p2p"           => "private_transfers",
      "card"               => "card_unmatched",
      "card_authorization" => "card_authorization",
      "transfer"           => "transfers",
      "internal_transfer"  => "transfers",
      "topup"              => "transfers",
      "fee"                => "fees"
    }.freeze

    def self.call(transaction) = new.enrich(transaction)

    def self.enrich_pending(scope = BankTransaction.without_enrichment)
      enricher = new
      count = 0
      scope.find_each do |tx|
        enricher.enrich(tx)
        count += 1
      end
      count
    end

    # Re-runs enrichment against all rebuildable rows (preserving manual
    # decisions). Useful after seeding new rules or accepting LLM proposals.
    def self.rebuild!(scope = nil)
      scope ||= TransactionEnrichment.rebuildable
      enricher = new
      scope.includes(:enrichable).find_each do |enrichment|
        next if enrichment.enrichable.nil?
        enricher.enrich(enrichment.enrichable, existing: enrichment)
      end
    end

    def initialize
      @rules               = load_rules
      @fallback_categories = load_fallback_categories
    end

    def enrich(transaction, existing: nil)
      enrichment = existing || transaction.enrichment || transaction.build_enrichment
      return enrichment if enrichment.persisted? && enrichment.manual?
      return enrichment if enrichment.persisted? && enrichment.category_overridden?

      rule = first_matching_rule(transaction)

      if rule
        enrichment.merchant      = rule.merchant
        enrichment.merchant_rule = rule
        enrichment.source        = SOURCE_TO_ENRICHMENT.fetch(rule.source)
        enrichment.confidence    = rule.confidence
        enrichment.model         = rule.model
        enrichment.category      = nil  # let merchant.default_category provide it
      elsif (fallback_category = fallback_category_for(transaction))
        enrichment.merchant      = nil
        enrichment.merchant_rule = nil
        enrichment.source        = "system_fallback"
        enrichment.confidence    = nil
        enrichment.model         = nil
        enrichment.category      = fallback_category
      else
        enrichment.merchant      = nil
        enrichment.merchant_rule = nil
        enrichment.source        = "unmatched"
        enrichment.confidence    = nil
        enrichment.model         = nil
        enrichment.category      = nil
      end

      enrichment.enriched_at = Time.current
      enrichment.save!
      enrichment
    end

    private

    # Snapshot of enabled rules at construction time, sorted by precedence
    # so each transaction is just a linear scan. Cross-field precedence:
    # a user-source rule on `counterparty_name` beats a system-source rule
    # on `title` — so we sort all rules together, not per-field.
    def load_rules
      MerchantRule.enabled.includes(:merchant).to_a
                  .sort_by { |r| [ -r.source_rank, -r.priority, r.id ] }
    end

    def first_matching_rule(transaction)
      @rules.find do |rule|
        value = transaction.public_send(rule.field)
        value.present? && rule.matches?(value)
      end
    end

    # Resolve fallback category lazily once and reuse across the loop.
    # Returns nil when payment_method has no mapping or category isn't seeded.
    def load_fallback_categories
      Category.where(slug: PAYMENT_METHOD_FALLBACK.values.uniq).index_by(&:slug)
    end

    def fallback_category_for(transaction)
      slug = PAYMENT_METHOD_FALLBACK[transaction.payment_method.to_s]
      slug && @fallback_categories[slug]
    end
  end
end
