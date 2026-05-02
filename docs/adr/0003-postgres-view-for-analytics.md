# 0003 — Postgres view for analytics reads

## Context
Analytics needs a single relation over heterogeneous ledger sources
(ADR 0001) with native AR `joins`/`group`/`sum` ergonomics — no
hand-written UNION boilerplate per chart.

## Alternatives
- **Ruby aggregator** `Ledger::Query` — UNION in app code, loses native
  AR scope chaining for analytics.
- **Plain Postgres VIEW** — always fresh, no maintenance, uses
  underlying indexes through PG planner.
- **MATERIALIZED VIEW** — cached, requires REFRESH cron + lock window.

## Decision
Plain VIEW, managed by `scenic` (`db/views/ledger_entries_v0*.sql`).
Pre-resolves enrichment + `effective_category_id` + `signed_amount_cents`
in SQL. Read-only `LedgerEntry` model is the single analytics entry
point.

## Version history
- **v01** — baseline projection: source identity, amount + sign, status,
  payment_method, dates, title/counterparty_name, enrichment join.
- **v02** — three-layer category facets surfaced from join: `category_path`
  (ltree, for `<@` subtree filters), `essential` (Layer 2 needs/wants),
  `recurring` + `recurrence_interval` (Layer 2 cyclical).
- **v03** — `counterparty_kind` (self/external/unknown) projected from both
  branches; lets analytics filter own-account moves without re-deriving
  identity from IBAN + holder name on every query.

## Consequences
- Schema changes to source tables require a new scenic version (`rails
  generate scenic:view ledger_entries` → v0N+1).
- Source-table cols not relevant to analytics (raw_payload, note,
  external_id, etc.) stay off the view; reach via `source_record` if
  ever needed.
- Upgrade to materialized = `change_view :ledger_entries, materialized: true`
  + refresh cron. Revisit when aggregations show tail latency at >10⁵ rows.
