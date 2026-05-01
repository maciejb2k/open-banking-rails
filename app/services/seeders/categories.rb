# frozen_string_literal: true

module Seeders
  # Seeds the baseline three-layer category taxonomy for a single user.
  # Idempotent — keyed on (user_id, slug). Re-running updates existing
  # rows in place (name / kind / path / essential), never deletes them
  # (use the UI to archive so historical FKs from transaction_enrichments
  # stay valid).
  #
  # Call sites:
  #   * `db/seeds/categories.rb` (loops every user during db:seed)
  #   * registration / onboarding flow (seed the new user explicitly)
  #   * test factories (when a spec needs the full tree)
  #
  # No model callback wires this up — seeding is an explicit decision
  # made by whoever creates the user.
  module Categories
    SEPARATOR = "."

    PALETTE = {
      "food"      => "emerald",
      "mobility"  => "blue",
      "home"      => "amber",
      "health"    => "rose",
      "lifestyle" => "violet",
      "education" => "indigo",
      "services"  => "slate",
      "income"    => "green",
      "money"     => "gray",
      "noise"     => "zinc"
    }.freeze

    DEFINITIONS = [
      # Top-level domains — name + icon set on roots only; sub-categories
      # inherit color from the domain.
      { path: "food",        name: "Jedzenie",        kind: "expense",  icon: "utensils",       essential: false },
      { path: "mobility",    name: "Mobilność",       kind: "expense",  icon: "car",            essential: false },
      { path: "home",        name: "Mieszkanie",      kind: "expense",  icon: "home",           essential: true  },
      { path: "health",      name: "Zdrowie i ciało", kind: "expense",  icon: "heart",          essential: false },
      { path: "lifestyle",   name: "Lifestyle",       kind: "expense",  icon: "sparkles",       essential: false },
      { path: "education",   name: "Edukacja",        kind: "expense",  icon: "book-open",      essential: false },
      { path: "services",    name: "Usługi i opłaty", kind: "expense",  icon: "briefcase",      essential: true  },
      { path: "income",      name: "Wpływy",          kind: "income",   icon: "trending-up",    essential: false },
      { path: "money",       name: "Ruch pieniędzy",  kind: "transfer", icon: "arrow-right-left", essential: false },
      { path: "noise",       name: "Niesklasyfikowane", kind: "ignored", icon: "help-circle",   essential: false },

      # food.*
      { path: "food.cooking",                name: "W domu",                 kind: "expense", essential: true  },
      { path: "food.cooking.supermarket",    name: "Supermarkety",           kind: "expense", essential: true  },
      { path: "food.cooking.convenience",    name: "Sklepy osiedlowe",       kind: "expense", essential: true  },
      { path: "food.cooking.bakery",         name: "Piekarnie i cukiernie",  kind: "expense", essential: true  },
      { path: "food.cooking.specialty",      name: "Sklepy specjalistyczne", kind: "expense", essential: false },
      { path: "food.cooking.alcohol",        name: "Alkohol (do domu)",      kind: "expense", essential: false },

      { path: "food.eating_out",             name: "Na mieście",             kind: "expense", essential: false },
      { path: "food.eating_out.restaurant",  name: "Restauracje",            kind: "expense", essential: false },
      { path: "food.eating_out.fastfood",    name: "Fast food / kebab",      kind: "expense", essential: false },
      { path: "food.eating_out.cafe",        name: "Kawiarnie",              kind: "expense", essential: false },
      { path: "food.eating_out.delivery",    name: "Dostawa jedzenia",       kind: "expense", essential: false },
      { path: "food.eating_out.bar",         name: "Bar / pub / klub",       kind: "expense", essential: false },

      # mobility.*
      { path: "mobility.daily",              name: "Codzienne",              kind: "expense", essential: true  },
      { path: "mobility.daily.transit",      name: "Komunikacja miejska",    kind: "expense", essential: true  },
      { path: "mobility.daily.rideshare",    name: "Taxi / Bolt / Uber",     kind: "expense", essential: false },
      { path: "mobility.daily.parking",      name: "Parkingi",               kind: "expense", essential: false },

      { path: "mobility.car",                name: "Auto",                   kind: "expense", essential: true  },
      { path: "mobility.car.fuel",           name: "Paliwo",                 kind: "expense", essential: true  },
      { path: "mobility.car.service",        name: "Serwis i mycie",         kind: "expense", essential: false },
      { path: "mobility.car.tolls",          name: "Opłaty drogowe",         kind: "expense", essential: false },

      { path: "mobility.travel",             name: "Podróże",                kind: "expense", essential: false },
      { path: "mobility.travel.flights",     name: "Loty",                   kind: "expense", essential: false },
      { path: "mobility.travel.lodging",     name: "Noclegi",                kind: "expense", essential: false },
      { path: "mobility.travel.longdistance", name: "PKP / autobus",         kind: "expense", essential: false },

      # home.*
      { path: "home.fixed",                  name: "Stałe",                  kind: "expense", essential: true  },
      { path: "home.fixed.rent",             name: "Czynsz / kredyt",        kind: "expense", essential: true  },
      { path: "home.fixed.utilities",        name: "Media (prąd / gaz)",     kind: "expense", essential: true  },
      { path: "home.fixed.telecom",          name: "Internet / telefon",     kind: "expense", essential: true  },

      { path: "home.variable",               name: "Zmienne",                kind: "expense", essential: false },
      { path: "home.variable.drugstore",     name: "Drogerie",               kind: "expense", essential: true  },
      { path: "home.variable.goods",         name: "Wyposażenie",            kind: "expense", essential: false },
      { path: "home.variable.maintenance",   name: "Konserwacja i remonty", kind: "expense", essential: false },

      # health.*
      { path: "health.medical",              name: "Medyczne",               kind: "expense", essential: true  },
      { path: "health.medical.pharmacy",     name: "Apteki",                 kind: "expense", essential: true  },
      { path: "health.medical.doctor",       name: "Lekarze",                kind: "expense", essential: true  },
      { path: "health.medical.dentist",      name: "Stomatolog",             kind: "expense", essential: false },
      { path: "health.medical.optician",     name: "Optyk",                  kind: "expense", essential: false },

      { path: "health.body",                 name: "Ciało",                  kind: "expense", essential: false },
      { path: "health.body.haircut",         name: "Fryzjer",                kind: "expense", essential: false },
      { path: "health.body.beauty",          name: "Kosmetyk",               kind: "expense", essential: false },
      { path: "health.body.fitness",         name: "Sport i siłownia",       kind: "expense", essential: false },

      # lifestyle.*
      { path: "lifestyle.entertainment",            name: "Rozrywka",              kind: "expense", essential: false },
      { path: "lifestyle.entertainment.streaming",  name: "Streaming",             kind: "expense", essential: false },
      { path: "lifestyle.entertainment.events",     name: "Bilety i wydarzenia",   kind: "expense", essential: false },
      { path: "lifestyle.entertainment.games",      name: "Gry",                   kind: "expense", essential: false },
      { path: "lifestyle.entertainment.hobbies",    name: "Hobby",                 kind: "expense", essential: false },

      { path: "lifestyle.shopping",                 name: "Zakupy",                kind: "expense", essential: false },
      { path: "lifestyle.shopping.clothing",        name: "Ubrania i obuwie",      kind: "expense", essential: false },
      { path: "lifestyle.shopping.electronics",     name: "Elektronika",           kind: "expense", essential: false },
      { path: "lifestyle.shopping.general",         name: "Inne sklepy",           kind: "expense", essential: false },

      { path: "lifestyle.tools",                    name: "Narzędzia cyfrowe",     kind: "expense", essential: false },
      { path: "lifestyle.tools.saas",               name: "SaaS / AI",             kind: "expense", essential: false },
      { path: "lifestyle.tools.cloud",              name: "Chmura / dyski",        kind: "expense", essential: false },
      { path: "lifestyle.tools.media",              name: "Media i prasa",         kind: "expense", essential: false },

      { path: "lifestyle.giving",                   name: "Prezenty i darowizny",  kind: "expense", essential: false },
      { path: "lifestyle.giving.gifts",             name: "Prezenty",              kind: "expense", essential: false },
      { path: "lifestyle.giving.donations",         name: "Darowizny",             kind: "expense", essential: false },

      # education.*
      { path: "education.courses",  name: "Kursy i szkolenia", kind: "expense", essential: false },
      { path: "education.books",    name: "Książki",           kind: "expense", essential: false },
      { path: "education.tuition",  name: "Studia / czesne",   kind: "expense", essential: false },

      # services.*
      { path: "services.financial",            name: "Finansowe",             kind: "expense", essential: true  },
      { path: "services.financial.fees",       name: "Prowizje bankowe",      kind: "expense", essential: true  },
      { path: "services.financial.fx_markup",  name: "Spread walutowy",       kind: "expense", essential: false },

      { path: "services.taxes",                name: "Podatki",               kind: "expense", essential: true  },
      { path: "services.taxes.income_tax",     name: "PIT",                   kind: "expense", essential: true  },
      { path: "services.taxes.property_tax",   name: "Podatek od nieruchomości", kind: "expense", essential: true  },

      { path: "services.insurance",            name: "Ubezpieczenia",         kind: "expense", essential: true  },
      { path: "services.insurance.life",       name: "Na życie",              kind: "expense", essential: false },
      { path: "services.insurance.property",   name: "Mieszkania",            kind: "expense", essential: true  },
      { path: "services.insurance.liability",  name: "OC / AC",               kind: "expense", essential: true  },

      { path: "services.professional",         name: "Profesjonalne",         kind: "expense", essential: false },
      { path: "services.professional.legal",   name: "Prawne",                kind: "expense", essential: false },
      { path: "services.professional.accounting", name: "Księgowość",         kind: "expense", essential: false },

      # income.*
      { path: "income.work",            name: "Praca",            kind: "income", essential: false },
      { path: "income.work.salary",     name: "Wynagrodzenie",    kind: "income", essential: false },
      { path: "income.work.bonus",      name: "Premie",           kind: "income", essential: false },
      { path: "income.work.freelance",  name: "Freelance / B2B",  kind: "income", essential: false },

      { path: "income.passive",         name: "Pasywne",          kind: "income", essential: false },
      { path: "income.passive.interest", name: "Odsetki",         kind: "income", essential: false },
      { path: "income.passive.dividends", name: "Dywidendy",      kind: "income", essential: false },
      { path: "income.passive.rent_in", name: "Najem",            kind: "income", essential: false },

      { path: "income.refunds",         name: "Zwroty i cashback", kind: "income", essential: false },
      { path: "income.refunds.refunds", name: "Zwroty",            kind: "income", essential: false },
      { path: "income.refunds.cashback", name: "Cashback",         kind: "income", essential: false },

      { path: "income.other",           name: "Inne wpływy",       kind: "income", essential: false },
      { path: "income.other.sale",      name: "Sprzedaż rzeczy",   kind: "income", essential: false },
      { path: "income.other.gifts_in",  name: "Otrzymane prezenty", kind: "income", essential: false },

      # money.* (transfer/savings)
      { path: "money.transfers",            name: "Przelewy",         kind: "transfer", essential: false },
      { path: "money.transfers.own",        name: "Własne konta",     kind: "transfer", essential: false },
      { path: "money.transfers.private",    name: "Prywatne BLIK / przelewy", kind: "transfer", essential: false },
      { path: "money.transfers.atm",        name: "Bankomat",         kind: "transfer", essential: false },

      { path: "money.savings",              name: "Oszczędności",     kind: "savings",  essential: false },
      { path: "money.savings.account",      name: "Konto oszczędnościowe", kind: "savings", essential: false },
      { path: "money.savings.deposit",      name: "Lokaty",           kind: "savings",  essential: false },

      { path: "money.investments",          name: "Inwestycje",       kind: "savings",  essential: false },
      { path: "money.investments.brokerage", name: "Brokerski",       kind: "savings",  essential: false },
      { path: "money.investments.etf",      name: "ETF / fundusze",   kind: "savings",  essential: false },
      { path: "money.investments.crypto",   name: "Krypto",           kind: "savings",  essential: false },

      # noise.* — buckets for transactions without a merchant signal.
      #
      # `noise.unmatched.*` leaves are kind=expense — these are REAL
      # spend, just without a known merchant. They count toward Spend
      # totals so the bottom-line "ile wydałem" stays honest. The UI
      # surfaces them with a badge for review queue.
      #
      # `noise.authorizations.*` and `noise.adjustments.*` stay
      # kind=ignored — those are non-real (preauth that gets reversed,
      # reconciliation corrections) and shouldn't pollute totals.
      { path: "noise.unmatched",         name: "Bez sklepu",            kind: "expense", essential: false },
      { path: "noise.unmatched.blik",    name: "BLIK POS bez nazwy",    kind: "expense", essential: false },
      { path: "noise.unmatched.card",    name: "Karta bez sklepu",      kind: "expense", essential: false },
      { path: "noise.unmatched.cash",    name: "Gotówka bez kontekstu", kind: "expense", essential: false },
      { path: "noise.unmatched.other",   name: "Inne",                  kind: "expense", essential: false },

      { path: "noise.authorizations",    name: "Autoryzacje",           kind: "ignored", essential: false },
      { path: "noise.authorizations.card", name: "Autoryzacje karty",   kind: "ignored", essential: false },

      { path: "noise.adjustments",       name: "Korekty",               kind: "ignored", essential: false },
      { path: "noise.adjustments.cash",  name: "Korekta gotówki",       kind: "ignored", essential: false },
      { path: "noise.adjustments.fx",    name: "Korekta walutowa",      kind: "ignored", essential: false }
    ].freeze

    def self.call(user)
      DEFINITIONS.each_with_index do |attrs, index|
        path   = attrs.fetch(:path)
        slug   = path.tr(SEPARATOR, "_")
        domain = path.split(SEPARATOR).first
        record = user.categories.find_or_initialize_by(slug: slug)
        record.assign_attributes(
          name:      attrs[:name],
          kind:      attrs[:kind],
          color:     attrs[:color] || PALETTE[domain],
          icon:      attrs[:icon],
          essential: attrs.fetch(:essential, false),
          path:      path,
          position:  index
        )
        record.save!
      end
    end
  end
end
