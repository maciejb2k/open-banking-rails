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

    # Fallback when no MerchantRule matched: assign a generic category
    # based on (direction, payment_method [, counterparty_kind]).
    #
    # Direction matters: an incoming wire is salary, an outgoing wire is
    # an own-account transfer — same payment_method, completely different
    # category.
    #
    # For `blik_p2p` and `transfer` we also branch on counterparty_kind:
    # money to/from yourself is a transfer; money to/from anyone else is
    # an expense (or income on the credit side). Without that branch the
    # fallback would lump real spending into transfers and hide it from
    # totals — which is exactly the bug the column was added to fix.
    #
    # Values are full ltree paths. Anything missing from this map falls
    # into source=`unmatched` (NULL category) and is invisible to all
    # `.spend` / `.income` totals until reviewed.
    PAYMENT_METHOD_FALLBACK = {
      # ─── Outgoing (debit) — spending or own-transfer ──────────────
      [ "debit", "blik_pos" ]           => "noise.unmatched.blik",
      [ "debit", "blik_atm" ]           => "money.transfers.atm",
      [ "debit", "card" ]               => "noise.unmatched.card",
      [ "debit", "card_authorization" ] => "noise.authorizations.card",
      [ "debit", "internal_transfer" ]  => "money.transfers.own",
      [ "debit", "topup" ]              => "money.transfers.own",
      [ "debit", "fee" ]                => "services.financial.fees",
      # Cash debits (manual transactions)
      [ "debit", "cash" ]               => "noise.unmatched.cash",
      [ "debit", "cash_atm_topup" ]     => "money.transfers.atm",
      [ "debit", "cash_deposit" ]       => "money.transfers.own",
      [ "debit", "cash_fx_conversion" ] => "noise.adjustments.fx",
      [ "debit", "cash_adjustment" ]    => "noise.adjustments.cash",

      # ─── Incoming (credit) — income or refund or own-transfer ─────
      # Internal / topup — moving money between user's own surfaces
      [ "credit", "internal_transfer" ]  => "money.transfers.own",
      [ "credit", "topup" ]              => "money.transfers.own",
      # Card credit = refund / cashback from a merchant.
      [ "credit", "card" ]               => "income.refunds.refunds",
      # ATM credit = unusual but exists (cash deposit at ATM).
      [ "credit", "blik_atm" ]           => "money.transfers.atm",
      # Cash credit = mystery source — flag as income but specify "other".
      [ "credit", "cash" ]               => "income.other.sale",
      [ "credit", "cash_atm_topup" ]     => "money.transfers.atm",
      [ "credit", "cash_deposit" ]       => "money.transfers.own"
    }.freeze

    # Identity-aware fallback for payment methods where "to/from self vs
    # external" changes the kind of category we want. Keyed by
    # (direction, payment_method, counterparty_kind). `unknown` is treated
    # as `external` — if there's no signal that it's our own account, we
    # err on the side of counting it as a real transaction. Worst case the
    # user moves it back via a per-transaction override.
    IDENTITY_AWARE_FALLBACK = {
      # Outgoing BLIK P2P / external wire: money out to someone else is
      # spend (lands in noise.unmatched.other → kind=expense → visible
      # on the spend list); to my own surfaces it's a transfer.
      [ "debit", "blik_p2p", "self" ]     => "money.transfers.own",
      [ "debit", "blik_p2p", "external" ] => "noise.unmatched.other",
      [ "debit", "blik_p2p", "unknown" ]  => "noise.unmatched.other",

      [ "debit", "transfer", "self" ]     => "money.transfers.own",
      [ "debit", "transfer", "external" ] => "noise.unmatched.other",
      [ "debit", "transfer", "unknown" ]  => "noise.unmatched.other",

      # Incoming BLIK P2P / external wire: from self = own-transfer;
      # from someone else = income (refund-shaped) by default. Salary
      # is the most-likely external wire, so credit+transfer+external
      # keeps the legacy salary-default behavior — user reclassifies
      # exotic incoming wires.
      [ "credit", "blik_p2p", "self" ]     => "money.transfers.own",
      [ "credit", "blik_p2p", "external" ] => "income.refunds.refunds",
      [ "credit", "blik_p2p", "unknown" ]  => "income.refunds.refunds",

      [ "credit", "transfer", "self" ]     => "money.transfers.own",
      [ "credit", "transfer", "external" ] => "income.work.salary",
      [ "credit", "transfer", "unknown" ]  => "income.work.salary"
    }.freeze

    # All paths the enricher might assign as a fallback — used to preload
    # category records once per user instead of per transaction.
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

    # Re-runs enrichment against all rebuildable rows for a single user
    # (preserving manual decisions). Useful after seeding new rules or
    # accepting LLM proposals. user: is required — without it the service
    # would walk every user's enrichments and re-enrich them against this
    # user's rule set, which is the bug per-user scoping was added to fix.
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
      @user.merchant_rules.enabled.includes(:merchant).to_a
           .sort_by { |r| [ -r.source_rank, -r.priority, r.id ] }
    end

    def first_matching_rule(transaction)
      @rules.find do |rule|
        # Polymorphic enrichables — a rule's field may not exist on every
        # ledger entry shape (ManualTransaction has no counterparty_iban,
        # for example). Treat missing fields as a non-match instead of a
        # NoMethodError. Skips silently; expected case, not an error.
        next false unless transaction.respond_to?(rule.field)
        value = transaction.public_send(rule.field)
        value.present? && rule.matches?(value)
      end
    end

    # Resolve fallback categories once per user and reuse across the loop.
    # Keyed by full ltree path — unique per user, no collision risk.
    def load_fallback_categories
      @user.categories.where(path: ALL_FALLBACK_PATHS)
           .index_by { |c| c.path.to_s }
    end

    # Two lookups, in order of specificity:
    #   1. Identity-aware: (direction, payment_method, counterparty_kind)
    #      for methods where "to/from self" vs "to/from other" changes
    #      the answer (blik_p2p, transfer).
    #   2. Plain: (direction, payment_method) for everything else.
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
