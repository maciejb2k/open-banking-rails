# frozen_string_literal: true

module Admin
  # Helpers for cookie-backed boolean preferences (privacy mode, dark mode, etc.)
  # paired with the `preference-toggle` Stimulus controller.
  #
  # Read state:        preference?("dark_mode")
  # Render a button:   preference_toggle_button "dark_mode", class_name: "dark",
  #                      icon_off: "sun", icon_on: "moon",
  #                      title: "Toggle dark mode"
  module PreferenceToggleHelper
    DEFAULT_BUTTON_CLASS = "rounded-lg p-2 text-muted-foreground " \
                           "hover:bg-card-hover hover:text-foreground transition-colors"

    def preference?(name)
      cookies[name].to_s == "1"
    end

    # Render an icon button wired to the preference-toggle Stimulus controller.
    #
    #   name        - cookie name (e.g. "privacy_mode")
    #   class_name  - CSS class to flip on the scope element (e.g. "privacy-mode")
    #   icon_off    - admin/shared/icons partial name shown when preference is OFF
    #   icon_on     - admin/shared/icons partial name shown when preference is ON
    #   scope       - CSS selector for scope element (default ":root" = <html>)
    #   title       - tooltip text
    #   button_class- override the wrapper button class
    def preference_toggle_button(name, class_name:, icon_off:, icon_on: nil, scope: ":root", title: nil, button_class: nil)
      icon_on ||= icon_off
      active   = preference?(name)

      content_tag :button,
                  type: "button",
                  title: title,
                  "aria-pressed": active.to_s,
                  class: button_class || DEFAULT_BUTTON_CLASS,
                  data: {
                    controller: "preference-toggle",
                    action: "click->preference-toggle#toggle",
                    preference_toggle_name_value:  name,
                    preference_toggle_class_value: class_name,
                    preference_toggle_scope_value: scope
                  } do
        safe_join([
          content_tag(:span, render("admin/shared/icons/#{icon_off}", classes: "h-5 w-5"),
                      "data-preference-toggle-target": "iconOff",
                      class: ("hidden" if active)),
          content_tag(:span, render("admin/shared/icons/#{icon_on}", classes: "h-5 w-5"),
                      "data-preference-toggle-target": "iconOn",
                      class: ("hidden" unless active))
        ])
      end
    end
  end
end
