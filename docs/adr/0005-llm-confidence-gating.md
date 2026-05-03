# 0005 - LLM enrichment with confidence gating

## Context
Rule-based classification handles common merchants but leaves a long
tail unmatched. LLMs classify the tail well but are non-deterministic
and hallucinate occasionally.

## Alternatives
- **Rule-only** - accept the unmatched tail.
- **Auto-apply every LLM proposal** - fastest, lowest precision.
- **Threshold gate** + review queue for low-confidence proposals.

## Decision
Threshold at 0.85. Above → `MerchantRule(source: "llm", enabled: true)`,
auto-applied on next rebuild. Below → `enabled: false`, surfaced in
the LLM enrichment review queue. User-source rules always outrank
LLM via `SOURCE_RANK = { user: 2, llm: 1, system: 0 }`.

## Consequences
- LLM never silently overrides a user decision (rebuilds preserve
  `source: manual` and `category_overridden`).
- Threshold is one constant - tunable later with measured FP rate
  per model.
- Cost capped: `Llm::EnrichmentRunner` scope is merchantless rows
  with signal only (skips own-IBAN noise, BLIK codes, blank titles).
