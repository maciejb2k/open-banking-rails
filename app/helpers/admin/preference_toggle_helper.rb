# frozen_string_literal: true

module Admin
  # Cookie-backed boolean preferences paired with the preference-toggle
  # Stimulus controller.
  module PreferenceToggleHelper
    DEFAULT_BUTTON_CLASS = "rounded-lg p-2 text-muted-foreground " \
                           "hover:bg-card-hover hover:text-foreground transition-colors"

    def preference?(name)
      cookies[name].to_s == "1"
    end

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
