# frozen_string_literal: true

# Seed categories — top-level groups + sub-categories. Idempotent: keyed by
# slug. Renaming `name` here updates existing rows; deleting an entry does
# NOT remove the row (we soft-delete via UI to preserve historical refs).
#
# `kind` partitioning is intentional:
#   expense   — counts toward "ile wydałem"
#   income    — wynagrodzenia, zwroty, refundacje
#   transfer  — przelewy między własnymi kontami (excluded from spend)
#   savings   — przelewy na konto oszczędnościowe (osobny bucket od expense)
#   ignored   — autoryzacje karty, duplikaty (hidden from analytics)

CATEGORIES = [
  # Top-level groups (parent_slug: nil)
  { slug: "groceries",       name: "Zakupy spożywcze",      kind: "expense",  color: "emerald", icon: "shopping-cart" },
  { slug: "dining",          name: "Jedzenie na mieście",   kind: "expense",  color: "orange",  icon: "utensils" },
  { slug: "transport",       name: "Transport",             kind: "expense",  color: "blue",    icon: "car" },
  { slug: "household",       name: "Dom i chemia",          kind: "expense",  color: "amber",   icon: "home" },
  { slug: "health",          name: "Zdrowie",               kind: "expense",  color: "rose",    icon: "heart" },
  { slug: "entertainment",   name: "Rozrywka",              kind: "expense",  color: "violet",  icon: "film" },
  { slug: "subscriptions",   name: "Subskrypcje",           kind: "expense",  color: "indigo",  icon: "repeat" },
  { slug: "shopping",        name: "Zakupy (inne)",         kind: "expense",  color: "pink",    icon: "shopping-bag" },
  { slug: "fees",            name: "Opłaty i prowizje",     kind: "expense",  color: "slate",   icon: "receipt" },
  { slug: "gifts_donations", name: "Prezenty i darowizny",  kind: "expense",  color: "fuchsia", icon: "gift" },
  { slug: "income",          name: "Wpływy",                kind: "income",   color: "green",   icon: "trending-up" },
  { slug: "transfers",       name: "Przelewy własne",       kind: "transfer", color: "gray",    icon: "arrow-right-left" },
  { slug: "savings",         name: "Oszczędności",          kind: "savings",  color: "teal",    icon: "piggy-bank" },
  { slug: "uncategorized",   name: "Nieprzypisane",         kind: "expense",  color: "zinc",    icon: "help-circle" },

  # Payment-method fallbacks: assigned by TransactionEnricher when no
  # MerchantRule matches but the transaction's payment_method maps to a
  # generic bucket (e.g. BLIK POS without merchant info from the bank).
  { slug: "blik_pos_unmatched",  name: "BLIK POS (bez sklepu)",     kind: "expense",  color: "amber",  icon: "credit-card" },
  { slug: "blik_atm_withdrawal", name: "Wypłaty z bankomatu",       kind: "expense",  color: "stone",  icon: "banknote" },
  { slug: "card_authorization",  name: "Autoryzacje karty",         kind: "ignored",  color: "zinc",   icon: "shield" },
  { slug: "card_unmatched",      name: "Płatność kartą (inne)",     kind: "expense",  color: "neutral", icon: "credit-card" },
  { slug: "private_transfers",   name: "Przelewy prywatne",         kind: "transfer", color: "sky",     icon: "users" },

  # Sub-categories under groceries
  { slug: "supermarkets",       name: "Supermarkety",          kind: "expense", parent_slug: "groceries" },
  { slug: "convenience_stores", name: "Sklepy osiedlowe",      kind: "expense", parent_slug: "groceries" },
  { slug: "bakery",             name: "Piekarnie i cukiernie", kind: "expense", parent_slug: "groceries" },
  { slug: "specialty_food",     name: "Sklepy specjalistyczne", kind: "expense", parent_slug: "groceries" },

  # Sub-categories under dining
  { slug: "restaurants",  name: "Restauracje",        kind: "expense", parent_slug: "dining" },
  { slug: "fast_food",    name: "Fast food / kebab",  kind: "expense", parent_slug: "dining" },
  { slug: "cafe",         name: "Kawiarnie",          kind: "expense", parent_slug: "dining" },
  { slug: "delivery",     name: "Dostawa jedzenia",   kind: "expense", parent_slug: "dining" },

  # Sub-categories under transport
  { slug: "fuel",          name: "Paliwo",              kind: "expense", parent_slug: "transport" },
  { slug: "public_transit", name: "Komunikacja miejska", kind: "expense", parent_slug: "transport" },
  { slug: "taxi_rideshare", name: "Taxi / Bolt / Uber",  kind: "expense", parent_slug: "transport" },
  { slug: "car_service",    name: "Serwis i mycie auta", kind: "expense", parent_slug: "transport" },
  { slug: "parking_tolls",  name: "Parkingi i opłaty",   kind: "expense", parent_slug: "transport" },

  # Sub-categories under household
  { slug: "drugstore",       name: "Drogerie",          kind: "expense", parent_slug: "household" },
  { slug: "home_goods",      name: "Wyposażenie domu",  kind: "expense", parent_slug: "household" },
  { slug: "utilities",       name: "Media (prąd/gaz)",  kind: "expense", parent_slug: "household" },
  { slug: "rent_mortgage",   name: "Czynsz / kredyt",   kind: "expense", parent_slug: "household" },
  { slug: "telecom",         name: "Internet / telefon", kind: "expense", parent_slug: "household" },

  # Sub-categories under health
  { slug: "pharmacy",   name: "Apteki",          kind: "expense", parent_slug: "health" },
  { slug: "doctor",     name: "Lekarze",         kind: "expense", parent_slug: "health" },
  { slug: "dentist",    name: "Stomatolog",      kind: "expense", parent_slug: "health" },
  { slug: "optician",   name: "Optyk",           kind: "expense", parent_slug: "health" },

  # Sub-categories under entertainment
  { slug: "streaming",   name: "Streaming",         kind: "expense", parent_slug: "entertainment" },
  { slug: "events",      name: "Bilety i wydarzenia", kind: "expense", parent_slug: "entertainment" },
  { slug: "games",       name: "Gry",               kind: "expense", parent_slug: "entertainment" },
  { slug: "hobbies",     name: "Hobby",             kind: "expense", parent_slug: "entertainment" },
  { slug: "sports",      name: "Sport i fitness",   kind: "expense", parent_slug: "entertainment" },

  # Sub-categories under subscriptions
  { slug: "saas_ai",        name: "AI / SaaS",        kind: "expense", parent_slug: "subscriptions" },
  { slug: "cloud_storage",  name: "Chmura / dyski",   kind: "expense", parent_slug: "subscriptions" },
  { slug: "media_subs",     name: "Media i prasa",    kind: "expense", parent_slug: "subscriptions" },

  # Sub-categories under shopping
  { slug: "clothing",         name: "Ubrania i obuwie", kind: "expense", parent_slug: "shopping" },
  { slug: "electronics",      name: "Elektronika",      kind: "expense", parent_slug: "shopping" },
  { slug: "general_merchandise", name: "Inne sklepy",   kind: "expense", parent_slug: "shopping" }
].freeze

# Build top-level first, then sub-categories so parent_id resolves.
top_level, children = CATEGORIES.partition { |c| c[:parent_slug].nil? }

[ top_level, children ].each do |group|
  group.each_with_index do |attrs, index|
    parent = attrs[:parent_slug] && Category.find_by(slug: attrs[:parent_slug])
    record = Category.find_or_initialize_by(slug: attrs[:slug])
    record.assign_attributes(
      name: attrs[:name],
      kind: attrs[:kind],
      color: attrs[:color],
      icon: attrs[:icon],
      parent_id: parent&.id,
      position: index
    )
    record.save!
  end
end

Rails.logger.info "Seeded #{Category.count} categories (#{Category.top_level.count} top-level)"
