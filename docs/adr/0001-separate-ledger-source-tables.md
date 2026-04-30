# 0001 — Separate ledger source tables (bank vs manual)

## Context
Two kinds of ledger entries coexist: bank-synced (immutable, idempotent on
`external_id`, encrypted `raw_payload`, system lifecycle) and user-entered
cash (mutable, audited, currency must match wallet). Analytics needs both
queryable as one relation.

## Alternatives
- **Single table + `kind` discriminator (STI)** — nullable per-type cols,
  CHECK constraints to enforce shape per kind.
- **Single table + polymorphic source FK** — common cols + per-type
  `source_data` row.
- **Two source tables + DB view** for unified reads (Concrete Table
  Inheritance + view).

## Decision
Two tables + view. Bank and manual differ on 5+ invariants (idempotency
key, mutability, encryption, audit, currency-vs-wallet). Single table
would push these into CHECK constraints + app-level guards; two tables
let each constraint live where it belongs.

## Consequences
- Writes go to source models (different validations + paper_trail strategy).
- Reads go through the `LedgerEntry` view (ADR 0003), no UNION in app code.
- Adding a 3rd ledger type = new UNION branch + scenic v02; no schema
  change to existing tables.
- Revisit if: 3+ types appear with near-identical schemas, or bulk
  cross-source mutations become a regular use case.
