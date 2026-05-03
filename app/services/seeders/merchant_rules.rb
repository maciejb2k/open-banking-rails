# frozen_string_literal: true

module Seeders
  # Idempotent. Depends on Seeders::Categories having run (path lookups).
  module MerchantRules
    # [slug, name, category_path, rule_field, rule_pattern, rule_kind]
    RETAIL = [
      [ "biedronka",      "Biedronka",     "food.cooking.supermarket",         "title",              "BIEDRONKA",       "contains" ],
      [ "lidl",           "Lidl",          "food.cooking.supermarket",         "title",              "LIDL",            "contains" ],
      [ "kaufland",       "Kaufland",      "food.cooking.supermarket",         "title",              "KAUFLAND",        "contains" ],
      [ "auchan",         "Auchan",        "food.cooking.supermarket",         "title",              "AUCHAN",          "contains" ],
      [ "eleclerc",       "eLeclerc",      "food.cooking.supermarket",         "title",              "ELECLERC",        "contains" ],
      [ "zabka",          "Żabka",         "food.cooking.convenience",         "title",              "ZABKA",           "contains" ],
      [ "spolem",         "Społem PSS",    "food.cooking.convenience",         "title",              "SPOLEM",          "contains" ],

      [ "rossmann",       "Rossmann",      "home.variable.drugstore",          "title",              "ROSSMANN",        "contains" ],
      [ "pepco",          "Pepco",         "lifestyle.shopping.general",       "title",              "PEPCO",           "contains" ],
      [ "tedi",           "TEDi",          "lifestyle.shopping.general",       "title",              "TEDI",            "contains" ],

      [ "decathlon",      "Decathlon",     "health.body.fitness",              "title",              "DECATHLON",       "contains" ],
      [ "otcf_4f",        "4F (OTCF)",     "lifestyle.shopping.clothing",      "title",              "OTCF",            "contains" ],

      [ "media_expert",   "Media Expert",  "lifestyle.shopping.electronics",   "title",              "MEDIAEXPERT",     "contains" ],

      [ "doz_apteka",     "DOZ Apteka",    "health.medical.pharmacy",          "title",              "DOZ APTEKA",      "contains" ],

      [ "dara_kebab",     "Dara Kebab",    "food.eating_out.fastfood",         "title",              "DARA KEBAB",      "contains" ],
      [ "doner_king",     "Doner King",    "food.eating_out.fastfood",         "title",              "DONER KING",      "contains" ],
      [ "mcdonalds",      "McDonald's",    "food.eating_out.fastfood",         "title",              "MCDONALD",        "contains" ],

      [ "alcapone",       "Al Capone",     "food.cooking.alcohol",             "title",              "CAPONE",          "contains" ],

      [ "t_mobile",       "T-Mobile",      "home.fixed.telecom",               "title",              "T-MOBILE POLSKA", "contains" ],

      [ "allegropay",     "AllegroPay",    "lifestyle.shopping.general",       "title",              "ALLEGROPAY",      "contains" ],

      [ "claude_ai",      "Claude.ai",     "lifestyle.tools.saas",             "counterparty_name",  "Claude.ai",       "contains" ],
      [ "openai",         "OpenAI",        "lifestyle.tools.saas",             "counterparty_name",  "Openai",          "contains" ],
      [ "anthropic",      "Anthropic",     "lifestyle.tools.saas",             "counterparty_name",  "Anthropic",       "contains" ],
      [ "google_one",     "Google One",    "lifestyle.tools.cloud",            "counterparty_name",  "Google",          "contains" ],
      [ "linkedin",       "LinkedIn",      "lifestyle.tools.saas",             "counterparty_name",  "Linkedin",        "contains" ]
    ].freeze

    def self.call(user)
      cat = ->(path) { user.categories.find_by(path: path) or raise "Missing seeded category at path: #{path}" }
      seed_retail(user, cat)
      seed_atm(user, cat)
      seed_topup(user, cat)
    end

    def self.seed_retail(user, cat)
      RETAIL.each do |slug, name, path, field, pattern, kind|
        merchant = user.merchants.find_or_initialize_by(slug: slug)
        merchant.assign_attributes(
          name: name,
          kind: "company",
          source: "system",
          default_category: cat.call(path),
          approved_at: merchant.approved_at || Time.current
        )
        merchant.save!

        rule = merchant.merchant_rules.find_or_initialize_by(field: field, pattern: pattern)
        rule.assign_attributes(
          user: user,
          kind: kind,
          source: "system",
          enabled: true,
          priority: rule.priority || 0,
          case_sensitive: false
        )
        rule.save!
      end
    end

    # Priority 300 beats retail (0) and own-account-syncer rules (200).
    def self.seed_atm(user, cat)
      atm_merchant = user.merchants.find_or_initialize_by(slug: "atm_withdrawal")
      atm_merchant.assign_attributes(
        name:             "ATM",
        kind:             "other",
        source:           "system",
        default_category: cat.call("money.transfers.atm"),
        approved_at:      atm_merchant.approved_at || Time.current,
        notes:            "Auto-generated. Cash withdrawals from any ATM. " \
                          "Cash::AtmWithdrawalLinker pairs each withdrawal with a " \
                          "topup in the user's cash wallet when track_cash is on."
      )
      atm_merchant.save!

      rule = atm_merchant.merchant_rules.find_or_initialize_by(field: "payment_method", pattern: "blik_atm")
      rule.assign_attributes(
        user: user, kind: "exact", source: "system", enabled: true,
        priority: 300, case_sensitive: false,
        approved_at: rule.approved_at || Time.current
      )
      rule.save!
    end

    # Funding card is the user's own - without this rule, the credit lands
    # in a hallucinated category because LLM/seed rules see "Google" in
    # counterparty data. Priority 250 (above own-account 200, below ATM 300).
    def self.seed_topup(user, cat)
      topup_merchant = user.merchants.find_or_initialize_by(slug: "mobile_wallet_topup")
      topup_merchant.assign_attributes(
        name:             "Top-up (own)",
        kind:             "platform",
        source:           "system",
        default_category: cat.call("money.transfers.own"),
        approved_at:      topup_merchant.approved_at || Time.current,
        notes:            "Auto-generated. Google Pay / Apple Pay top-ups to " \
                          "own balance accounts. Funding card is the user's own - " \
                          "this is a transfer between own surfaces."
      )
      topup_merchant.save!

      [
        [ "title", "Google Pay Top-Up by", "contains" ],
        [ "title", "Apple Pay Top-Up by",  "contains" ],
        [ "title", "Top-Up by *",          "contains" ]
      ].each do |field, pattern, kind|
        rule = topup_merchant.merchant_rules.find_or_initialize_by(field: field, pattern: pattern)
        rule.assign_attributes(
          user: user, kind: kind, source: "system", enabled: true,
          priority: 250, case_sensitive: false,
          approved_at: rule.approved_at || Time.current
        )
        rule.save!
      end
    end
  end
end
