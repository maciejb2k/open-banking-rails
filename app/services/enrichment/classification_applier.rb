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
    Result = Struct.new(:success, :message, keyword_init: true) do
      def success? = success
    end

    PROPAGATION_MODES = %i[only_this all_for_merchant create_rule].freeze

    def self.call(...) = new(...).call

    def initialize(transaction:, merchant:, category:, mode:, rule_field: nil, rule_pattern: nil, rule_kind: "contains", actor: nil)
      @transaction  = transaction
      @merchant     = merchant
      @category     = category
      @mode         = mode.to_sym
      @rule_field   = rule_field
      @rule_pattern = rule_pattern
      @rule_kind    = rule_kind
      @actor        = actor
    end

    def call
      return failure("Nieznany tryb propagacji: #{@mode}") unless PROPAGATION_MODES.include?(@mode)
      return failure("Wybierz sprzedawcę") if @merchant.nil? && @mode != :only_this
      return failure("Wybierz wzorzec") if @mode == :create_rule && @rule_pattern.blank?

      ActiveRecord::Base.transaction do
        case @mode
        when :only_this        then apply_only_this
        when :all_for_merchant then apply_all_for_merchant
        when :create_rule      then apply_create_rule
        end
      end

      success("Zastosowano: #{label_for_mode(@mode)}")
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.join(", "))
    end

    private

    def apply_only_this
      enrichment = @transaction.enrichment || @transaction.build_enrichment
      enrichment.merchant            = @merchant
      enrichment.category            = @category
      enrichment.category_overridden = @category.present?
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
      @merchant.update!(default_category: @category) if @category

      # Re-enrich this transaction against the rule set so it tracks the
      # merchant going forward (clears any prior `manual` lock).
      enrichment = @transaction.enrichment || @transaction.build_enrichment
      enrichment.merchant            = @merchant
      enrichment.category            = nil
      enrichment.category_overridden = false
      enrichment.source              = "user_rule"
      enrichment.enriched_at         = Time.current
      enrichment.save!
    end

    def apply_create_rule
      rule = @actor.merchant_rules.create!(
        merchant: @merchant,
        kind: @rule_kind,
        field: @rule_field || "title",
        pattern: @rule_pattern,
        priority: 100,
        source: "user",
        enabled: true,
        approved_at: Time.current,
        approved_by: @actor
      )
      # Optionally update merchant default if user picked a category.
      @merchant.update!(default_category: @category) if @category && @merchant.default_category_id != @category.id

      Enrichment::TransactionEnricher.rebuild!(user: @actor)
      rule
    end

    def label_for_mode(mode)
      { only_this: "tylko tę transakcję", all_for_merchant: "wszystkie z tego sprzedawcy", create_rule: "nowa reguła + przebudowa" }.fetch(mode)
    end

    def success(msg) = Result.new(success: true, message: msg)
    def failure(msg) = Result.new(success: false, message: msg)
  end
end
