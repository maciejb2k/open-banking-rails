-- v03 - projects counterparty_kind from both UNION branches.
--
-- New column vs. v02:
--   * counterparty_kind (text)     - "self" / "external" / "unknown".
--                                    Set at sync/create time by
--                                    Banking::CounterpartyResolver. Lets
--                                    analytics filter own-account moves
--                                    without re-deriving identity from
--                                    IBAN + holder name on every query.
--
-- Schema invariants (relied on by LedgerEntry):
--   * Both UNION branches project the same column types. counterparty_kind
--     is NOT NULL on both source tables (default 'unknown') so no cast
--     is needed.

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
  bt.counterparty_kind,
  te.id                                              AS enrichment_id,
  te.merchant_id,
  COALESCE(te.category_id, m.default_category_id)    AS effective_category_id,
  c.path                                             AS category_path,
  COALESCE(c.essential, false)                       AS essential,
  COALESCE(te.recurring, false)                      AS recurring,
  te.recurrence_interval                             AS recurrence_interval,
  te.source                                          AS enrichment_source
FROM bank_transactions bt
LEFT JOIN transaction_enrichments te
  ON te.enrichable_type = 'BankTransaction' AND te.enrichable_id = bt.id
LEFT JOIN merchants m
  ON m.id = te.merchant_id
LEFT JOIN categories c
  ON c.id = COALESCE(te.category_id, m.default_category_id)

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
  mt.counterparty_kind,
  te.id,
  te.merchant_id,
  COALESCE(te.category_id, m.default_category_id),
  c.path,
  COALESCE(c.essential, false),
  COALESCE(te.recurring, false),
  te.recurrence_interval,
  te.source
FROM manual_transactions mt
LEFT JOIN transaction_enrichments te
  ON te.enrichable_type = 'ManualTransaction' AND te.enrichable_id = mt.id
LEFT JOIN merchants m
  ON m.id = te.merchant_id
LEFT JOIN categories c
  ON c.id = COALESCE(te.category_id, m.default_category_id);
