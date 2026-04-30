# frozen_string_literal: true

module Admin
  # View helpers for transaction enrichment UI: human labels for source /
  # payment_method enums + matching badge variants.
  #
  # Single source of truth for these labels — controllers, tables, modals,
  # all read from here so changing a label in one place updates everywhere.
  module EnrichmentHelper
    SOURCE_LABELS = {
      "system_rule"     => "Auto",
      "user_rule"       => "Rule",
      "llm_rule"        => "AI",
      "llm_pending"     => "Pending review",
      "manual"          => "Manual",
      "unmatched"       => "Unmatched",
      "system_fallback" => "Fallback"
    }.freeze

    SOURCE_VARIANTS = {
      "system_rule"     => :muted,
      "user_rule"       => :info,
      "llm_rule"        => :default,
      "llm_pending"     => :warning,
      "manual"          => :success,
      "unmatched"       => :muted,
      "system_fallback" => :muted
    }.freeze

    PAYMENT_METHOD_LABELS = {
      "card"               => "Card",
      "card_authorization" => "Card authorization",
      "blik_pos"           => "BLIK at POS",
      "blik_p2p"           => "BLIK to phone",
      "blik_atm"           => "BLIK at ATM",
      "transfer"           => "Transfer",
      "internal_transfer"  => "Internal transfer",
      "topup"              => "Top-up",
      "fee"                => "Fee",
      "other"              => "Other"
    }.freeze

    def enrichment_source_label(source)
      SOURCE_LABELS.fetch(source.to_s, source.to_s.humanize)
    end

    def enrichment_source_badge(source)
      return nil if source.blank?
      render "admin/shared/components/badge",
             text: enrichment_source_label(source),
             variant: SOURCE_VARIANTS.fetch(source.to_s, :muted)
    end

    def payment_method_label(method)
      return nil if method.blank?
      PAYMENT_METHOD_LABELS.fetch(method.to_s, method.to_s.humanize)
    end

    # Choices for select inputs.
    def payment_method_options(include_blank: true)
      opts = BankTransaction::PAYMENT_METHODS.map { |m| [ payment_method_label(m), m ] }
      include_blank ? [ [ "All", "" ] ] + opts : opts
    end

    # Hierarchical select options: top-level groups with sub-categories
    # nested under them (using OptGroups). Excludes archived.
    def category_select_options(selected_id: nil)
      groups = Category.active.top_level.ordered.includes(:children).map do |top|
        children = top.children.where(archived_at: nil).order(:position, :name)
        if children.any?
          [ top.name, [ [ top.name + " (general)", top.id ] ] + children.map { |c| [ c.name, c.id ] } ]
        else
          [ top.name, [ [ top.name, top.id ] ] ]
        end
      end
      grouped_options_for_select(groups, selected_id)
    end
  end
end
