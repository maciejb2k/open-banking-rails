# frozen_string_literal: true

# Baseline system-source merchant rules for Polish/EU merchants commonly seen
# in card transactions. Idempotent: keyed by merchant slug + rule pattern.
#
# This is the minimal set to validate the enricher end-to-end. Phase 2 will
# expand it via the admin UI; Phase 3 grows it automatically through LLM
# proposals. User-source rules always beat these — system seeds are just a
# starting baseline.

cat = ->(slug) { Category.find_by(slug: slug) }

DEFINITIONS = [
  # slug,            display_name,         category_slug,           field,                pattern,           kind
  [ "biedronka",      "Biedronka",          "supermarkets",          "title",              "BIEDRONKA",       "contains" ],
  [ "lidl",           "Lidl",               "supermarkets",          "title",              "LIDL",            "contains" ],
  [ "kaufland",       "Kaufland",           "supermarkets",          "title",              "KAUFLAND",        "contains" ],
  [ "auchan",         "Auchan",             "supermarkets",          "title",              "AUCHAN",          "contains" ],
  [ "eleclerc",       "eLeclerc",           "supermarkets",          "title",              "ELECLERC",        "contains" ],
  [ "zabka",          "Żabka",              "convenience_stores",    "title",              "ZABKA",           "contains" ],
  [ "spolem",         "Społem PSS",         "convenience_stores",    "title",              "SPOLEM",          "contains" ],

  [ "rossmann",       "Rossmann",           "drugstore",             "title",              "ROSSMANN",        "contains" ],
  [ "pepco",          "Pepco",              "general_merchandise",   "title",              "PEPCO",           "contains" ],
  [ "tedi",           "TEDi",               "general_merchandise",   "title",              "TEDI",            "contains" ],

  [ "decathlon",      "Decathlon",          "sports",                "title",              "DECATHLON",       "contains" ],
  [ "otcf_4f",        "4F (OTCF)",          "clothing",              "title",              "OTCF",            "contains" ],

  [ "media_expert",   "Media Expert",       "electronics",           "title",              "MEDIAEXPERT",     "contains" ],

  [ "doz_apteka",     "DOZ Apteka",         "pharmacy",              "title",              "DOZ APTEKA",      "contains" ],

  [ "dara_kebab",     "Dara Kebab",         "fast_food",             "title",              "DARA KEBAB",      "contains" ],
  [ "doner_king",     "Doner King",         "fast_food",             "title",              "DONER KING",      "contains" ],
  [ "mcdonalds",      "McDonald's",         "fast_food",             "title",              "MCDONALD",        "contains" ],

  [ "t_mobile",       "T-Mobile",           "telecom",               "title",              "T-MOBILE POLSKA", "contains" ],

  [ "allegropay",     "AllegroPay",         "shopping",              "title",              "ALLEGROPAY",      "contains" ],

  # Card-on-file SaaS — counterparty_name is set, type_hint is empty.
  [ "claude_ai",      "Claude.ai",          "saas_ai",               "counterparty_name",  "Claude.ai",       "contains" ],
  [ "openai",         "OpenAI",             "saas_ai",               "counterparty_name",  "Openai",          "contains" ],
  [ "anthropic",      "Anthropic",          "saas_ai",               "counterparty_name",  "Anthropic",       "contains" ],
  [ "google_one",     "Google One",         "cloud_storage",         "counterparty_name",  "Google",          "contains" ],
  [ "linkedin",       "LinkedIn",           "saas_ai",               "counterparty_name",  "Linkedin",        "contains" ]
].freeze

DEFINITIONS.each do |slug, display_name, category_slug, field, pattern, kind|
  category = cat.call(category_slug) or raise "Missing seeded category: #{category_slug}"

  merchant = Merchant.find_or_initialize_by(slug: slug)
  merchant.assign_attributes(
    name: display_name,
    display_name: display_name,
    kind: "company",
    source: "system",
    default_category: category,
    approved_at: merchant.approved_at || Time.current
  )
  merchant.save!

  rule = MerchantRule.find_or_initialize_by(merchant: merchant, field: field, pattern: pattern)
  rule.assign_attributes(
    kind: kind,
    source: "system",
    enabled: true,
    priority: rule.priority || 0,
    case_sensitive: false
  )
  rule.save!
end

# ATM withdrawal — special-case system merchant. Withdrawing cash is a
# *location change* (account → wallet), not a spend, so the default
# category is `transfers` (kind: transfer) and the row falls out of spend
# analytics. Phase 3's Cash::AtmWithdrawalLinker pairs it with a manual
# topup for users who opted into cash tracking.
#
# Priority 300 beats both the retail rules above (priority 0) and the
# OwnAccountMerchantSyncer rules (priority 200), so an ATM withdrawal
# can never be misclassified as a regular merchant or own-account transfer.
ATM_RULES = [
  # payment_method is normalized upstream by PaymentMethodInferer (PKO
  # type_hint MOBILE-PAYMENT-ATM-*, Berlin Group ATM/WTHD codes all collapse
  # here). One rule, every bank.
  [ "payment_method", "blik_atm", "exact" ]
].freeze

atm_merchant = Merchant.find_or_initialize_by(slug: "atm_withdrawal")
atm_merchant.assign_attributes(
  name:             "ATM (cash withdrawal)",
  display_name:     "ATM",
  kind:             "other",
  source:           "system",
  default_category: cat.call("transfers"),
  approved_at:      atm_merchant.approved_at || Time.current,
  notes:            "Auto-generated. Cash withdrawals from any ATM. " \
                    "Cash::AtmWithdrawalLinker pairs each withdrawal with a " \
                    "topup in the user's cash wallet when track_cash is on."
)
atm_merchant.save!

ATM_RULES.each do |field, pattern, kind|
  rule = MerchantRule.find_or_initialize_by(merchant: atm_merchant, field: field, pattern: pattern)
  rule.assign_attributes(
    kind:           kind,
    source:         "system",
    enabled:        true,
    priority:       300,
    case_sensitive: false,
    approved_at:    rule.approved_at || Time.current
  )
  rule.save!
end

Rails.logger.info "Seeded #{Merchant.where(source: 'system').count} system merchants, #{MerchantRule.where(source: 'system').count} system rules"
