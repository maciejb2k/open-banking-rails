# frozen_string_literal: true

module Llm
  # Orchestrates LLM-driven enrichment for a batch of unmatched transactions.
  #
  # Flow:
  #   1. Find unmatched transactions (with usable `title` or `counterparty_name`)
  #   2. Group by (normalized_title, counterparty_name) — deduplicate clusters
  #   3. Send clusters to MerchantSuggester in batches of BATCH_SIZE (one API
  #      call per batch, not per transaction)
  #      - confidence ≥ AUTO_APPROVE_THRESHOLD → create Merchant + enabled rule
  #      - confidence < threshold but > 0     → create Merchant + disabled rule
  #      - confidence == 0                    → skip
  #   4. Rebuild enrichments at the end so newly enabled rules apply to history
  #
  # Idempotent on re-runs: existing Merchant slugs are never duplicated.
  class EnrichmentRunner
    Result = Struct.new(:processed, :auto_applied, :pending_review, :skipped, :errors, keyword_init: true)

    AUTO_APPROVE_THRESHOLD = ENV.fetch("LLM_MERCHANT_AUTO_APPROVE_THRESHOLD", "0.85").to_f
    DEFAULT_LIMIT          = 50  # max distinct groups per run

    def self.call(...) = new(...).call

    def initialize(user:, scope: nil, limit: DEFAULT_LIMIT, client: nil, throttle_seconds: 2, on_batch: nil)
      @user             = user
      @scope            = scope || default_scope
      @limit            = limit
      # Client resolved lazily — the index action instantiates the runner
      # purely to inspect groups (build_groups), and we don't want that to
      # raise NotConfiguredError when LLM hasn't been set up yet.
      @client_override  = client
      @throttle_seconds = throttle_seconds
      @on_batch         = on_batch
    end

    def client
      @client ||= @client_override || Llm::Client.for(user: @user)
    end

    def call
      auto = pending = skipped = 0
      errors = []

      samples = build_groups(@scope).first(@limit).map { |_sig, sample| sample }
      batches = samples.each_slice(Llm::MerchantSuggester::BATCH_SIZE).to_a

      Rails.logger.info("[Llm::EnrichmentRunner] #{samples.size} groups → #{batches.size} batch calls (auto-approve ≥ #{AUTO_APPROVE_THRESHOLD})")

      batches.each_with_index do |batch, batch_idx|
        batch_auto = batch_pending = batch_skipped = 0
        batch_errors = []
        suggester = Llm::MerchantSuggester.new(user: @user, items: batch, client: client)

        begin
          suggestions = suggester.call

          batch.zip(suggestions).each do |sample, suggestion|
            outcome = process_suggestion(suggestion, sample)
            case outcome
            when :auto_applied   then batch_auto    += 1
            when :pending_review then batch_pending += 1
            when :skipped        then batch_skipped += 1
            end
          rescue ActiveRecord::RecordInvalid => e
            batch_errors << { title: sample[:title], error: "#{e.class}: #{e.message}" }
            Rails.logger.warn("[Llm::EnrichmentRunner] record invalid: #{e.message}")
          end

          @on_batch&.call(
            index: batch_idx, size: batch.size, status: "succeeded",
            auto: batch_auto, pending: batch_pending, skipped: batch_skipped,
            errors: batch_errors,
            request: suggester.last_input, response: suggester.last_response
          )
        rescue Llm::Client::Error => e
          batch_errors = batch.map { |s| { title: s[:title], error: e.message } }
          Rails.logger.warn("[Llm::EnrichmentRunner] batch #{batch_idx} failed: #{e.message}")
          @on_batch&.call(
            index: batch_idx, size: batch.size, status: "failed",
            auto: 0, pending: 0, skipped: 0,
            errors: batch_errors,
            request: suggester.last_input, response: nil
          )
        end

        auto    += batch_auto
        pending += batch_pending
        skipped += batch_skipped
        errors  += batch_errors

        sleep @throttle_seconds if @throttle_seconds.positive? && batch_idx < batches.size - 1
      end

      Enrichment::TransactionEnricher.rebuild!(user: @user) if auto.positive?

      Result.new(processed: samples.size, auto_applied: auto, pending_review: pending, skipped: skipped, errors: errors)
    end

    private

    # Payment methods where the concept of "merchant" doesn't apply:
    # BLIK to a phone is a transfer between people, ATM is a cash withdrawal,
    # internal transfers / topups move money within your own accounts, fees
    # are bank charges. Sending these to the LLM produces noise at best
    # ("John Doe is a merchant" — nope, that's the user) and bad rules
    # at worst (counterparty_name=exact lockouts that catch innocent strangers).
    NON_MERCHANT_PAYMENT_METHODS = %w[blik_p2p blik_atm internal_transfer topup fee].freeze

    # Anything without a merchant (source = unmatched OR system_fallback) AND
    # that could plausibly have one. We deliberately filter out three classes
    # of false positives — each independently sufficient to send the LLM
    # down the wrong path:
    #
    #   1. Payment methods that aren't merchant-shaped (see constant above).
    #   2. counterparty_iban that belongs to one of the user's own accounts —
    #      defense-in-depth on top of OwnAccountMerchantSyncer's IBAN rules,
    #      so an alternate-BBAN or missing-IBAN edge case can't slip through.
    #   3. counterparty_name that matches the user's own holder name across
    #      any account. Catches the "stranger with the same name as you"
    #      case: their transfers come in with your IBAN unmatched (it isn't
    #      yours) but with your literal name in counterparty_name. The LLM
    #      would happily propose your name as a merchant; this stops it.
    def default_scope
      scope = BankTransaction.for_user(@user)
                .joins(:enrichment)
                .merge(TransactionEnrichment.merchantless)
                .where("(title IS NOT NULL AND title <> '' AND title !~ '^[0-9]+$') OR (counterparty_name IS NOT NULL AND counterparty_name <> '')")
                .where.not(payment_method: NON_MERCHANT_PAYMENT_METHODS)

      own = own_ibans
      scope = scope.where("counterparty_iban IS NULL OR REPLACE(UPPER(counterparty_iban), ' ', '') NOT IN (?)", own) if own.any?

      names = own_holder_names
      scope = scope.where("counterparty_name IS NULL OR UPPER(BTRIM(counterparty_name)) NOT IN (?)", names) if names.any?

      scope
    end

    def user_bank_accounts
      @user_bank_accounts ||= BankAccount.where(id: @user.all_bank_account_ids)
    end

    # All IBANs (primary + alternates) across every BankAccount the user owns.
    # Returns normalized (no spaces, uppercase) for SQL comparison stability.
    def own_ibans
      @own_ibans ||= (
        user_bank_accounts.pluck(:iban).compact +
        user_bank_accounts.find_each.flat_map(&:alternate_ibans)
      ).compact_blank.map { |i| i.gsub(/\s+/, "").upcase }.uniq
    end

    # Account-holder names (banks fill `BankAccount.name` differently — mBank
    # uppercase, Revolut titlecase, PKO sometimes empty). Normalize to upper +
    # strip so we catch every spelling variant in one IN clause.
    def own_holder_names
      @own_holder_names ||= user_bank_accounts.pluck(:name)
                                              .compact_blank
                                              .map { |n| n.strip.upcase }
                                              .uniq
    end

    # Build groups of unmatched transactions and skip those already covered
    # by an existing MerchantRule (regardless of enabled/source) — sending
    # them to the LLM would yield the same suggestion and waste tokens.
    # User must accept the existing pending merchant to release the group.
    def build_groups(scope)
      rules = @user.merchant_rules.to_a

      scope.find_each.each_with_object({}) do |tx, acc|
        key = [ Enrichment::TitleNormalizer.call(tx.title), tx.counterparty_name.to_s ]
        next if key == [ "", "" ]
        next if covered_by_existing_rule?(rules, tx)
        acc[key] ||= { title: tx.title, counterparty_name: tx.counterparty_name }
      end
    end

    def covered_by_existing_rule?(rules, tx)
      rules.any? do |r|
        value = case r.field
                when "title"             then tx.title
                when "counterparty_name" then tx.counterparty_name
                when "counterparty_iban" then tx.counterparty_iban
                end
        value.present? && r.matches?(value)
      end
    end

    def process_suggestion(suggestion, sample)
      return :skipped if suggestion.merchant_name.blank? || suggestion.confidence.zero?

      validated = enforce_pattern_matches(suggestion, sample)
      # nil means we couldn't produce a working pattern — neither LLM's
      # nor a derived one matched the source. Skip rather than persist a
      # disabled rule with a useless pattern (those linger in the DB,
      # waste future LLM tokens, and the disabled state means the rule
      # never actually classifies anything).
      return :skipped if validated.nil?

      ActiveRecord::Base.transaction do
        merchant = upsert_merchant(validated)
        upsert_rule(merchant, validated)
        validated.confident?(AUTO_APPROVE_THRESHOLD) ? :auto_applied : :pending_review
      end
    end

    # Three outcomes:
    #   1. LLM's pattern already matches the source title → keep as-is.
    #   2. LLM's pattern doesn't match, but TitleNormalizer.likely_pattern
    #      can derive one that does → swap LLM's pattern for the derived
    #      one and KEEP the original confidence. The merchant identity
    #      came from the LLM (which is what's hard); the regex was the
    #      easy part it stumbled on, and we have a deterministic fallback.
    #   3. Even derived doesn't work → return nil. Caller skips the row
    #      instead of persisting a useless disabled rule.
    def enforce_pattern_matches(suggestion, sample)
      sample_value = case suggestion.rule_field
                     when "title"             then sample[:title]
                     when "counterparty_name" then sample[:counterparty_name]
                     end
      return nil if sample_value.blank?

      llm_probe = MerchantRule.new(
        kind: suggestion.rule_kind, field: suggestion.rule_field,
        pattern: suggestion.rule_pattern, case_sensitive: false, merchant_id: 0
      )
      return suggestion if llm_probe.matches?(sample_value)

      derived = derive_pattern_for(suggestion.rule_field, sample_value)
      if derived.present?
        derived_probe = MerchantRule.new(
          kind: "contains", field: suggestion.rule_field,
          pattern: derived, case_sensitive: false, merchant_id: 0
        )
        if derived_probe.matches?(sample_value)
          Rails.logger.info("[Llm::EnrichmentRunner] swapped LLM pattern #{suggestion.rule_pattern.inspect} → #{derived.inspect} for #{sample_value.inspect}")
          return suggestion.dup.tap do |s|
            s.rule_pattern = derived
            s.rule_kind    = "contains"
            s.reasoning    = "[DERIVED] LLM pattern didn't match; replaced with stripped-title substring. #{s.reasoning}"
          end
        end
      end

      Rails.logger.warn("[Llm::EnrichmentRunner] no working pattern for #{sample_value.inspect}; LLM proposed #{suggestion.rule_pattern.inspect}, skipping")
      nil
    end

    # Deterministic fallback pattern derived from the source value via the
    # same stripping logic the title normalizer uses for grouping. Only
    # `title` field — for counterparty_name (free-text), if the LLM's
    # pattern fails, we have no better signal to derive from.
    def derive_pattern_for(field, value)
      return nil unless field == "title"
      Enrichment::TitleNormalizer.likely_pattern(value)
    end

    def upsert_merchant(suggestion)
      slug = slugify(suggestion.merchant_name)
      merchant = @user.merchants.find_or_initialize_by(slug: slug)
      merchant.assign_attributes(
        name:             suggestion.merchant_name,
        kind:             allowed_kind(suggestion.merchant_kind),
        source:           merchant.persisted? ? merchant.source : "llm",
        confidence:       suggestion.confidence,
        model:            client.model,
        default_category: resolve_category_for(suggestion),
        notes:            [ merchant.notes, suggestion.reasoning ].compact_blank.uniq.join("\n").presence
      )
      merchant.approved_at = Time.current if !merchant.persisted? && suggestion.confident?(AUTO_APPROVE_THRESHOLD)
      merchant.save!
      merchant
    end

    def upsert_rule(merchant, suggestion)
      rule = merchant.merchant_rules.find_or_initialize_by(
        field: suggestion.rule_field, kind: suggestion.rule_kind, pattern: suggestion.rule_pattern
      )
      rule.user       = @user
      rule.source     = "llm"
      rule.confidence = suggestion.confidence
      rule.model      = client.model
      rule.priority   = 50
      rule.enabled    = suggestion.confident?(AUTO_APPROVE_THRESHOLD)
      rule.save!
      rule
    end

    def slugify(name)
      name.to_s.downcase.gsub(/\p{M}/, "").gsub(/[^a-z0-9]+/, "_").gsub(/_+/, "_").gsub(/\A_|_\z/, "").presence ||
        "merchant_#{SecureRandom.hex(4)}"
    end

    def allowed_kind(value)
      Merchant::KINDS.include?(value) ? value : nil
    end

    # LLM returns a full ltree path (e.g. "food.cooking.supermarket").
    # We accept paths that exist in the user's active set; anything else
    # falls back to noise.unmatched.other (kind=ignored), which keeps the
    # merchant assignable but invisible to spend totals until reviewed.
    def resolve_category_for(suggestion)
      path = suggestion.category_path.to_s.strip
      @user.categories.find_by(path: path) ||
        @user.categories.find_by(path: "noise.unmatched.other")
    end
  end
end
