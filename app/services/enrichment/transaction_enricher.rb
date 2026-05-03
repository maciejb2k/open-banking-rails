# frozen_string_literal: true

module Enrichment
  # Rule resolution: source_rank DESC (user > llm > system), priority DESC, id ASC.
  # First matching rule wins. `manual` rows and `category_overridden` rows are
  # never touched by enrich_pending/rebuild - explicit user decisions survive.
  class TransactionEnricher
    SOURCE_TO_ENRICHMENT = {
      "system" => "system_rule",
      "user"   => "user_rule",
      "llm"    => "llm_rule"
    }.freeze

    # Direction matters: an incoming wire is salary, an outgoing wire is an
    # own-account transfer - same payment_method, different category. For
    # blik_p2p and transfer, identity also matters (handled in
    # IDENTITY_AWARE_FALLBACK below). Anything missing falls into source
    # =`unmatched` (NULL category) and is invisible to .spend/.income
    # totals until reviewed.
    PAYMENT_METHOD_FALLBACK = {
      [ "debit", "blik_pos" ]           => "noise.unmatched.blik",
      [ "debit", "blik_atm" ]           => "money.transfers.atm",
      [ "debit", "card" ]               => "noise.unmatched.card",
      [ "debit", "card_authorization" ] => "noise.authorizations.card",
      [ "debit", "internal_transfer" ]  => "money.transfers.own",
      [ "debit", "topup" ]              => "money.transfers.own",
      [ "debit", "fee" ]                => "services.financial.fees",
      [ "debit", "cash" ]               => "noise.unmatched.cash",
      [ "debit", "cash_atm_topup" ]     => "money.transfers.atm",
      [ "debit", "cash_deposit" ]       => "money.transfers.own",
      [ "debit", "cash_fx_conversion" ] => "noise.adjustments.fx",
      [ "debit", "cash_adjustment" ]    => "noise.adjustments.cash",

      [ "credit", "internal_transfer" ]  => "money.transfers.own",
      [ "credit", "topup" ]              => "money.transfers.own",
      [ "credit", "card" ]               => "income.refunds.refunds",
      [ "credit", "blik_atm" ]           => "money.transfers.atm",
      [ "credit", "cash" ]               => "income.other.sale",
      [ "credit", "cash_atm_topup" ]     => "money.transfers.atm",
      [ "credit", "cash_deposit" ]       => "money.transfers.own"
    }.freeze

    # `unknown` is treated as `external` - without a signal that it's our
    # own account, count it as a real transaction (user reclassifies). For
    # credit+transfer+external, default to salary (most-likely external wire).
    IDENTITY_AWARE_FALLBACK = {
      [ "debit", "blik_p2p", "self" ]     => "money.transfers.own",
      [ "debit", "blik_p2p", "external" ] => "noise.unmatched.other",
      [ "debit", "blik_p2p", "unknown" ]  => "noise.unmatched.other",

      [ "debit", "transfer", "self" ]     => "money.transfers.own",
      [ "debit", "transfer", "external" ] => "noise.unmatched.other",
      [ "debit", "transfer", "unknown" ]  => "noise.unmatched.other",

      [ "credit", "blik_p2p", "self" ]     => "money.transfers.own",
      [ "credit", "blik_p2p", "external" ] => "income.refunds.refunds",
      [ "credit", "blik_p2p", "unknown" ]  => "income.refunds.refunds",

      [ "credit", "transfer", "self" ]     => "money.transfers.own",
      [ "credit", "transfer", "external" ] => "income.work.salary",
      [ "credit", "transfer", "unknown" ]  => "income.work.salary"
    }.freeze

    ALL_FALLBACK_PATHS = (PAYMENT_METHOD_FALLBACK.values + IDENTITY_AWARE_FALLBACK.values).uniq.freeze

    def self.call(transaction, user:) = new(user: user).enrich(transaction)

    def self.enrich_pending(user:, scope: nil)
      scope ||= BankTransaction.for_user(user).without_enrichment
      enricher = new(user: user)
      count = 0
      scope.find_each do |tx|
        enricher.enrich(tx)
        count += 1
      end
      count
    end

    # user: is required - without it the service would re-enrich every user's
    # data against this user's rule set.
    def self.rebuild!(user:, scope: nil)
      scope ||= TransactionEnrichment.for_user(user).rebuildable
      enricher = new(user: user)
      scope.includes(:enrichable).find_each do |enrichment|
        next if enrichment.enrichable.nil?
        enricher.enrich(enrichment.enrichable, existing: enrichment)
      end
    end

    def initialize(user:)
      @user                = user
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
        enrichment.category      = nil
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

    # All rules sorted together (not per-field) - a user-source rule on
    # counterparty_name beats a system-source rule on title.
    def load_rules
      @user.merchant_rules.enabled.includes(:merchant).to_a
           .sort_by { |r| [ -r.source_rank, -r.priority, r.id ] }
    end

    def first_matching_rule(transaction)
      @rules.find do |rule|
        # Polymorphic enrichables - ManualTransaction has no counterparty_iban
        # etc. Treat missing fields as a non-match, not a NoMethodError.
        next false unless transaction.respond_to?(rule.field)
        value = transaction.public_send(rule.field)
        value.present? && rule.matches?(value)
      end
    end

    def load_fallback_categories
      @user.categories.where(path: ALL_FALLBACK_PATHS)
           .index_by { |c| c.path.to_s }
    end

    def fallback_category_for(transaction)
      direction = transaction.direction.to_s
      method    = transaction.payment_method.to_s
      kind      = transaction.try(:counterparty_kind).to_s

      path = IDENTITY_AWARE_FALLBACK[[ direction, method, kind ]] ||
             PAYMENT_METHOD_FALLBACK[[ direction, method ]]
      path && @fallback_categories[path]
    end
  end
end
