# 0010 - Three-layer category model (ltree path + kind + facets)

## Context
Categorization has to answer four orthogonal questions: where in the
hierarchy, what role for analytics (spend/income/transfer/savings/
ignored), need vs want, recurring or not. Squashing these into one flat
enum or one boolean-loaded model pushes the answers into ad-hoc
re-derivation on every consumer. Analytics correctness depends on
partitioning by the right axis before summing.

## Alternatives
- **Flat enum + parent_id self-FK** - recursive CTE per query, no
  native subtree operator.
- **`ancestry`/`closure_tree` gem** - Ruby-side tree, still leaves all
  axes on one model.
- **PG `ltree` path + `kind` enum + facets split across models.**

## Decision
Three layers:
- **Layer 1 - `Category`**: per-user, soft-deletable, ltree `path` with
  GiST index, `kind` ∈ {expense,income,transfer,savings,ignored},
  `essential` boolean.
- **Layer 2 - `TransactionEnrichment`**: `recurring` + `recurrence_interval`
  (per-row, not per-category - the same category holds both one-off and
  recurring rows).
- **Layer 3 - `gutentag` tags on enrichment** for free-form labels.

The view (ADR 0003) projects Layer 1+2 facets onto every ledger row so
analytics scopes stay one-line.

## Consequences
- **Every analytics sum must narrow on `kind` first.** Canonical scopes
  (`spend`, `income`, `transfers`, `savings`) on `LedgerEntry` pin
  direction + kind together so a misclassified row can't inflate totals.
- A new property of *the category* → column on `Category` + view bump.
  A property of *a specific transaction* → column on `TransactionEnrichment`
  + view bump.
- `path` is the source of truth, `slug` is the leaf; renames change
  `name` only - seeds, exports, the LLM suggester, and `merchant_rules`
  keep working.
- Revisit if: a 4th orthogonal axis appears, or hierarchy depth grows
  past ~4 levels and lookups need different indexing.
