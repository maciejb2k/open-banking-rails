# frozen_string_literal: true

module Llm
  # confidence ≥ AUTO_APPROVE_THRESHOLD → enabled rule; > 0 below threshold →
  # disabled rule (pending review); == 0 → skip. Idempotent on re-runs.
  class EnrichmentRunner
    Result = Struct.new(:processed, :auto_applied, :pending_review, :skipped, :errors, keyword_init: true)

    AUTO_APPROVE_THRESHOLD = ENV.fetch("LLM_MERCHANT_AUTO_APPROVE_THRESHOLD", "0.85").to_f
    DEFAULT_LIMIT          = 50  # max distinct groups per run

    def self.call(...) = new(...).call

    def initialize(user:, scope: nil, limit: DEFAULT_LIMIT, client: nil, throttle_seconds: 2, on_batch: nil)
      @user             = user
      @scope            = scope
      @limit            = limit
      # Lazy client resolution - runner is safe to construct without an LLM
      # provider configured.
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

      samples = EnrichableQuery.new(@user).groups(scope: @scope).first(@limit).map { |_sig, sample| sample }
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

    def process_suggestion(suggestion, sample)
      return :skipped if suggestion.merchant_name.blank? || suggestion.confidence.zero?

      validated = enforce_pattern_matches(suggestion, sample)
      # nil = no working pattern (neither LLM's nor derived). Skip rather
      # than persist a useless rule.
      return :skipped if validated.nil?

      ActiveRecord::Base.transaction do
        merchant = upsert_merchant(validated)
        upsert_rule(merchant, validated)
        validated.confident?(AUTO_APPROVE_THRESHOLD) ? :auto_applied : :pending_review
      end
    end

    # If LLM's pattern doesn't match, try a derived pattern via TitleNormalizer
    # and KEEP the LLM's confidence - the merchant identity came from the LLM
    # (the hard part), regex is the easy part with a deterministic fallback.
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

    # Only `title` - counterparty_name is free-text, no better signal to
    # derive from when the LLM's pattern fails.
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

    # Unknown paths fall back to noise.unmatched.other (kind=ignored) - keeps
    # the merchant assignable but invisible to spend totals until reviewed.
    def resolve_category_for(suggestion)
      path = suggestion.category_path.to_s.strip
      @user.categories.find_by(path: path) ||
        @user.categories.find_by(path: "noise.unmatched.other")
    end
  end
end
