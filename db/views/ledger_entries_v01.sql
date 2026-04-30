-- Read-only unified ledger for analytics. UNIONs every persisted financial
-- entry (BankTransaction synced from Open Banking, ManualTransaction typed
-- in by the user) and pre-resolves enrichment + effective category in SQL,
-- so analytics queries stay single-relation.
--
-- Why a view (vs service object / materialized view): see
-- AGENTS.md → "Analytics data access". TL;DR: smallest possible abstraction
-- that lets `LedgerEntry.for_user(user).booked.spend.group(...).sum(...)`
-- work natively. Always fresh, no maintenance.
--
-- Extending:
--   * New ledger source (e.g. RecurringTransaction) → add a third UNION ALL
--     branch with the same projected columns, bump to v02 via:
--       rails generate scenic:view ledger_entries
--       (writes db/views/ledger_entries_v02.sql + migration)
--   * New analytics column on an existing source → add to the projection in
--     every UNION branch, bump to v02. Type/null compatibility across
--     branches is enforced by Postgres at view-creation time.
--
-- Schema invariants (relied on by the LedgerEntry model):
--   * source_type ∈ ('BankTransaction', 'ManualTransaction')
--   * (source_type, source_id) is the natural key
--   * signed_amount_cents is positive for credits, negative for debits
--   * effective_category_id = explicit override or merchant default
--   * NULL effective_category_id ⟹ unmatched / no merchant + no override

SELECT
  'BankTransaction'::text                            AS source_type,
  bt.id                                              AS source_id,
  bt.bank_account_id,
  bt.amount_cents,
  bt.currency,
  bt.direction,
  CASE bt.direction
    WHEN 'credit' THEN  bt.amount_cents
    ELSE               -bt.amount_cents
  END                                                AS signed_amount_cents,
  bt.status,
  bt.booking_date,
  bt.transaction_date,
  bt.payment_method,
  bt.title,
  bt.counterparty_name,
  te.id                                              AS enrichment_id,
  te.merchant_id,
  COALESCE(te.category_id, m.default_category_id)    AS effective_category_id,
  te.source                                          AS enrichment_source
FROM bank_transactions bt
LEFT JOIN transaction_enrichments te
  ON te.enrichable_type = 'BankTransaction' AND te.enrichable_id = bt.id
LEFT JOIN merchants m
  ON m.id = te.merchant_id

UNION ALL

SELECT
  'ManualTransaction'::text,
  mt.id,
  mt.bank_account_id,
  mt.amount_cents,
  mt.currency,
  mt.direction,
  CASE mt.direction
    WHEN 'credit' THEN  mt.amount_cents
    ELSE               -mt.amount_cents
  END,
  mt.status,
  mt.booking_date,
  mt.transaction_date,
  mt.payment_method,
  mt.title,
  mt.counterparty_name,
  te.id,
  te.merchant_id,
  COALESCE(te.category_id, m.default_category_id),
  te.source
FROM manual_transactions mt
LEFT JOIN transaction_enrichments te
  ON te.enrichable_type = 'ManualTransaction' AND te.enrichable_id = mt.id
LEFT JOIN merchants m
  ON m.id = te.merchant_id;
