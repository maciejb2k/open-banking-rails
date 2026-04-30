# frozen_string_literal: true

module Admin
  # Always-on bullet masking for transactions in user-marked private
  # categories (see User#hidden_categories, set in
  # /admin/settings/preferences). Independent of the topbar privacy_mode
  # cookie — that one masks all `.sensitive` UI for screen-share; this
  # one renders bullets server-side for specific categories regardless of
  # toggle state.
  #
  # Server-side rather than CSS-based because the existing `.sensitive`
  # mechanism gates on `html.privacy-mode` — using it here would require
  # privacy_mode to be on, which the user explicitly didn't want. Bullets
  # in the rendered HTML mean the original value never reaches the page,
  # which is also stricter (no DevTools / View Source leak).
  #
  #   <%= hide_private_text(tx.title, tx.effective_category) %>
  #   <%= hide_private_text(tx.amount.format, tx.effective_category, mask: "•••") %>
  module HidePrivateHelper
    DEFAULT_MASK_CAP = 24

    def hide_private?(category_or_id)
      current_user&.hides_category?(category_or_id) || false
    end

    # Returns value as-is when not hidden; bullets matching the value's
    # length when hidden (capped so wide labels don't break layout).
    # Pass `mask:` for a fixed replacement (e.g. amounts where the digit
    # count itself leaks magnitude).
    def hide_private_text(value, category_or_id, mask: nil)
      return value unless hide_private?(category_or_id)
      return value if value.blank?
      return mask  if mask
      "•" * [ value.to_s.length, DEFAULT_MASK_CAP ].min
    end
  end
end
