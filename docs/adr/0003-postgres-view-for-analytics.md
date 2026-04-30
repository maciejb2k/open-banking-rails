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
Plain VIEW, managed by `scenic` (`db/views/ledger_entries_v01.sql`).
Pre-resolves enrichment + `effective_category_id` + `signed_amount_cents`
in SQL. Read-only `LedgerEntry` model is the single analytics entry
point.

## Consequences
- Schema changes to source tables require a scenic v02 bump.
- Source-table cols not relevant to analytics (raw_payload, note,
  external_id, etc.) stay off the view; reach via `source_record` if
  ever needed.
- Upgrade to materialized = `change_view :ledger_entries, materialized: true`
  + refresh cron. Revisit when aggregations show tail latency at >10⁵ rows.
