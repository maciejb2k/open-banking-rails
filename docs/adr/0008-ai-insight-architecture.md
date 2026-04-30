# 0008 — AI insight: facts-only narration, no number generation

## Context
Analytics dashboard shows a 3-sentence "what happened with your
spending" insight. LLMs hallucinate numbers — sending raw transactions
and asking for analysis would produce wrong amounts, fake merchant
names, and invented percentages. The card has to be trustworthy enough
to sit next to authoritative stat cards.

## Alternatives
- **Free-form analysis** — send transactions, let LLM analyze and
  narrate. Lowest fidelity; numbers will drift.
- **Structured output (JSON schema)** — model emits {top_category, …},
  app renders. Structurally safe but pushes the *judgment* (what is
  noteworthy) into the model — for a 3-sentence card that's overkill.
- **Facts-only narration** — Ruby computes every fact deterministically;
  LLM only writes 3 sentences over those facts.

## Decision
Facts-only. `Analytics::AiInsight` builds a `Facts` struct in Ruby
(spend total, delta vs previous period, top category + delta, top
merchant + delta, 0–2 notable movers via `|delta_pct| ≥ 100% AND
abs(amount) ≥ 200 PLN` heuristic). Prompt is hard-pinned: "use ONLY
numbers in the facts; do not invent". Output is plain text, exactly
3 sentences, neutral tone.

A defensive numeric guard runs after the model: every digit-sequence
in the response must appear in the serialized facts. Violations →
fall through to a muted callout ("Brak insightu — spróbuj odświeżyć"),
no broken card.

No cache in MVP1. Add fragment cache keyed by
`(user_id, period.from, period.to, account_ids.sort.hash)` with 24h
TTL when call frequency justifies it.

## Consequences
- Adding a new fact = Ruby change (and one prompt-line). Shape of the
  card stays bounded; the LLM never decides *what* to highlight, only
  *how* to phrase it.
- Notable-movers heuristic is one constant pair, tunable later. Full
  z-score / anomaly module is a separate concern (MVP3+).
- LLM failure / guard violation degrades silently — the dashboard
  always loads, the card just goes empty.
- No structured-output schema needed; the LLM client's `structured`
  path is bypassed in favor of a plain text completion (one new
  client method or an inline prompt — chose the smaller surface at
  implementation time).
