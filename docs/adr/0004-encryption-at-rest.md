# 0004 — Selective ActiveRecord encryption

## Context
PSD2 secrets, API session IDs, raw bank payloads, and balances are
sensitive. They must be encrypted at rest, search/equality lookups
on them are not needed.

## Alternatives
- **Disk / Postgres TDE only** — protects against disk theft, not against
  app-server / DB-user compromise.
- **Encrypt entire sensitive tables** — overkill, breaks indexes and
  Ransack on non-secret cols.
- **AR-encryption per field, non-deterministic.**

## Decision
Selective AR-encryption (non-deterministic) on:
`tpp_credentials.private_key_pem`, `tpp_credentials.application_id`,
`bank_connections.session_id`, `bank_connections.psu_id_hash`,
`bank_connections.raw_session_payload`, `bank_accounts.raw_balances`,
`bank_transactions.raw_payload`. PaperTrail skips them. Ransack
allowlists exclude them. Logs filter common secret patterns.

## Consequences
- Equality search on encrypted fields is impossible — fine, we don't
  need it. If we ever do (e.g. dedup on hashed session_id), switch
  that one field to deterministic encryption.
- Key rotation uses standard Rails encryption tooling.
- Plain TDE is still desirable for prod (defense in depth) but not
  in scope here.
