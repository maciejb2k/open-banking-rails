# frozen_string_literal: true

Ransack.configure do |c|
  # Convert "0"/"false" to false so unchecked checkboxes don't trigger scopes.
  c.sanitize_custom_scope_booleans = true
end
