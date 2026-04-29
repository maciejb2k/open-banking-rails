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

Rails.logger.info "Seeded #{Merchant.where(source: 'system').count} system merchants, #{MerchantRule.where(source: 'system').count} system rules"
