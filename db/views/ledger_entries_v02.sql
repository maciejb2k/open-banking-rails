-- v02 - adds Layer 1/2 columns from the three-layer category model.
--
-- New projected columns vs. v01:
--   * category_path (ltree)        - full materialized path of the
--                                    effective category (e.g. food.cooking.supermarket).
--                                    Use `<@ 'food'::ltree` for subtree filters.
--                                    NULL when no enrichment match (unmatched row).
--   * essential (boolean)          - Layer 2 facet on the effective category.
--                                    Falls through `false` for unmatched.
--   * recurring (boolean)          - Layer 2 facet on the enrichment.
--                                    Populated by Recurrence::Detector.
--   * recurrence_interval (text)   - weekly/monthly/yearly when recurring.
--
-- Schema invariants (relied on by LedgerEntry):
--   * Both UNION branches project the same column types - `NULL::ltree`
--     and `NULL::text` casts are required where a branch may not produce
--     a value (Postgres rejects bare NULL union with concrete type).
--   * effective_category_id stays in the projection for back-compat
--     (analytics still resolve the AR object through it). category_path
--     is the new fast filter axis.

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
