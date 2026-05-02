# 0009 — `OperationRun` as the generic long-operation tracker

## Context
Several flows are async with a UI surface for live progress + later
debugging: transaction sync, balance/connection/account-details
refresh, LLM enrichment, LLM connection test. Each has its own
inputs and summary shape, but the operational concerns
(start/finish/error/duration, who triggered it, manual vs scheduled,
broadcast progress) are identical.

## Alternatives
- **Per-kind tables** (`transaction_syncs`, `llm_enrichments`, …) —
  schema duplication; each new operation is a migration.
- **Sidekiq job log only** — no domain model to render in `/admin`,
  retries pollute history, no `subject` association.
- **Single table + `kind` discriminator + jsonb `params`/`summary`.**

## Decision
Single `operation_runs`. `kind` discriminates (`KINDS` whitelist),
`params`/`summary` are kind-specific jsonb, `subject` is polymorphic,
`triggered_by_user_id` is NOT NULL. `STREAMED_KINDS` opts a kind into
per-run Turbo Stream broadcasts. Jobs are thin wrappers that own the
run record; the actual work lives in domain operations so synchronous
callers (rake, console) bypass the run model entirely.

## Consequences
- Adding an operation = `KINDS` entry + a job + optional progress
  partial. No schema change.
- `summary` shape is a code-side contract per kind (header comment in
  each job). Old runs stay readable as long as readers tolerate
  missing keys.
- Cascade-on-user-delete is forced by NOT NULL on `triggered_by_user_id`.
- Revisit if: a kind's `params`/`summary` need DB-level constraints, or
  a kind needs system-triggered (no user) ownership.
