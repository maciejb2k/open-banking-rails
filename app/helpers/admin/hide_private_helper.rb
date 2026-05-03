# frozen_string_literal: true

module Admin
  # Server-side bullet masking - original value never reaches the page, so
  # there's no DevTools / View Source leak (vs the CSS-based privacy_mode).
  module HidePrivateHelper
    DEFAULT_MASK_CAP = 24

    def hide_private?(category_or_id)
      current_user&.hides_category?(category_or_id) || false
    end

    # Pass `mask:` for a fixed replacement (e.g. amounts, where digit count
    # itself leaks magnitude).
    def hide_private_text(value, category_or_id, mask: nil)
      return value unless hide_private?(category_or_id)
      return value if value.blank?
      return mask  if mask
      "•" * [ value.to_s.length, DEFAULT_MASK_CAP ].min
    end
  end
end
