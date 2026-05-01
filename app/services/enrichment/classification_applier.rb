# frozen_string_literal: true

module Enrichment
  # Applies a user's classification edit on a single transaction with one of
  # three propagation modes:
  #
  #   :only_this   — write the override on this enrichment row only.
  #                  Marks `source: "manual"` so future rebuilds skip it.
  #   :all_for_merchant — set merchant.default_category (if user picked one);
  #                  every transaction enriched against this merchant
  #                  inherits the new category through #effective_category.
  #                  This transaction's enrichment loses its `manual` flag
  #                  so it stays in sync with the merchant default.
  #   :create_rule — create a new user-source MerchantRule from the chosen
  #                  field+pattern, then rebuild enrichments. The rule wins
  #                  for all matching transactions (past and future).
  #
  # Returns Result.new(success:, message:).
  class ClassificationApplier
    # Carries the whole user edit payload — what classification to write,
    # what propagation mode, and (for :create_rule) the seed rule. The
    # controller resolves merchant/category to AR records before
    # constructing this; raw ids never reach the service.
    Input = Struct.new(
      :mode, :merchant, :category, :rule_field, :rule_kind, :rule_pattern,
      keyword_init: true
    ) do
      def normalized_mode      = mode.to_sym
      def normalized_rule_kind = (rule_kind.presence || "contains").to_s
      def normalized_rule_field = (rule_field.presence || "title").to_s
    end

    Result = Struct.new(:success, :message, keyword_init: true) do
      def success? = success
    end

    PROPAGATION_MODES = %i[only_this all_for_merchant create_rule].freeze

    def self.call(...) = new(...).call

    def initialize(transaction:, input:, actor:)
      @transaction = transaction
      @input       = input
      @actor       = actor
    end

    def call
      mode = @input.normalized_mode
      return failure("Unknown propagation mode: #{mode}") unless PROPAGATION_MODES.include?(mode)
      return failure("Pick a merchant") if @input.merchant.nil? && mode != :only_this
      return failure("Pick a pattern") if mode == :create_rule && @input.rule_pattern.blank?

      ActiveRecord::Base.transaction do
        case mode
        when :only_this        then apply_only_this
        when :all_for_merchant then apply_all_for_merchant
        when :create_rule      then apply_create_rule
        end
      end

      success("Applied: #{label_for_mode(mode)}")
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.join(", "))
    end

    private

    def apply_only_this
      enrichment = @transaction.enrichment || @transaction.build_enrichment
      enrichment.merchant            = @input.merchant
      enrichment.category            = @input.category
      enrichment.category_overridden = @input.category.present?
      enrichment.source              = "manual"
      enrichment.merchant_rule       = nil
      enrichment.confidence          = nil
      enrichment.model               = nil
      enrichment.enriched_at         = Time.current
      enrichment.save!
    end

    def apply_all_for_merchant
      # Update merchant default category (if user picked one) so every
      # transaction enriched against this merchant inherits it through
      # `effective_category` — no DB write per transaction needed.
      @input.merchant.update!(default_category: @input.category) if @input.category

      # Re-enrich this transaction against the rule set so it tracks the
      # merchant going forward (clears any prior `manual` lock).
      enrichment = @transaction.enrichment || @transaction.build_enrichment
      enrichment.merchant            = @input.merchant
      enrichment.category            = nil
      enrichment.category_overridden = false
      enrichment.source              = "user_rule"
      enrichment.enriched_at         = Time.current
      enrichment.save!
    end

    def apply_create_rule
      rule = @actor.merchant_rules.create!(
        merchant: @input.merchant,
        kind: @input.normalized_rule_kind,
        field: @input.normalized_rule_field,
        pattern: @input.rule_pattern,
        priority: 100,
        source: "user",
        enabled: true,
        approved_at: Time.current,
        approved_by: @actor
      )
      # Optionally update merchant default if user picked a category.
      if @input.category && @input.merchant.default_category_id != @input.category.id
        @input.merchant.update!(default_category: @input.category)
      end

      Enrichment::TransactionEnricher.rebuild!(user: @actor)
      rule
    end

    def label_for_mode(mode)
      {
        only_this:        "this transaction only",
        all_for_merchant: "all transactions for this merchant",
        create_rule:      "new rule + rebuild"
      }.fetch(mode)
    end

    def success(msg) = Result.new(success: true, message: msg)
    def failure(msg) = Result.new(success: false, message: msg)
  end
end
