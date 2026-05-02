# 0011 — Single-user-shaped multi-tenant + first-run UI bootstrap

## Context
Self-hosted PFM: in practice one user per deployment, sometimes two.
Schema is multi-tenant-shaped (categories, merchants, rules,
llm_setting, hidden_categories — all per-user). Greenfield deploy needs
an account before sign-in works, without inventing credentials in a
terminal the user may never see.

## Alternatives
- **Seed admin user, print bootstrap password to logs** — brittle,
  fails on headless deploys, leaks secret material to stdout.
- **Devise sign-up route** — public registration on every instance is
  a footgun on a misconfigured reverse proxy.
- **First-run UI** — `User.count == 0` → redirect to `/setup`, form
  creates the first account, route then closes.

## Decision
Devise mounted with `skip: [:registrations]`.
`ApplicationController#require_first_run_setup` redirects to `/setup`
while no user exists. `SetupController#create` creates the user, runs
`Seeders::Categories` + `Seeders::MerchantRules`, signs them in.
Schema stays multi-tenant-shaped — the future second user is "create
the second user", not a refactor.

## Consequences
- Greenfield deploy: `compose up` → browser → form. No bootstrap
  password in logs, no env var.
- Second user (partner) is created via Rails console — deliberate
  friction, no public sign-up surface ever.
- Forgot-password without SMTP is a documented `bin/rails runner` one-liner.
- New per-user table = `belongs_to :user` + uniqueness scope. No
  "global vs scoped" judgment per-table.
- `User.exists?` runs every request — cached enough by the AR query
  cache at this scale; memoize behind `Rails.cache` if it ever shows up.
- Revisit if: real multi-user usage appears (need stronger isolation
  tests), or this ever ships as SaaS (public registration + onboarding
  become real concerns).
