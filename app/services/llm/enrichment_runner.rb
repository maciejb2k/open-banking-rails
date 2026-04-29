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

    def initialize(scope: nil, limit: DEFAULT_LIMIT, client: nil, throttle_seconds: 2, on_batch: nil)
      @scope            = scope || default_scope
      @limit            = limit
      @client           = client || Llm::Client.default
      @throttle_seconds = throttle_seconds
      @on_batch         = on_batch
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
        suggester = Llm::MerchantSuggester.new(items: batch, client: @client)

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

      Enrichment::TransactionEnricher.rebuild! if auto.positive?

      Result.new(processed: samples.size, auto_applied: auto, pending_review: pending, skipped: skipped, errors: errors)
    end

    private

    def default_scope
      BankTransaction
        .joins(:enrichment)
        .where(transaction_enrichments: { source: "unmatched" })
        .where("(title IS NOT NULL AND title <> '' AND title !~ '^[0-9]+$') OR (counterparty_name IS NOT NULL AND counterparty_name <> '')")
    end

    # Build groups of unmatched transactions and skip those already covered
    # by an existing MerchantRule (regardless of enabled/source) — sending
    # them to the LLM would yield the same suggestion and waste tokens.
    # User must accept the existing pending merchant to release the group.
    def build_groups(scope)
      rules = MerchantRule.all.to_a

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

      ActiveRecord::Base.transaction do
        merchant = upsert_merchant(validated)
        upsert_rule(merchant, validated)
        validated.confident?(AUTO_APPROVE_THRESHOLD) ? :auto_applied : :pending_review
      end
    end

    # If the proposed rule doesn't match the sample it was generated from, the
    # model hallucinated the pattern — demote below auto-approve threshold.
    def enforce_pattern_matches(suggestion, sample)
      probe = MerchantRule.new(
        kind: suggestion.rule_kind, field: suggestion.rule_field,
        pattern: suggestion.rule_pattern, case_sensitive: false, merchant_id: 0
      )
      sample_value = case suggestion.rule_field
                     when "title"             then sample[:title]
                     when "counterparty_name" then sample[:counterparty_name]
                     end

      return suggestion if sample_value.present? && probe.matches?(sample_value)

      Rails.logger.warn("[Llm::EnrichmentRunner] hallucinated pattern: #{suggestion.rule_pattern.inspect} doesn't match #{sample_value.inspect}")
      suggestion.dup.tap do |s|
        s.confidence = [ s.confidence, AUTO_APPROVE_THRESHOLD - 0.01 ].min
        s.reasoning  = "[GUARD] Pattern nie pasuje do sample — wymaga weryfikacji. #{s.reasoning}"
      end
    end

    def upsert_merchant(suggestion)
      slug = slugify(suggestion.merchant_name)
      merchant = Merchant.find_or_initialize_by(slug: slug)
      merchant.assign_attributes(
        name:             suggestion.merchant_name,
        display_name:     suggestion.merchant_name,
        kind:             allowed_kind(suggestion.merchant_kind),
        source:           merchant.persisted? ? merchant.source : "llm",
        confidence:       suggestion.confidence,
        model:            ENV.fetch("LLM_MODEL", "gemini-2.5-flash"),
        default_category: Category.find_by(slug: suggestion.category_slug) || Category.find_by(slug: "uncategorized"),
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
      rule.source     = "llm"
      rule.confidence = suggestion.confidence
      rule.model      = ENV.fetch("LLM_MODEL", "gemini-2.5-flash")
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
  end
end
