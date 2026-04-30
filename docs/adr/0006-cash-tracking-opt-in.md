# 0006 — Cash tracking is opt-in

## Context
Enabling cash tracking changes the meaning of BLIK ATM withdrawals
(from spend → transfer to wallet) and creates parallel manual rows.
This must not silently shift analytics for users who don't care.

## Alternatives
- **Always-on** — every ATM withdrawal auto-mirrored as a wallet topup.
- **Always-off** — manual cash UI exists but no auto-linking; user
  pairs withdrawals with topups by hand.
- **Per-user opt-in** flag.

## Decision
`User#track_cash` boolean, default false. Toggling on auto-creates a
PLN wallet (`Cash::WalletResolver`) and backfills historical BLIK ATM
withdrawals via `Cash::AtmWithdrawalLinker`. Sync-time linking is
gated by the same flag.

## Consequences
- Off (default): ATM withdrawals classified by the system ATM rule
  (kind: transfer via merchant default) — already excluded from spend.
  No cash-side bookkeeping.
- On: linker fires on every sync; user logs cash spending manually.
  Wallet balance can drift from physical wallet — Phase 4
  reconciliation surfaces this.
- Toggling off later keeps existing data; only future links are gated.
