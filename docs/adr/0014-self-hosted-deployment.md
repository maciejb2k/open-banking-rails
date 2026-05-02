# 0014 — Self-hosted deployment shape (compose-only, ENV-only, self-bootstrapping)

## Context
Target user is a self-hoster on a personal VPS / homelab — won't clone
the repo, won't read code, expects "download a compose file, bring it
up, log in" (Plausible CE / Immich / Linkding pattern). Finance data
raises the stakes: a botched upgrade or `down -v` is worse than losing
a self-hosted bookmark service. Full reasoning with prior-art survey
in `docs/deployment-plan.md`; this ADR is the implemented summary.

## Alternatives
- **Model A — clone repo + `bin/setup`** (Mastodon, Synapse) — more
  knobs, more steps, needs Ruby on the host to manage secrets.
- **Single compose with overlays** — DRY but the self-hoster has to
  mentally merge files to know what's running.
- **Rails encrypted credentials in prod** — needs `RAILS_MASTER_KEY`
  in env and editing secrets means launching an editor inside the
  container; no real win for single-tenant self-hosted.
- **Model B — `docker-compose.yml` + nothing else, all bootstrap inside
  the image.**

## Decision
Model B + ENV-only secrets + self-bootstrap entrypoint + dedicated
migrate service + automatic pre-migration backup.

- Two compose files, no overlays. Different `name:` (`obr-dev`,
  `obr-prod`) so dev/prod volumes never collide.
- No Rails encrypted credentials in prod — `SECRET_KEY_BASE` and the
  three `ACTIVE_RECORD_ENCRYPTION_*` keys come from ENV; initializer
  fails loud if missing.
- `bin/docker-entrypoint` generates missing secrets on first boot into
  the `app_secrets` named volume; subsequent boots read them. Operator
  ENV always wins.
- Dedicated `migrate` service (`restart: "no"`,
  `service_completed_successfully` gate) eliminates the web↔worker
  race and runs `pg_dump` before migrating.
- `./backups` as bind mount (visible on host, easy to rsync off-site).
- No Watchtower — auto-update of a finance app at 3am is how you wake
  up to a broken migration.
- First-run UI instead of seeded admin user (ADR 0011).

## Consequences
- Greenfield = curl + `up -d` + browser. No bootstrap password in logs.
- Upgrade = `pull && up -d`; pre-migration backup is automatic; if
  `migrate` fails, app/worker don't start (depends_on condition) — old
  container keeps serving until forward-fix.
- **`app_secrets` volume is required to decrypt backups — must be
  backed up alongside `./backups/`.** Trade-off accepted for the
  bootstrap simplicity.
- `image:` + `build:` together in the manifest — `pull` works
  post-publication, `--build` for forks/private phase. Same compose,
  no branching.
- Revisit if: multi-host deploy is needed (compose stops being enough
  → Kamal or k8s), or this ships as managed SaaS (secrets move to
  Vault / KMS).
