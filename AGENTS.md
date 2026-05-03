# AGENTS.md

Guide for agents working on this codebase. Add a new section per area as
conventions emerge - don't pad sections with content that isn't established
yet.

## Language

**UI copy is always English. No exceptions.** Labels, buttons, hints, flash
messages, callout titles, validation copy, page titles, empty states,
controller-rendered alerts/notices - all English. Even if surrounding
features were authored in another language by mistake, new code is
English and old code gets translated when you touch it.

User-supplied data (transaction titles, merchant names, notes, category
names typed by the user, prompts sent to the LLM) is whatever language
the user wrote it in - that's their choice and not something to
"normalize." Render it as-is. Same for LLM prompts where the model's
behavior is tuned for a specific language: leave them alone.

The boundary is "did the developer write this string, or did the user /
model?" Developer strings → English. Everything else → don't touch.

## Admin UI

Read before touching `app/views/admin/`. Goal: keep the panel consistent and
the component library from rotting into one-off divs.

### Source of truth

**`/admin/styleguide`** (`admin_styleguide_path`) renders every reusable
component with its variants. Read it before writing markup. Each partial's
API is in its first line as `<%# locals: (...) %>` - that's the signature.

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

- **Index** (filters + sortable table + pagination) - `bank_transactions/index.html.erb`
- **Show** (header + actions + cards + definition list) - `settings/bank_connections/show.html.erb`
- **Form** (new/edit) - `settings/tpp_credentials/_form.html.erb`
- **Auth** (centered, full-width submit) - `sessions/new.html.erb`

### Rules

1. **Read the styleguide first.** If the thing exists as a component, use it.
   Don't render markup that has a component (buttons, badges, cards, tables,
   form fields, callouts, filter chips/triggers, dropdown menus).
2. **Don't copy Tailwind class strings.** If you'd write the same 8+ class
   string twice, use an existing utility (`.form-input`, `.admin-section`) or
   extract a partial.
3. **Use the design tokens.** Colors via `bg-primary/10`, `text-destructive`
   etc. - never raw hex. Spacing/radii from the existing scale.
4. **Sensitive data must be wrapped.** IBANs, amounts, names, raw payloads,
   secrets - wrap in `sensitive(value)` / `sensitive_class` / `sensitive: true`
   prop. See `app/helpers/admin/privacy_helper.rb` for kinds (`:blur`,
   `:strong`, `:redact`, `:mask`).
5. **Icons live in `shared/icons/`.** Don't inline SVG.

### Extracting a new component

Bar: same chunk of markup appears **3+ times**, or has non-trivial
logic/Stimulus wiring that would otherwise be duplicated. Don't extract on
impulse - every component is one more thing to maintain.

When you do extract:

1. Put the partial in `shared/components/_<name>.html.erb`.
2. First line is `<%# locals: (...) %>` with keyword-style locals; second line
   a one-liner explaining the non-obvious bits.
3. Add a section to `app/views/admin/styleguide/index.html.erb` showing every
   variant - same PR.
4. Replace the existing 3+ usages in the same change.

### Building something custom (one-off)

If a need genuinely doesn't fit anything reusable and the extraction bar
isn't met, that's fine - but:

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
source - currently `BankTransaction` (synced from Open Banking) and
`ManualTransaction` (cash typed in by the user) - and pre-resolves
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
`ledger_entry.source_record` - keep this off the hot path; analytics
queries should use view columns directly.

`signed_amount_cents` is positive for credits, negative for debits - sum it
directly for net flow, no `CASE` in the application.

### Always partition by `Category#kind`

Summing raw amounts across all rows is nonsense - income cancels expense,
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

The view's column projection has to match across all UNION branches -
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

## Controllers & service objects

Read before adding a new action or service. Reference shapes:

- `app/services/cash/transaction_creator.rb` - canonical service: `Input`
  struct, `Result` struct, `def self.call(...) = new(...).call`, AR
  transaction, `RecordInvalid` → `Result(success?: false)`.
- `app/services/enrichment/classification_applier.rb` - multi-mode service
  with early-return guards.
- `app/controllers/admin/cash_transactions_controller.rb` - controller that
  only parses params, calls the service, branches on `result.success?`.
- `app/services/enable_banking/` - adapter shape: typed `Result`/`Error`,
  no gem objects leaking out.

### Controllers stay thin

A controller action does five things, in this order:

1. Pull data from `params`, `current_user`, session.
2. Build the service's `Input`.
3. Call the service.
4. Branch on `result.success?` → `redirect_to` (success) or
   `render :new/:edit, status: :unprocessable_entity` (failure).
5. Update flash / cookies / session.

```ruby
def create
  result = Cash::TransactionCreator.call(
    user:  current_user,
    input: Cash::TransactionCreator::Input.new(**cash_params.to_h.symbolize_keys)
  )
  if result.success?
    redirect_to admin_cash_transactions_path, notice: "Saved."
  else
    @cash_transaction = result.transaction || ManualTransaction.new
    load_form_options
    flash.now[:alert] = result.error.presence || "Could not save."
    render :new, status: :unprocessable_entity
  end
end
```

Rules:

- **No business `@ivars` in `before_action`.** Filters load a record
  (`@cash_transaction = ...`) or enforce a precondition. They don't compute
  or mutate.
- **No `ActiveRecord::Base.transaction` in a controller.** That's a service.
- **No model writes from a controller** beyond `destroy!` of an
  already-loaded scoped record. The moment a second caller appears or the
  write touches >1 row, extract a service.
- **Authorize through scoped associations.** `current_user.merchants.find(...)`,
  not `Merchant.find(params[:id])`.

### Service objects

One use case = one service. Verb-named, single public `#call`, namespaced
by domain.

```ruby
# frozen_string_literal: true

module Cash
  class TransactionCreator
    Input  = Struct.new(:amount, :currency, ..., keyword_init: true) do
      def normalized_currency = currency.to_s.strip.upcase.presence || "PLN"
      def amount_cents_in(iso) = ...
    end

    Result = Struct.new(:success?, :transaction, :error_messages, keyword_init: true) do
      def error = Array(error_messages).join(", ")
    end

    def self.call(...) = new(...).call

    def initialize(user:, input:)
      @user, @input = user, input
    end

    def call
      ActiveRecord::Base.transaction do
        # ... business logic ...
        return Result.new(success?: true, transaction: tx)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, transaction: e.record, error_messages: e.record.errors.full_messages)
    end
  end
end
```

Non-negotiables:

1. **Namespaced under a domain folder.** `app/services/<domain>/<verb>.rb`.
   Top-level only for cross-domain policy (`OperationRunFinalizer`).
2. **Verb name.** `Creator`, `Updater`, `Applier`, `Resolver`, `Linker`,
   `Syncer`, `Detector`, `Suggester`, `Finalizer`. Never `*Service`,
   `*Manager`, `*Helper`.
3. **`def self.call(...) = new(...).call`** - always. Callers write
   `Cash::TransactionCreator.call(...)`.
4. **Keyword-only args** on the constructor and on `Input`
   (`keyword_init: true`).
5. **Single public method.** Helpers are `private`. A second use case is a
   second service.
6. **Stateless across calls.** Fresh instance per request; never memoize a
   service on the controller.
7. **AR transaction lives in the service**, not the controller.

### `Input` and `Result` structs

Use `Input` when the service takes >2 args or any arg needs parsing /
normalization (currency strings, decimal amounts, dates, blank-vs-missing
semantics). Build it in the controller; never let `params` reach the
service.

The `Input` owns trimming, casing, blank → default, string → typed value,
and "blank means clear" vs "blank means keep" semantics (see
`Cash::TransactionUpdater::Input` for the second case). The service body
then reads as business logic, not parsing.

`Result` carries `success?`, the entity (success or half-built on
failure), and `error_messages`. Why Result over raised exceptions on
failure? Because the controller renders the form back with the
half-built record on failure - Result carries it naturally.

Services rescue **domain-typed** exceptions (`RecordInvalid`,
`ArgumentError` from BigDecimal, adapter errors) and translate them into
`Result(success?: false)`. Bugs (`KeyError`, `NoMethodError`) propagate.
Raise (don't Result) for invariant violations from internal callers
(unknown enum, missing required relation) - those are caller bugs.

### Adapters: wrap every external API

Every external service (Enable Banking, an LLM provider, future Stripe)
gets an adapter under its own namespace. Nothing outside the adapter
touches the gem or the raw HTTP client.

- Adapter exposes the methods *your app* needs, named in your domain.
- Returns your own `Result` / typed value, never the gem's response.
- Wraps third-party exceptions: `rescue Faraday::Error => e; raise EnableBanking::Error.new(...)`.
- Fake adapter for tests lives next to the real one and shares its
  interface.

A vendor swap or gem upgrade touches only `app/services/<domain>/` -
never controllers, never the rest of the services.

### Forms when conditional validations appear

If you're about to write `validates :foo, if: :context_flag?` with
`attr_accessor :context_flag` on a model - stop. The condition isn't
model state, it's form context. Extract a form object under
`app/forms/<form>.rb` (`include ActiveModel::Model`, own the
context-specific validations, `def persisted?; false; end`). The model
keeps only invariants. The service persists with `save!(validate: false)`
after the form approves the data. Don't put `#save` on the form.

### No AR callbacks for cross-aggregate work

`after_create` / `after_save` / `after_commit` are reserved for trivially
local data hygiene (derived columns on the same row). They are **not** for
sending mail, calling external services, updating other aggregates, or
enqueueing non-hygiene jobs.

Reasons that bite us in practice: callbacks fire under *every* save path
regardless of business context, hide intent, and block service
extraction. "Transaction was saved" is not the same business event as
"user added a manual cash entry" vs "ATM linker matched a withdrawal" -
a callback can't tell.

The replacement: do the side-effect explicitly in the service that
triggered the save. `Cash::TransactionCreator` saves the transaction *and
then* builds the enrichment in the same method, in the same transaction -
that's the whole point of the service.

### File layout

```
app/services/<domain>/<verb>.rb       → Domain::Verb
app/services/<domain>/api/<endpoint>  → Domain::Api::Endpoint  (adapter endpoints)
app/forms/<form>.rb                   → Form                   (when needed)
```

Existing domain folders: `analytics/`, `banking/`, `cash/`, `categories/`,
`data_exchange/`, `enable_banking/`, `enrichment/`, `llm/`, `recurrence/`,
`seeders/`. Add a new one only when ≥2 related services exist or are
imminent.

`Input` and `Result` are inner constants of their service, not separate
files - unless they're shared across multiple services in the same
namespace (`EnableBanking::Result`, `DataExchange::Result`).

### Smells to avoid

1. Business `@ivars` set in `before_action` and read in views.
2. `ActiveRecord::Base.transaction` in a controller.
3. AR callbacks doing cross-aggregate work (mail, jobs, other-table writes).
4. Conditional validations on a model with `attr_accessor :context_flag`.
5. A controller action branching `if param == "x"` between two business
   cases - split into two services / two routes.
6. Booleans or bare AR objects returned from services. Return a `Result`.
7. Pattern-suffix names (`*Service`, `*Manager`) - rename to the verb.
8. Multiple public methods on one service - split.
9. A service reading `params`, `request`, `session`, `cookies`, or
   `current_user` from outside. Pass them in.
10. Adapters that leak gem exceptions or response objects.

### PR checklist

- [ ] Controller action is `params → Input → Service.call → branch on Result`,
      no business logic.
- [ ] No new `ActiveRecord::Base.transaction` outside a service.
- [ ] No new `after_save`/`after_create`/`after_commit` doing
      cross-aggregate work.
- [ ] Service is namespaced (`Domain::Verb`), uses
      `def self.call(...) = new(...).call`, keyword args, single public `#call`.
- [ ] External API calls go through an adapter; no gem types leak.
- [ ] New conditional validation? Form object exists, conditional is gone
      from the model.
