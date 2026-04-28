# frozen_string_literal: true

module Admin
  module BaseHelper
    def nav_item_active?(path)
      return false if path.blank? || path == "#"
      return request.path == path if path == admin_root_path
      request.path == path || request.path.start_with?(path + "/")
    end

    def admin_nav_sections
      [
        {
          title: "Operations",
          items: [
            { name: "Dashboard", path: admin_root_path, icon: "layout_dashboard" }
          ]
        },
        {
          title: "Settings",
          items: [
            { name: "TPP Credentials", path: admin_settings_tpp_credentials_path, icon: "file_text" },
            { name: "Bank Connections", path: admin_settings_bank_connections_path, icon: "package" },
            { name: "Bank Accounts", path: admin_settings_bank_accounts_path, icon: "dollar_sign" },
            { name: "Audit Log", path: admin_versions_path, icon: "shield" }
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

    # Renders a sortable column header link with an arrow icon.
    # Reads current sort state from @q (Ransack search object set in controller).
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

    def breadcrumb_items
      segments = request.path.split("/").reject(&:empty?)

      nav_labels = { "admin" => { label: "Admin", path: admin_root_path } }
      admin_nav_sections.each do |section|
        section[:items].each do |item|
          next if item[:path].blank? || item[:path] == "#"
          segment = item[:path].split("/").reject(&:empty?).last
          nav_labels[segment] = { label: item[:name], path: item[:path] } if segment
        end
      end

      segments.each_with_index.map do |seg, i|
        path = "/" + segments[0..i].join("/")

        if numeric_id?(seg) && i.positive?
          label = breadcrumb_label_for_id(parent_segment: segments[i - 1], id: seg) || seg
          { label: label, path: path }
        else
          item = nav_labels[seg]
          { label: item&.fetch(:label, nil) || seg.humanize, path: item&.fetch(:path, nil) || path }
        end
      end
    end

    private

    def numeric_id?(segment)
      segment.match?(/\A\d+\z/)
    end

    # Resolve `/.../tpp_credentials/1` → "Personal Enable Banking"
    # by looking up the record and falling back through:
    #   to_breadcrumb → display_name → name → id
    # Returns nil if model can't be inferred or record not found.
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
