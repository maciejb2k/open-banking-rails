# spec/AGENTS.md

Operational guide for maintaining and extending the test suite. Read this
**before** writing or refactoring any spec.

This file is the rules of the road inside `spec/`. The strategy that produced
the suite is in `docs/testing-map.md` (~12500 lines, reference material).
Production-code conventions are in the root `AGENTS.md`. This file is shorter
on purpose — it's the operational layer that survives day to day.

The philosophy is built on four ideas: test units behind facades (not
individual classes); replace external systems with in-memory fake adapters
that production code runs against; build test state through the same
services used in production rather than through factory grafs; and avoid
the "wall of mocks" that turns tests into a wall in front of the code
instead of a safety net behind it. The rest of this file is the
operational consequence of those four.

---

## TL;DR — the eight non-negotiables

1. **Test units, not classes.** A unit is a collection of classes behind a
   public facade (e.g. the whole `Cash::` domain through `TransactionCreator`,
   the analytics view through `LedgerEntry`). Don't write a per-class spec for
   an internal helper.
2. **Use the in-memory fakes.** `fake_eb` and `fake_llm` are configured per
   example. Production adapter code runs against them. WebMock is reserved for
   the *single* wire-format spec per adapter.
3. **Build state through production services.** `Seeders::Showcase`,
   `Seeders::Categories`, `Cash::TransactionCreator`,
   `EnableBanking::Operations::*` are the canonical setup paths for system
   specs. Factories are for narrow domain specs.
4. **Controller specs test five things** — status, redirect/render target,
   flash, cross-user 404, that the right service was called. Nothing more.
   Anything else means business logic leaked into the controller.
5. **System specs tell stories.** Multi-step user journeys via Capybara,
   ending with cross-cutting invariants asserted via `SystemInvariants`.
6. **Flat spec structure.** One `RSpec.describe` per file, only bare `it`
   blocks. No `context`, no nested `describe`. English-only descriptions.
   No `#`-comments inside example bodies.
7. **Result-shape services.** Services return a `Result` struct with
   `success?`, `error_messages`, and the relevant entity. Specs assert on
   `result.success?` and `result.error_messages`, not on raised exceptions
   for domain failures.
8. **Stable system tests.** They survive refactoring of the internals.
   If a system spec breaks because you renamed a private method, the spec
   was wrong, not the rename. If a system spec breaks because a UI label
   moved, fix the label or the spec — not "the system."

If a spec doesn't fit one of these, push back before writing it.

---

## Suite layout

```
spec/
├── factories/                 19 minimal factory_bot files, one per model
├── factories_spec.rb          FactoryBot.lint(traits: true) — single test
├── models/                    Model invariants. One file per model.
│   └── concerns/              Concern unit specs (LedgerEntryConcern).
├── services/                  Domain unit specs, organized by domain.
│   ├── analytics/             cash_flow, filter, period
│   ├── auth/                  PAT issuer + authenticator
│   ├── auto_sync/             Dispatcher, CircuitBreaker, NextRunCalculator,
│   │                          ScheduleUpserter
│   ├── cash/                  TransactionCreator, TransactionUpdater,
│   │                          AtmWithdrawalLinker, Tracking
│   ├── categories/            Creator, Mover
│   ├── data_exchange/         round_trip_spec covers Export+Import as a unit
│   ├── enable_banking/        Operations, plus the wire-format adapter_spec
│   │   └── operations/        One spec per Operation (CreateConnection,
│   │                          SyncAccountTransactions, etc.)
│   ├── enrichment/            ClassificationApplier, TitleNormalizer,
│   │                          TransactionEnricher (the rule chain)
│   ├── llm/                   ConnectionTestRunner
│   ├── mcp/                   ApplicationTool, ServerBuilder
│   ├── recurrence/            Detector
│   ├── seeders/               Categories, MerchantRules, Showcase
│   ├── banking_spec.rb        CounterpartyResolver
│   └── operation_run_finalizer_spec.rb
├── requests/                  Eight admin-area files + api/v1 + mcp.
│   ├── api/v1/                Grape JSON API specs (Bearer auth)
│   └── mcp/                   MCP server specs (JSON-RPC)
├── system/                    14 user-journey specs + smoke crawler.
│   └── smoke/                 Auto-enumerated GET-route renderer
└── support/
    ├── auth_helpers.rb        issue_pat, bearer_headers, api_get/post/...
    ├── encryption_helpers.rb
    ├── fakes/                 The two in-memory fakes
    │   ├── enable_banking_client.rb   (336 lines — read it cover to cover)
    │   └── llm_client.rb              (86 lines)
    ├── fakes_helpers.rb       Wires fakes into Llm::Client.for and
    │                          EnableBanking::Client.new
    ├── shared_examples/       a cross-user isolated resource;
    │                          a bearer-authenticated endpoint;
    │                          a service returning a Result; etc.
    ├── showcase_helper.rb     setup_showcase, truncate_db, system spec hooks
    ├── sidekiq_helpers.rb
    ├── sign_in_helpers.rb     sign_in_as (system) + sign_in_request (request)
    ├── smoke_helpers.rb       Route enumeration for the smoke crawler
    ├── system_invariants.rb   The four cross-cutting invariants
    ├── system_spec_helper.rb
    ├── time_helpers.rb
    └── webmock_config.rb
```

If you're tempted to add a new top-level directory, you're probably crossing
a domain boundary that doesn't exist yet. Push back.

---

## The four immovables

### Flat spec structure

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::TransactionCreator do
  it "persists a manual transaction in the user's PLN cash wallet" do
    # ...
  end

  it "normalizes currency input ' eur ' to EUR and resolves to the EUR wallet" do
    # ...
  end
end
```

Not allowed: `context`, nested `describe`, `before(:each) { ... }` filling
ivars used across many examples (use a private helper method or a `let`
on the fly inside the example), `RSpec.shared_context` outside `support/`.

Why: nested groups silently apply to a subset of examples, and a reader
has to track scope to know what's true. Flat structure means each `it`
is a complete story.

The check:

```bash
grep -rn "^[[:space:]]*context\b\|^[[:space:]]*describe\b" spec/ --include="*_spec.rb"
```

Should return zero hits except top-level `RSpec.describe`.

### English-only descriptions and developer strings

`it` and `describe` strings are English. Always. Even if the production code
they cover was written in another language.

User-supplied test data (merchant names like "żabka", Polish account names,
LLM prompts tuned for Polish) is fine — that's user data, not developer copy.
The boundary is the same as in the root `AGENTS.md`.

### No `#`-comments inside example bodies

Specs document themselves through `it "..."` descriptions. If an example needs
inline narration, the description is too vague — fix the description.

The only allowed `#` comments in spec files are the AnnotateRb schema
information headers at the top of factory files and model specs.

### Result-shape services and how to test them

Every service returns a `Result` struct with at minimum `success?` and an
entity (the persisted record on success, the half-built record on failure).
Domain failures translate `RecordInvalid` → `Result(success?: false,
error_messages: [...])`. Specs assert:

```ruby
result = Cash::TransactionCreator.call(user: user, input: input)

expect(result.success?).to be(true)
expect(result.transaction).to be_persisted
expect(result.enrichment.source).to eq("manual")
```

For failures:

```ruby
expect(result.success?).to be(false)
expect(result.transaction).to be_a(ManualTransaction)   # half-built
expect(result.error_messages.join).to match(/blank|amount/i)
```

Do NOT use `expect { ... }.to raise_error(SomeFailure)` for *domain* failures.
Reserve raised exceptions for invariant violations from internal callers
(unknown enum value, missing required relation) — those are caller bugs.

---

## Authoring patterns (copy-paste templates)

### Service spec

Reference: `spec/services/cash/transaction_creator_spec.rb`,
`spec/services/llm/connection_test_runner_spec.rb`.

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::TransactionCreator do
  def call(user:, **input_attrs)
    input = described_class::Input.new(**input_attrs)
    described_class.call(user: user, input: input)
  end

  it "<happy path: persists, sets defaults, returns Result(success: true)>" do
    user = create(:user)

    result = call(user: user, amount: "12.34", currency: "PLN")

    expect(result.success?).to be(true)
    expect(result.transaction).to be_persisted
    # ... entity-specific shape assertions
  end

  it "<one specific edge case per example, no shared setup>" do
    # ...
  end

  it "<failure path: returns Result(success: false) with error_messages>" do
    user = create(:user)

    result = call(user: user, amount: "")

    expect(result.success?).to be(false)
    expect(result.error_messages.join).to match(/blank|amount/i)
  end
end
```

A `call(...)` helper that wraps `Input.new(**...)` is conventional — saves a
line per example and makes the test read like the controller calling the
service.

### Domain unit spec (testing through the facade)

Reference: `spec/services/enrichment/transaction_enricher_spec.rb`,
`spec/models/ledger_entry_spec.rb`.

The unit's *public surface* is what you test. Internal helpers
(`Banking::CounterpartyResolver` is internal to the enrichment chain,
`Cash::WalletResolver` is internal to `TransactionCreator`) are covered
transitively. Don't reach for them.

If you're tempted to test an internal helper directly:

1. Ask: "does this helper have a purpose beyond the one caller?"
2. If no → don't add a spec, test through the caller.
3. If yes → it's actually a public API. Promote it (move out of a `private_constant`,
   give it a `Result` if it makes decisions) and then test it like a service.

The exception: pure data mappers with many distinct branches
(e.g. `EnableBanking::TransactionNormalizer`, `JwtSigner`,
`PaymentMethodInferer`). A focused per-class spec is cheaper than spreading
14 edge cases across the operation that calls them. **This is a deliberate
deviation from "Test units, not classes" and should be justified per case.**

### Request spec — the five things

Reference: `spec/requests/cash_spec.rb`, `spec/requests/banking_spec.rb`.

```ruby
RSpec.describe "Cash area", type: :request do
  it "GET /admin/cash_transactions returns 200 with only the current user's transactions" do
    user = create(:user)
    other = create(:user)
    own = create(:manual_transaction, user: user, title: "OWN-TX")
    foreign = create(:manual_transaction, user: other, title: "FOREIGN-TX")
    sign_in user

    get admin_cash_transactions_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own.title)
    expect(response.body).not_to include(foreign.title)
  end

  it "POST /admin/cash_transactions delegates to TransactionCreator and redirects on success" do
    user = create(:user)
    sign_in user

    post admin_cash_transactions_path, params: { cash_transaction: { ... } }

    expect(response).to redirect_to(admin_cash_transactions_path)
    expect(flash[:notice]).to match(/Saved/)
    expect(ManualTransaction.for_user(user).count).to eq(1)
  end

  it_behaves_like "a cross-user isolated resource",
                  verb: :get,
                  path_for: ->(record) { Rails.application.routes.url_helpers.admin_cash_transaction_path(record) },
                  build_record: ->(user) { create(:manual_transaction, user: user) }
end
```

What you DON'T test in a request spec:

- The detailed shape of the entity the service returned (that's a service spec).
- Internal `before_action` mechanics.
- Locale-specific copy beyond a single keyword.
- HTML structure beyond "the right title shows up".
- Time formatting.

If you find yourself writing more than ~10 lines per request example, ask
whether the test belongs in the service spec.

### System spec — the story shape

Reference: `spec/system/personal_access_token_lifecycle_spec.rb`,
`spec/system/cash_with_atm_link_spec.rb`,
`spec/system/llm_enrichment_spec.rb`.

```ruby
RSpec.describe "<thing the user is doing> journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "<one full multi-step scenario, ending with invariants>" do
    user = build_seeded_user(...)

    sign_in_as(user)

    visit "/admin/some_page"
    click_button "Generate something"
    expect(page).to have_text("Saved")

    # ... three to ten steps the user actually takes ...

    # End the example with cross-cutting invariants:
    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
    assert_no_orphaned_enrichments!(user)
  end
end
```

Hard rules:

- `self.use_transactional_tests = false` — required, because Capybara's
  server runs in another thread.
- `before(:each) { truncate_db }` and `after(:each) { truncate_db }` — required
  in *every* system spec file. Yes it's eight lines per file, no it's not
  worth centralizing (we tried; see "Pending decisions" below).
- `sign_in_as(user)` from `SignInHelpers` — uses `Warden::Test::Helpers#login_as`
  which exercises the real cookie path.
- End with at least `assert_no_running_operation_runs!` and
  `assert_ledger_sums_match!(user)` if the journey touched any ledger source.

If you have to write more than ~50 lines per example, it's probably two
journeys glued together — split.

If you tag with `:sidekiq_inline`, jobs run inline for the duration of that
example. Use this when the journey *requires* a job to run terminally
(e.g. `auto_sync_circuit_breaker_spec.rb`); don't use it casually because
inline mode hides ordering bugs.

### Adapter wire-format spec (intentionally minimal)

Reference: `spec/services/enable_banking/adapter_spec.rb`.

This is the *one* place WebMock is used. It tests:

1. The HTTP verb, URL, and headers the adapter emits.
2. That JSON success bodies map to `Result(success: true, data: ...)`.
3. That JSON error bodies map to `Result(success: false, error: ...)`.
4. That transport exceptions (Faraday::ConnectionFailed) become
   `Result(success: false, status: 0)`, never raise.

That's it. Feature scenarios go through the fake.

### MCP tool spec / API endpoint spec

Reference: `spec/services/mcp/application_tool_spec.rb`,
`spec/requests/api/v1/transactions_spec.rb`,
`spec/requests/api/v1/cross_cutting_spec.rb`.

For Bearer-authenticated endpoints, use the `AuthHelpers`:

```ruby
raw, _record = issue_pat(user)
api_get("/api/v1/transactions", token: raw)
```

For MCP JSON-RPC:

```ruby
list = mcp_call(method: "tools/list", token: raw)
result = mcp_tool_call(name: "transactions.list", token: raw, arguments: {})
```

Auth boundary tests live in one place per surface:
`spec/requests/api/v1/cross_cutting_spec.rb` (uses
`it_behaves_like "a bearer-authenticated endpoint"`),
`spec/requests/mcp/protocol_spec.rb`. Don't repeat the 401 matrix in every
endpoint file.

---

## Working with the fakes

### `fake_eb` (Fakes::EnableBankingClient)

Three method categories — preserve this distinction when you extend it:

1. **Real adapter interface**: `get(path, params)`, `post(path, body)`,
   `delete(path)` returning `EnableBanking::Result`. Production code calls
   these. Don't change their signatures.
2. **UI fakers** — methods named after what a human does in the bank's web UI:
   `add_aspsp`, `add_session`, `add_account`, `add_transaction`, `set_balance`,
   `expire_session`, `revoke_session`. Tests call these to *describe state*.
3. **Test helpers** — `simulate_failure`, `simulate_429`, `simulate_500`,
   `reset!`, `recorded_calls`. Tests call these for orchestration.

Typical setup in a system spec:

```ruby
fake_eb.add_aspsp(name: "PKO BP", country: "PL")
session_id = fake_eb.add_session(aspsp_name: "PKO BP", country: "PL", valid_until: 30.days.from_now)
fake_eb.add_account(session_id: session_id, currency: "PLN", balance_cents: 100_00, iban: "PL...")
fake_eb.add_transaction(account_uid: ..., amount_cents: 50_00, direction: "debit", title: "BIEDRONKA")
```

Then production code (`EnableBanking::Operations::SyncAccountTransactions`,
`CreateConnection`, etc.) runs against the fake exactly as it would against
the real Enable Banking.

To simulate a failure:

```ruby
fake_eb.simulate_failure(method: :get, path: "/accounts/#{uid}/transactions", status: 500, count: 3)
```

`recorded_calls` captures every call made — useful for asserting the adapter
issued the expected sequence:

```ruby
expect(fake_eb.recorded_calls.map { |c| c[:path] }).to include("/sessions/#{sid}")
```

### Adding a new method to `fake_eb`

Trigger: production adapter starts using a new endpoint, OR a test scenario
needs to seed state that wasn't expressible before.

1. If the production adapter calls the new endpoint, add a `case path when
   "/new/path"` branch in the `get`/`post`/`delete` method that returns
   `respond(...)` with the right shape.
2. If a test needs a new "imagine the user did X in the bank's UI" verb,
   add a UI faker method (`add_*`, `set_*`, `expire_*`, etc.) that mutates
   `@aspsps` / `@sessions` / `@accounts` / `@transactions`.
3. Always update the one wire-format spec
   (`spec/services/enable_banking/adapter_spec.rb`) if the production adapter
   gained a new endpoint — that's where the WebMock proof lives.

### `fake_llm` (Fakes::LlmClient)

Same three categories, smaller surface:

1. **Real interface**: `structured(system_prompt:, user_prompt:, schema:)`
   returning a Hash matching the schema's `required` keys.
2. **UI fakers**: `respond_with(matcher:, response:)`,
   `respond_with_schema(matcher:, structured:)`,
   `respond_for_merchant_suggester(items:)`.
3. **Test helpers**: `set_failure(message:)`, `reset!`, `recorded_prompts`,
   `recorded_models`.

The fake matches the *first* canned response whose `matcher` (Regexp,
substring, or callable) matches the concatenated `system_prompt + user_prompt`,
and falls back to a schema-aware default for unmatched calls.

For confidence-gating tests, return varied confidences:

```ruby
fake_llm.respond_for_merchant_suggester(items: [
  { name: "Devstyle",  pattern: "DEVSTYLE",  category_path: "lifestyle.tools.saas",     confidence: 0.95 },
  { name: "Januszex",  pattern: "JANUSZEX",  category_path: "food.eating_out.fastfood", confidence: 0.6  }
])
```

Then exercise the runner and assert that high-confidence items got
auto-applied while low-confidence ones landed in pending review (per
ADR 0005).

`recorded_prompts` is the receipt for "did the runner send what we expected?":

```ruby
expect(fake_llm.recorded_prompts.last[:user]).to match(/sent_at=\d{4}-\d{2}-\d{2}/)
```

### When NOT to use the fakes

- Wire-format adapter spec — uses WebMock directly. ONE such spec per adapter.
- Pure unit specs that don't go anywhere near the network (most domain specs).

The check that a spec is using the fakes: `fake_eb` and `fake_llm` are
auto-injected per example via `FakesHelpers`. Any spec that names them is
opting into the fake layer; any spec that doesn't is opting out.

---

## Working with `LedgerEntry`

`LedgerEntry` (the Postgres view backed by `db/views/ledger_entries_v01.sql`)
is the single read seam for analytics. Read `app/models/ledger_entry.rb` and
the `Analytics data access` section of root `AGENTS.md` before testing
anything that aggregates transactions.

Spec invariants you must preserve when extending the view:

1. **Sum integrity**: `LedgerEntry.for_user(u).sum(:signed_amount_cents)` ==
   the same sum on `BankTransaction.for_user(u)` + `ManualTransaction.for_user(u)`.
   Test in `spec/models/ledger_entry_spec.rb` after every view change.
2. **No leaks, no duplicates**: one ledger row per source-table row.
3. **`signed_amount_cents` is canonical** — positive for credits, negative for
   debits. Never test with raw `amount_cents` summed across mixed directions.
4. **Always partition by `Category#kind`** in expense/income/transfer scopes.
   Sums across all rows are nonsense.
5. **Read-only**: `expect { row.update(...) }.to raise_error(ActiveRecord::ReadOnlyRecord)`.

If you bump the view to v02:

1. Generate `db/views/ledger_entries_v02.sql` via `rails generate scenic:view`.
2. Re-run `spec/models/ledger_entry_spec.rb` — every invariant must hold.
3. Add new test for whatever column/scope was added.
4. `assert_ledger_sums_match!` in `spec/support/system_invariants.rb`
   already verifies signed + unsigned + count integrity; if you added a new
   ledger source (say `RecurringTransaction`), extend that helper.

The `assert_ledger_sums_match!(user)` invariant is asserted at the end of
most system specs. It catches view drift across journeys.

---

## Setup helpers — what's available

| Helper | File | Purpose |
|--------|------|---------|
| `sign_in_as(user)` | `support/sign_in_helpers.rb` | System spec sign-in via Warden |
| `sign_in_request(user, password:)` | same | Request spec POST to sign_in |
| `sign_in user` | provided by Devise::Test::IntegrationHelpers | Stuffs the session — fastest for request specs |
| `issue_pat(user, name:)` | `support/auth_helpers.rb` | Real PAT via `Auth::PersonalAccessTokenIssuer` |
| `bearer_headers(token)` | same | `{ Authorization: "Bearer ..." }` |
| `api_get/post/patch/delete` | same | Bearer + JSON content type |
| `mcp_call(method:, params:, token:)` | same | JSON-RPC envelope |
| `mcp_tool_call(name:, arguments:, token:)` | same | tools/call helper |
| `fake_eb`, `fake_llm` | `support/fakes_helpers.rb` | The two in-memory adapters |
| `setup_showcase` | `support/showcase_helper.rb` | Full demo state via `Seeders::Showcase` |
| `truncate_db` | same | Used in every system spec's before/after hooks |
| `assert_no_running_operation_runs!` | `support/system_invariants.rb` | No `:running` runs left |
| `assert_ledger_sums_match!(user)` | same | Signed + unsigned + count integrity |
| `assert_user_isolation!(a, b)` | same | No shared BankTransaction ids |
| `assert_no_orphaned_enrichments!(user)` | same | No enrichments without enrichable |
| `:sidekiq_inline` tag | `rails_helper.rb` | Sidekiq runs inline for that example |
| `:papertrail` tag | same | PaperTrail enabled for that example |
| `freeze_time`, `travel_to(...)` | `support/time_helpers.rb` | Standard Rails time helpers |

Shared examples (use these instead of inlining):

| Shared example | File | When to use |
|---------------|------|-------------|
| `"a cross-user isolated resource"` | `support/shared_examples/cross_user_isolation.rb` | GET/PATCH/DELETE that should 404 for foreign records |
| `"a bearer-authenticated endpoint"` | `support/auth_helpers.rb` | API/MCP endpoints — covers no-token, non-Bearer, wrong prefix, revoked |
| `"a service returning a Result"` | `support/shared_examples/result_struct.rb` | Sanity check that a service has the right shape |
| `"a service that wraps RecordInvalid"` | same | Failure path |
| `"an idempotent service"` | same | Snapshot-based idempotency |

---

## System invariants — what each one catches

The suite has four invariants asserted at the end of system specs. Each one
catches a specific class of regression:

```ruby
assert_no_running_operation_runs!     # Operations stuck in :running (job died mid-flight)
assert_ledger_sums_match!(user)       # View drift, double-counting, missed source
assert_user_isolation!(user_a, user_b) # Cross-user leak in a query path
assert_no_orphaned_enrichments!(user)  # Enrichment kept alive after enrichable destroyed
```

Add a new invariant when:

- A class of bug has appeared more than once.
- The check is cheap (single SQL query).
- It belongs at the *end* of every journey, not at the start.

Each new invariant is one method in `system_invariants.rb`, named
`assert_<thing>!`, raising with a concrete diagnostic on failure (id list,
counts, etc.). A regression flips one helper, not 30 specs.

---

## Adding a new spec — decision tree

```
What are you testing?

├── External API integration?
│   └── If wire format → ONE WebMock spec at services/<adapter>/adapter_spec.rb.
│       Otherwise → use the fake. If the fake doesn't support it yet, extend
│       the fake first (UI faker for state, real-interface branch for new
│       endpoint).
│
├── Domain logic with a public facade?
│   └── ONE spec at services/<domain>/<facade>_spec.rb. Test through the
│       facade — internal helpers are covered transitively. NEVER write a
│       per-internal-class spec for something with a single caller.
│
├── A pure data mapper with many distinct branches?
│   └── Per-class spec is OK (e.g. TransactionNormalizer). Justify in the
│       file's header — if you can't, push it back into the facade.
│
├── A controller action?
│   └── Add it to the right area request spec
│       (requests/<area>_spec.rb). Five things: status, redirect, flash,
│       cross-user 404 via shared example, service called.
│
├── A user journey?
│   └── ONE system spec at system/<journey>_spec.rb. Multi-step, real
│       service paths, end with system invariants. Use Seeders::Showcase if
│       the journey assumes a populated state.
│
├── A new API endpoint or MCP tool?
│   └── Add to requests/api/v1/<resource>_spec.rb or requests/mcp/tools_spec.rb.
│       Include `it_behaves_like "a bearer-authenticated endpoint"` once per
│       endpoint, NOT per spec. Don't re-test the auth matrix.
│
├── A new model?
│   └── ONE spec at models/<model>_spec.rb covering its invariants
│       (validations that aren't obvious, scopes, business methods).
│       Don't typo-test ActiveRecord — `validates :email, presence: true` is
│       proven by the framework. Test the *non-obvious* parts.
│
├── A new factory?
│   └── Add the factory under factories/<plural>.rb. Add traits only when
│       3+ specs need them. The factory must round-trip
│       `FactoryBot.lint(traits: true)` — covered by factories_spec.rb.
│
└── An internal helper class with one caller?
    └── DON'T add a spec. Test through the caller. If you feel you must,
        the helper is probably a public API in disguise — promote it.
```

The default answer is "use the existing pattern in this directory." If
you're inventing a new pattern, that's a smell — push back.

---

## Refactoring the suite

### When to delete a class-level spec

- The class is now an internal-only helper of one facade.
- The behavior is already covered by the facade's spec.
- Don't keep "just in case" — every spec is code you maintain.

Always run the suite before AND after deletion to confirm coverage didn't drop.

### When to convert mock-heavy → fake-driven

If a spec contains `allow_any_instance_of(...)` or `allow(SomeService).to
receive(:call)` more than twice, it's a candidate.

Pattern:

1. Find what state the mock was simulating. (E.g. "the LLM returns this
   response" or "the bank session is expired".)
2. Express that state through the fake (`fake_llm.respond_with(...)`,
   `fake_eb.expire_session(sid)`).
3. Let production code run all the way through.

The book argues this is *always* better. In practice, it's cheaper for
journey-shaped tests, and similar-cost or worse for tests of one specific
controller branch (where mocking the service is one line vs. a multi-step
fake setup).

The line: if the spec is a story (system spec or thick request spec), prefer
the fake. If the spec is a one-branch failure path in a thin controller,
mocking the service is fine.

### When a factory needs a new trait

Trigger: 3+ specs create the same combination of attributes inline.

Anti-pattern: `trait :for_some_specific_test_scenario { ... }` — that's a
test helper, not a model facet.

If the trait would only apply to one test scenario, write a private helper
method in that spec instead.

### When to extract a new shared example

Same bar: 3+ uses, identical assertion shape. Examples that already meet it
and are extracted: `"a cross-user isolated resource"`,
`"a bearer-authenticated endpoint"`. Examples that *don't* meet it (yet)
and stay inline: shape of a JSON envelope (each endpoint has its own
fields).

### When to introduce a new fake

A new external system (third-party API, new LLM provider for a separate
purpose, payment gateway) is added. The new fake follows the same three-tier
shape:

1. Real interface (production methods, real Result types).
2. UI fakers (state-mutation methods named after human actions).
3. Test helpers (simulate failures, reset, record).

Wire it into `FakesHelpers` so per-example setup is automatic. Add a
WebMock-only adapter spec for the wire format. Cover the rest through the
fake.

---

## Smells to grep for

Run these periodically. Each one finds a known anti-pattern.

```bash
# Nested describe / context — should be 0
grep -rn "^[[:space:]]*context\b\|^[[:space:]]*describe\b" spec/ --include="*_spec.rb"

# Comments inside spec bodies — should only be schema info at top of file
grep -rn "^[[:space:]]\+#[^!]" spec/ --include="*_spec.rb" | grep -v "Schema Information\|Table name\|Indexes\|Foreign Keys\|frozen_string_literal"

# Polish/non-English in spec descriptions — should be 0
grep -rE 'it "' spec/ --include="*.rb" | grep -E "[ąćęłńóśźż]"

# Wall of mocks — anything with >2 allow(...) is a candidate for fake-driven rewrite
for f in spec/**/*_spec.rb; do
  count=$(grep -c "allow(" "$f")
  [ "$count" -gt 4 ] && echo "$f: $count allow() calls"
done

# Class tests for internal helpers — review these manually
ls spec/services/<domain>/  # compare against app/services/<domain>/
# every internal helper that has its own spec should be either:
# (a) a pure data mapper with many branches (justified)
# (b) a public API in disguise (promote it)
# (c) deletable (covered by facade)

# `expect { }.to raise_error(SomeFailure)` for domain failures — should use Result
grep -rn "raise_error.*Failed\|raise_error.*Error" spec/services/ | head
# Adapter wire-format and config-error specs are OK; domain failures should not raise.

# system spec without invariant assertion — review manually
grep -L "assert_no_running_operation_runs\|assert_ledger_sums_match\|assert_user_isolation\|assert_no_orphaned_enrichments" spec/system/*.rb
# The smoke spec is exempt; other journeys should end with at least one invariant.

# Uses of `Sidekiq::Testing.inline!` outside `:sidekiq_inline` tag
grep -rn "Sidekiq::Testing.inline!" spec/ | grep -v "rails_helper.rb"
# OK in journey scenarios that need terminal job state. Not OK as a default.
```

---

## Running the suite

### Prerequisites

The test suite needs Postgres + Redis containers (per `.env`):

```bash
# These must be up before running specs
docker ps  # should show obr-dev-db-1 (5432) and obr-dev-redis-1 (6379)
```

If they're not running, the suite errors with `PG::ConnectionBad`. Bring
them up via the project's compose setup before doing anything else.

### Modes

```bash
# Full suite — ~2.5 minutes
bundle exec rspec

# A single file (or directory) — fastest feedback
bundle exec rspec spec/services/cash/

# A single example by line number
bundle exec rspec spec/models/ledger_entry_spec.rb:42

# Profile the slowest examples
bundle exec rspec --profile 10

# Only the smoke crawler (auto-enumerated admin routes)
bundle exec rspec spec/system/smoke/

# Force a deterministic seed for repro
bundle exec rspec --seed 42
```

### What `pending` means in this suite

The smoke crawler emits `pending` for routes that have no fixture id in
`Seeders::Showcase` (e.g. `/admin/llm_enrichments/:id` when no LLM run
has been seeded). That's expected — pending count varies with showcase
contents. Failing examples and pending examples are different categories;
only failures should ever be non-zero.

### Tagged examples

| Tag | Effect | Use when |
|-----|--------|----------|
| `:sidekiq_inline` | `Sidekiq::Testing.inline!` for the duration | Job's terminal state matters |
| `:papertrail` | `PaperTrail.enabled = true` for the duration | Asserting on `PaperTrail::Version` |
| `:focus` | Filter run to focused examples | Local dev only — never commit |

### OpenTelemetry under test

OTLP exporters are disabled in test env via `spec_helper.rb` setting
`OTEL_SDK_DISABLED=true`. Without this, the suite emits hundreds of
`buffer-full` warnings and `Unable to export` errors when no collector
is running. Don't re-enable.

### `factories_spec.rb`

This is a single example that calls `FactoryBot.lint(traits: true)`. If a
factory or trait has invalid attributes, this fails before any other spec.
Keep it green — it's the cheapest factory regression check.

---

## Pending decisions / known deviations

These are things future agents may be tempted to "fix" — don't, without
reading the rationale first.

### `truncate_db` is duplicated in 16 system specs (not centralized)

Each system spec has its own `before(:each) { truncate_db }` and
`after(:each) { truncate_db }`. We tried to centralize this in
`showcase_helper.rb`'s `before(:each, type: :system)` hook (commit history
will show the attempt and revert).

The reason it's per-file: explicit > magical. Centralizing means a reader of
a system spec doesn't see the cleanup, has to know that `type: :system`
triggers the hook, and the file becomes invisible setup. The DRY benefit
(8 lines per file) is small; the explicitness benefit is real.

If a future agent re-introduces centralization, they must:
1. Verify the suite passes under multiple seeds (system specs commit data,
   so non-system specs after them rely on transactional fixture isolation
   that doesn't undo committed data — both `before` AND `after` must clean).
2. Document why centralizing is now better than explicit.

### Some "internal class" specs exist (`TransactionNormalizer`, `JwtSigner`, `PaymentMethodInferer`)

By the book ("test units, not classes") these would be folded into their
callers' specs. They survive because:

- `TransactionNormalizer` is a pure mapper with ~14 distinct branches
  (Revolut entry_reference fallback, mBank BBAN→IBAN, debtor vs creditor,
  remittance info ordering, etc.). Folding into `SyncAccountTransactions`
  would mean one operation spec carrying all 14 cases.
- `JwtSigner` produces a wire-format token; the per-claim assertions
  (iss, aud, kid, RS256, TTL) don't fit naturally into the operation that
  consumes the token.
- `PaymentMethodInferer` similarly has many distinct branch combinations.

If you find yourself adding a new "internal class" spec, ask: does this
have ~10+ distinct cases that would each take 2-3 lines of setup at the
facade level? If yes, per-class is justified. If no, fold it.

### Domain specs use factory_bot, not `Seeders::Showcase`

A purist take on the "build state through production services" idea
argues against any factory-driven setup — a factory describes state you
*imagined*, not state that *can actually arise* from real interactions.
The trade-off here: most domain specs test *column-level* behavior
(signed_amount sign, kind partitioning, IBAN normalization) where a
factory `create(:bank_transaction, direction: "credit")` is 50× faster to
set up than a service-driven path that syncs against a fake bank.

System specs *do* use the service-driven path (`Seeders::Showcase`,
real `Cash::TransactionCreator`, etc.) — that's where it pays off,
because the journey is going to refactor that path anyway.

If you find a *domain* spec that builds a complex multi-step state via
factories (more than ~5 `create(...)` calls in setup), that's a candidate
for converting to service-driven setup.

### `allow_any_instance_of(LlmSetting).to receive(:build_client)` in `connection_test_runner_spec.rb`

The runner calls `setting.build_client` directly, bypassing the global
`Llm::Client.for(user:)` stub in `FakesHelpers`. The cleaner fix is in
production: route through `Llm::Client.for(user:)` so the global fake-injection
catches it, then drop the per-spec `allow_any_instance_of`.

This is a real to-do, not a defended deviation. Whoever next touches
`Llm::ConnectionTestRunner` should consider the production refactor.

### `it_behaves_like` uses `instance_exec(&build_record)` inside the shared example

The `build_record` lambda is defined in the calling spec's group scope, but
it calls `create(...)` which is only available in example scope. We use
`instance_exec(user, &build_record)` inside the shared example to bridge
the scopes. This is a real RSpec subtlety; if you write a new shared
example that takes a builder lambda, do the same.

---

## When this guide doesn't have an answer

1. Look at the closest existing spec in the same directory. The directory
   layout is intentional — proximity ≈ similarity.
2. Check `docs/testing-map.md` section 09 (cross-cutting concerns) and
   section 10 (phasing) for the strategic intent.
3. Re-read the four ideas at the top of this file (units behind facades,
   in-memory fakes, service-driven setup, no wall of mocks) and apply them
   directly to the case at hand. They're enough to derive the answer for
   most situations the suite hasn't yet seen.
4. If you still don't have an answer, you're probably crossing a real
   boundary the suite hasn't seen before. Push back on the request, ask
   the human, or record the decision here so the next agent doesn't
   re-litigate it.

---

## Maintenance ritual

Quarterly (or before any major refactor):

1. Run `bundle exec rspec --profile 10` and look at the slowest specs.
   The slowest *should* be `Seeders::Showcase` (~1s) — if a domain spec
   is taking >500ms it's probably building too much state.
2. Run the smell-grep block above. New hits are review candidates.
3. Run with three different `--seed` values. Any non-deterministic failures
   are real bugs (ordering leakage between specs, time-of-day assumptions,
   non-truncated state).
4. Check `coverage/index.html` for files with <50% coverage that aren't on
   the deliberate-skip list (typo-tests, debug stubs, gem internals).
5. Re-read this file. If something has drifted, update it.

The suite is alive. Treat it that way.
