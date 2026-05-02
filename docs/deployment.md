# Deployment

Operational runbooks for the self-hosted production stack
(`docker-compose.prod.yml`). README covers the happy path; this file is
for incident response and one-off maintenance.

## Secrets layout

`bin/docker-entrypoint` bootstraps four secrets on first boot and
persists them in the `app_secrets` named volume (`/rails/secrets/`):

| File                                  | ENV var                                       | Used for                                  |
| ------------------------------------- | --------------------------------------------- | ----------------------------------------- |
| `secret_key_base`                     | `SECRET_KEY_BASE`                             | Session + remember-me cookies, Devise tokens |
| `ar_encryption_primary_key`           | `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`        | AR Encryption (TPP creds, etc.)           |
| `ar_encryption_deterministic_key`     | `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`  | AR Encryption deterministic columns       |
| `ar_encryption_key_derivation_salt`   | `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`| AR Encryption salt                        |

ENV always wins over the file — the entrypoint only fills gaps. Back the
volume up alongside `./backups/`; without the AR keys the DB dump is
unreadable.

## Rotating `SECRET_KEY_BASE` (leaked cookies)

When session/remember-me cookies leak, rotating `SECRET_KEY_BASE`
invalidates every signed/encrypted cookie immediately. AR encryption
columns are keyed independently and stay readable.

```bash
docker compose -f docker-compose.prod.yml exec app rm /rails/secrets/secret_key_base
docker compose -f docker-compose.prod.yml up -d --force-recreate app worker
```

Or pin a specific value via `.env`:

```bash
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" >> .env
docker compose -f docker-compose.prod.yml up -d --force-recreate app worker
```

Side effects:

- Every user is logged out (intended).
- Pending Devise tokens (password reset, unlock) become invalid. Reset
  TTL is 6h, so the blast radius is small.
- AR-encrypted columns are unaffected — different keys.

Restart `app` and `worker` together so both processes share a consistent
env, even though Sidekiq doesn't read cookies.

**Do NOT rotate the AR encryption keys this way.** Regenerating
`ar_encryption_*` files makes every encrypted column unreadable. Key
rotation for AR Encryption requires Rails' multi-key support and is a
separate procedure (not yet documented here — add when needed).
