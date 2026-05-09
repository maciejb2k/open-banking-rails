# frozen_string_literal: true

module Admin
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
             label: enrichment_source_label(source),
             variant: SOURCE_VARIANTS.fetch(source.to_s, :muted)
    end

    def payment_method_label(method)
      return nil if method.blank?
      PAYMENT_METHOD_LABELS.fetch(method.to_s, method.to_s.humanize)
    end

    def payment_method_options(include_blank: true)
      opts = BankTransaction::PAYMENT_METHODS.map { |m| [ payment_method_label(m), m ] }
      include_blank ? [ [ "All", "" ] ] + opts : opts
    end

    # Full-breadcrumb labels so leaves are unambiguous; indented by depth.
    def category_select_options(selected_id: nil)
      pairs = current_user.categories.active.ordered.map do |c|
        indent = "-" * c.path.to_s.count(".")
        [ "#{indent} #{c.breadcrumb_names.join(' / ')}".strip, c.id ]
      end
      options_for_select(pairs, selected_id)
    end
  end
end
