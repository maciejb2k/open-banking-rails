# AGENTS.md

Guide for agents working on this codebase. Add a new section per area as
conventions emerge — don't pad sections with content that isn't established
yet.

## Admin UI

Read before touching `app/views/admin/`. Goal: keep the panel consistent and
the component library from rotting into one-off divs.

### Source of truth

**`/admin/styleguide`** (`admin_styleguide_path`) renders every reusable
component with its variants. Read it before writing markup. Each partial's
API is in its first line as `<%# locals: (...) %>` — that's the signature.

```
app/views/admin/shared/
  components/   reusable UI primitives
  form/         form field wrappers
  icons/        inline SVGs (one per file)
```

Useful helpers live in `app/helpers/admin/` (`sort_link`, `sensitive*`,
`admin_nav_sections`). CSS utilities in `app/assets/tailwind/application.css`:
`.admin-section`, `.admin-card`, `.form-input`.

### Reference views

When in doubt, copy the shape of these:

- **Index** (filters + sortable table + pagination) — `bank_transactions/index.html.erb`
- **Show** (header + actions + cards + definition list) — `settings/bank_connections/show.html.erb`
- **Form** (new/edit) — `settings/tpp_credentials/_form.html.erb`
- **Auth** (centered, full-width submit) — `sessions/new.html.erb`

### Rules

1. **Read the styleguide first.** If the thing exists as a component, use it.
   Don't render markup that has a component (buttons, badges, cards, tables,
   form fields, callouts, filter chips/triggers, dropdown menus).
2. **Don't copy Tailwind class strings.** If you'd write the same 8+ class
   string twice, use an existing utility (`.form-input`, `.admin-section`) or
   extract a partial.
3. **Use the design tokens.** Colors via `bg-primary/10`, `text-destructive`
   etc. — never raw hex. Spacing/radii from the existing scale.
4. **Sensitive data must be wrapped.** IBANs, amounts, names, raw payloads,
   secrets — wrap in `sensitive(value)` / `sensitive_class` / `sensitive: true`
   prop. See `app/helpers/admin/privacy_helper.rb` for kinds (`:blur`,
   `:strong`, `:redact`, `:mask`).
5. **Icons live in `shared/icons/`.** Don't inline SVG.

### Extracting a new component

Bar: same chunk of markup appears **3+ times**, or has non-trivial
logic/Stimulus wiring that would otherwise be duplicated. Don't extract on
impulse — every component is one more thing to maintain.

When you do extract:

1. Put the partial in `shared/components/_<name>.html.erb`.
2. First line is `<%# locals: (...) %>` with keyword-style locals; second line
   a one-liner explaining the non-obvious bits.
3. Add a section to `app/views/admin/styleguide/index.html.erb` showing every
   variant — same PR.
4. Replace the existing 3+ usages in the same change.

### Building something custom (one-off)

If a need genuinely doesn't fit anything reusable and the extraction bar
isn't met, that's fine — but:

- Leave a comment above explaining **why** no shared component fits, and what
  would trigger extraction:
  ```erb
  <%# Custom: needs sticky-on-scroll. If a second case appears, extract _sticky_bar. %>
  ```
- Use existing utilities and tokens (see Rules 2–3). No new class strings, no
  raw colors.

### PR checklist

- [ ] Loaded `/admin/styleguide` and every page touched, in the browser.
- [ ] No hand-rolled buttons / badges / inputs / tables.
- [ ] Sensitive values wrapped.
- [ ] If a new shared partial was added: it's in the styleguide.
- [ ] If something custom was added: there's a comment justifying it.

## Analytics data access

Read before writing any aggregation, chart endpoint, or report query.

### Single entry point: `LedgerEntry`

All analytics queries go through `LedgerEntry` (`app/models/ledger_entry.rb`),
a read-only model backed by the `ledger_entries` Postgres view
(`db/views/ledger_entries_v01.sql`). The view UNIONs every persisted ledger
source — currently `BankTransaction` (synced from Open Banking) and
`ManualTransaction` (cash typed in by the user) — and pre-resolves
enrichment + effective category in SQL.

Never write analytics against the underlying tables directly. Without the
view, every query has to UNION two tables and re-implement the
`COALESCE(category_override, merchant.default_category)` resolution; with
it, you get native Rails relation chains:

```ruby
LedgerEntry.for_user(user).booked.spend
           .where(booking_date: 90.days.ago..)
           .group("categories.id", "DATE_TRUNC('month', booking_date)")
           .sum(:amount_cents)
```

### Why a view (not a service object, not a materialized view)

- **Service object**: would push the UNION into Ruby; analytics loses native
  `joins` / `group` / `sum` AR ergonomics. Every chart endpoint would still
  know about both tables.
- **Materialized view**: introduces staleness + REFRESH cron + lock. Premature
  for this scale. Plain view is always fresh and uses the underlying indexes
  through PG planner. If aggregations get slow, upgrade is one line:
  `change_view :ledger_entries, materialized: true`.
- **Single physical table** (STI / denormalize): would require refactoring
  every existing model, sync pipeline, and UI. Zero payoff.

### What's exposed (and what isn't)

The view projects only the columns analytics needs:

```
source_type, source_id, bank_account_id,
amount_cents, signed_amount_cents, currency,
direction, status, payment_method,
booking_date, transaction_date,
title, counterparty_name,
enrichment_id, merchant_id, effective_category_id, enrichment_source
```

Detail-view fields stay on the source tables: `raw_payload`, `note`,
`external_id`, `type_hint`, `bank_transaction_code`, `value_date`,
`linked_bank_transaction_id`. When you need them, hop back via
`ledger_entry.source_record` — keep this off the hot path; analytics
queries should use view columns directly.

`signed_amount_cents` is positive for credits, negative for debits — sum it
directly for net flow, no `CASE` in the application.

### Always partition by `Category#kind`

Summing raw amounts across all rows is nonsense — income cancels expense,
transfers double-count own-account moves, ignored rows pollute totals. The
canonical scopes (`spend`, `income`, `transfers`, `savings`) narrow on
`Category#kind` first. Any new chart that doesn't fit one of those needs
to think about kind partitioning explicitly before summing.

### Extending the view

Bumps are versioned via `scenic`. Each version is a separate `.sql` file
in `db/views/`, dump-friendly to `schema.rb`, fast to revert.

```bash
# New ledger source (e.g. RecurringTransaction) or new analytics column
rails generate scenic:view ledger_entries
# -> writes db/views/ledger_entries_v02.sql + a migration calling
#    update_view :ledger_entries, version: 2, revert_to_version: 1
```

The view's column projection has to match across all UNION branches —
Postgres rejects mismatched types or column counts at view-creation time,
which is the safety net.

### When NOT to use `LedgerEntry`

- Writing transactions: use the source models (`BankTransaction`,
  `ManualTransaction`). They include `LedgerEntryConcern` for the polymorphic
  enrichment association.
- Editing enrichment / classification: use `Enrichment::ClassificationApplier`
  or `Cash::TransactionUpdater`, not direct enrichment writes.
- Showing a single transaction's detail page: bank vs manual UIs are
  different (bank rows are immutable, manual rows are editable), so use the
  source-specific controller.
