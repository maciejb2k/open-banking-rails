# 0008 — AI insight: facts-only narration, no number generation

## Context
Analytics dashboard shows a 3-sentence "what happened with your spending"
card. LLMs hallucinate numbers — sending raw transactions and asking for
analysis produces wrong amounts, fake merchant names, invented
percentages. The card sits next to authoritative stat cards, so it has
to be trustworthy at the same level.

## Alternatives
- **Free-form analysis** — send transactions, let LLM analyze and
  narrate. Lowest fidelity; numbers will drift.
- **Structured output (JSON schema)** — model emits {top_category, …},
  app renders. Structurally safe but pushes *what is noteworthy* into
  the model — overkill for a 3-sentence card.
- **Facts-only narration** — Ruby computes every fact deterministically;
  LLM only writes 3 sentences over those facts.

## Decision
Facts-only. `Analytics::AiInsight` builds a `Facts` struct in Ruby
(spend total, delta vs previous period, top category + delta, top
merchant + delta, 0–2 notable movers via `|delta_pct| ≥ 100% AND
abs(amount) ≥ 200 PLN`). Prompt is hard-pinned: "use ONLY numbers in
the facts; do not invent". A defensive numeric guard runs after the
model — every digit-sequence in the response must appear in the
serialized facts; violations fall through to a muted callout, no
broken card.

## Consequences
- Adding a new fact = Ruby change + one prompt line. Card shape stays
  bounded; the LLM never decides *what* to highlight, only *how* to
  phrase it.
- Notable-movers heuristic is one tunable constant pair. Full z-score /
  anomaly module is a separate concern (MVP3+).
- LLM failure / guard violation degrades silently; dashboard always
  loads.
- No cache in MVP1. When call frequency justifies it, fragment cache
  keyed by `(user, period, account_ids)` with 24h TTL.
