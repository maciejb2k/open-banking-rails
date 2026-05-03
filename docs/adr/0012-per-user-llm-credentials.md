# 0012 - Per-user LLM credentials + provider registry

## Context
Two LLM features (merchant suggester, AI insight) need an API key +
model. Earliest version read `OPENAI_API_KEY` / `LLM_MODEL` from ENV -
fine for one user, wrong as soon as the schema went multi-tenant
(ADR 0011): a shared key means one user can burn another's quota, and
provider/model selection has no UI.

## Alternatives
- **Keep global ENV** - simplest, but no per-user isolation and no
  switching without redeploy.
- **Per-user record, hardcode the supported list across the app** -
  every model select / validation / factory duplicates the list;
  adding a vendor touches 4+ files.
- **Per-user record + single registry of supported providers.**

## Decision
`LlmSetting` per user (`has_one`). `api_key` AR-encrypted (ADR 0004),
`provider` + `model` validated against `Llm::Providers::REGISTRY`.
`config/initializers/ruby_llm.rb` is deliberately key-less - keys bind
per-call via `RubyLLM.context` inside each `Llm::Clients::*`, so there's
no global to fall back on. Adding a vendor = one entry in the registry +
one `Llm::Clients::Foo` subclass.

## Consequences
- AI features fail loudly when no `LlmSetting` exists for the user -
  no silent fallback. `Llm::Client.for(user:)` is the canonical factory.
- Quota cross-contamination is impossible at the code level (no global
  key to leak through).
- Curated model lists per provider - a user picking an unsupported
  model fails at validation, not at request time. Trade-off:
  list needs maintenance touch-ups when a provider ships a new flagship.
- Revisit if: per-feature model choice matters (cheap for classification,
  smarter for insight) - would need feature→model mapping on the model.
