# frozen_string_literal: true

# Money / money-rails configuration.
#
# Storage convention: every monetized field stores a *_cents bigint and reads
# the currency from a sibling string column (ISO 4217), so a row's
# (amount_cents, currency) pair is always self-describing — no implicit
# default-currency leakage on read.

MoneyRails.configure do |config|
  # Default currency — used by Money.new when no currency is supplied (e.g.
  # in views that build a Money from a raw payload without a model).
  config.default_currency = :pln

  # Bank balances and transactions can be negative — we never want
  # accidental wraparound.
  config.no_cents_if_whole = false

  # Format follows the user's locale where possible (sets thousands /
  # decimal separators per Money::Currency definition).
  config.locale_backend = :i18n
end
