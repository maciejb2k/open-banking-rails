# frozen_string_literal: true

module Admin
  module BaseHelper
    def nav_item_active?(path)
      return false if path.blank? || path == "#"
      return request.path == path if path == admin_root_path
      request.path == path || request.path.start_with?(path + "/")
    end

    # First entry doubles as the default-redirect target for bare /preferences
    # (kept in sync via routes.rb).
    def preferences_sections
      [
        { id: :profile, label: "Profile", icon: "users",
          path: admin_settings_preferences_profile_path,
          desc: "Display name, password." },
        { id: :app,     label: "App",     icon: "sliders_horizontal",
          path: admin_settings_preferences_app_path,
          desc: "Cash tracking, hidden categories." },
        { id: :llm,     label: "LLM",     icon: "sparkles",
          path: admin_settings_preferences_llm_path,
          desc: "AI provider, API key, connection test." },
        { id: :data_exchange, label: "Data exchange", icon: "package",
          path: admin_settings_preferences_data_exchange_path,
          desc: "Export and import bundles between instances." }
      ]
    end

    def admin_nav_sections
      [
        {
          title: "Analytics",
          items: [
            { name: "Dashboard", path: admin_analytics_root_path, icon: "layout_dashboard" }
          ]
        },
        {
          title: "Operations",
          items: [
            { name: "Bank Transactions", path: admin_bank_transactions_path, icon: "dollar_sign" },
            { name: "Cash Transactions", path: admin_cash_transactions_path, icon: "banknote" },
            { name: "Sync Transactions", path: admin_transaction_syncs_path, icon: "refresh_cw" }
          ]
        },
        {
          title: "Classification",
          items: [
            { name: "Merchants", path: admin_merchants_path, icon: "tag" },
            { name: "Categories", path: admin_categories_path, icon: "shopping_cart" },
            { name: "AI Enrichment", path: admin_llm_enrichments_path, icon: "sparkles" },
            { name: "Matching engine", path: admin_matching_engine_path, icon: "search" }
          ]
        },
        {
          title: "Bank Integrations",
          items: [
            { name: "TPP Credentials",  path: admin_tpp_credentials_path,  icon: "file_text" },
            { name: "Bank Connections", path: admin_bank_connections_path, icon: "package" },
            { name: "Bank Accounts",    path: admin_bank_accounts_path,    icon: "dollar_sign" }
          ]
        },
        {
          title: "Settings",
          items: [
            { name: "Preferences", path: admin_settings_preferences_path, icon: "settings" },
            { name: "Audit Log",   path: admin_versions_path,             icon: "shield" }
          ]
        },
        *(Rails.env.development? ? [ {
          title: "Development",
          items: [
            { name: "Styleguide", path: admin_styleguide_path, icon: "settings" },
            { name: "Debug", path: admin_debug_path, icon: "sliders_horizontal" }
          ]
        } ] : [])
      ]
    end

    # Usage in th: <%= sort_link "Name", "name" %>
    def sort_link(label, column)
      current_sort = Array(@q&.sorts).first
      is_active = current_sort&.name == column.to_s
      current_dir = current_sort&.dir || "desc"
      new_dir = (is_active && current_dir == "asc") ? "desc" : "asc"
      q_params = params.fetch(:q, {}).to_unsafe_h.except("s")
      link_params = { q: q_params.merge("s" => "#{column} #{new_dir}") }
      icon_name = is_active ? (current_dir == "asc" ? "arrow_up" : "arrow_down") : "arrow_up_down"
      icon_classes = is_active ? "h-3.5 w-3.5" : "h-3.5 w-3.5 opacity-30"
      link_class = is_active ? "flex items-center gap-1 text-primary font-medium transition-colors" : "flex items-center gap-1 hover:text-foreground transition-colors"
      link_to url_for(link_params), class: link_class do
        safe_join([ label, render("admin/shared/icons/#{icon_name}", classes: icon_classes) ])
      end
    end

    # Returns nil when no svg exists - components fall back to an initials tile.
    def bank_logo_asset_path(slug)
      return nil if slug.blank?
      asset = Rails.application.assets.load_path.find("banks/#{slug}.svg")
      asset ? asset_path("banks/#{slug}.svg") : nil
    end

    def breadcrumb_items
      return @custom_breadcrumbs if @custom_breadcrumbs.present?

      # Trailing edit/new are CRUD actions, not destinations - drop them.
      segments = strip_action_suffix(request.path.split("/").reject(&:empty?))

      nav_labels = { "admin" => { label: "Admin", path: admin_root_path } }
      admin_nav_sections.each do |section|
        section[:items].each do |item|
          next if item[:path].blank? || item[:path] == "#"
          key = strip_action_suffix(item[:path].split("/").reject(&:empty?)).last
          nav_labels[key] = { label: item[:name], path: item[:path] } if key
        end
      end

      segments.each_with_index.map do |seg, i|
        path = "/" + segments[0..i].join("/")

        if numeric_id?(seg) && i.positive?
          label = breadcrumb_label_for_id(parent_segment: segments[i - 1], id: seg) || seg
          { label: label, path: path, sensitive: true }
        else
          item = nav_labels[seg]
          { label: item&.fetch(:label, nil) || seg.humanize, path: item&.fetch(:path, nil) || path }
        end
      end
    end

    # The two LedgerEntry source types have separate admin surfaces.
    def ledger_entry_path(entry)
      if entry.source_type == "BankTransaction"
        admin_bank_transaction_path(entry.source_id)
      else
        admin_cash_transaction_path(entry.source_id)
      end
    end

    def sync_age_label(synced_at)
      return "never" if synced_at.blank?
      diff = Time.current - synced_at
      if    diff < 1.hour   then "#{(diff / 60).to_i}m"
      elsif diff < 24.hours then "#{(diff / 3600).to_i}h"
      else                       "#{(diff / 86400).to_i}d"
      end
    end

    def sync_age_class(synced_at)
      return "text-destructive" if synced_at.blank?
      diff = Time.current - synced_at
      if    diff <= 24.hours then "text-muted-foreground"
      elsif diff <= 7.days   then "text-warning"
      else                        "text-destructive"
      end
    end

    private

    def numeric_id?(segment)
      segment.match?(/\A\d+\z/)
    end

    def strip_action_suffix(segments)
      return segments if segments.empty?
      %w[edit new].include?(segments.last) ? segments[0..-2] : segments
    end

    # Falls back through to_breadcrumb → display_name → name. Returns nil
    # if model can't be inferred or record not found.
    def breadcrumb_label_for_id(parent_segment:, id:)
      klass = parent_segment.singularize.classify.safe_constantize
      return nil unless klass.is_a?(Class) && klass < ApplicationRecord

      record = klass.find_by(id: id)
      return nil unless record

      if record.respond_to?(:to_breadcrumb)
        record.to_breadcrumb.presence
      elsif record.respond_to?(:display_name) && record.display_name.present?
        record.display_name
      elsif record.respond_to?(:name) && record.name.present?
        record.name
      end
    rescue StandardError
      nil
    end
  end
end
