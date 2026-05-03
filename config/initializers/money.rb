# frozen_string_literal: true

# Storage: every monetized field is *_cents bigint with currency in a sibling
# column (ISO 4217), so each (amount_cents, currency) pair is self-describing.

MoneyRails.configure do |config|
  config.default_currency = :pln
  config.no_cents_if_whole = false
  config.locale_backend = :i18n
end
