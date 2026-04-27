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
          title: "Audit",
          items: [
            { name: "Audit Log", path: admin_versions_path, icon: "shield" }
          ]
        },
        {
          title: "Settings",
          items: [
            { name: "Styleguide", path: admin_styleguide_path, icon: "settings" }
          ]
        },
        *(Rails.env.development? ? [ {
          title: "Development",
          items: [
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
        item = nav_labels[seg]
        { label: item&.fetch(:label, nil) || seg.humanize, path: item&.fetch(:path, nil) || path }
      end
    end
  end
end
