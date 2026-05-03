# 0002 - Polymorphic enrichment association

## Context
Classification (merchant, category, decision source, confidence) is
identical across ledger types. Embedding it on every source table would
duplicate columns and rule-matching logic.

## Alternatives
- **Inline columns** on each ledger source table.
- **Shared table referenced by FK** from each source (one FK column per
  source, mostly null).
- **Polymorphic association** `(enrichable_type, enrichable_id)`.

## Decision
Polymorphic. One `transaction_enrichments` table; one rebuild path
(`Enrichment::TransactionEnricher.rebuild!`) iterates every ledger type
uniformly. Adding a ledger type costs `include LedgerEntryConcern`.

## Consequences
- Unique index on `(enrichable_type, enrichable_id)` enforces 1:1.
- Rule field allowlist applies across ledger types; the enricher uses
  `respond_to?(rule.field)` so a rule that targets a column the model
  doesn't expose is a non-match, not an error.
- No DB-level referential integrity (Rails polymorphic FK limitation) -
  acceptable, rebuild scope handles orphans.
