# frozen_string_literal: true

module Enrichment
  # Three propagation modes:
  #   :only_this        - write override on this enrichment row, mark
  #                       source: "manual" so future rebuilds skip it.
  #   :all_for_merchant - set merchant.default_category; every tx for this
  #                       merchant inherits via #effective_category.
  #   :create_rule      - create a user-source MerchantRule + rebuild.
  class ClassificationApplier
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
      @input.merchant.update!(default_category: @input.category) if @input.category

      # Clear any prior `manual` lock so this row tracks the merchant going forward.
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
