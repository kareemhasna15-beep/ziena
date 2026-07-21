-- ══════════════════════════════════════════════════════════════════════════
-- Zeina — Task 26: delivery city + fee on orders
-- File:  supabase_task26_delivery.sql
-- Scope: additive columns on the orders table so the storefront can persist
--        the customer's chosen city and the delivery fee we charged them.
--        100% additive, 100% idempotent — safe to re-run any number of times.
--
-- Client-side sendOrder still lists these fields in OPTIONAL_ORDER_FIELDS, so
-- checkout never hard-fails if this SQL hasn't been run yet — but the orders
-- table won't record the city/fee until you run it.
--
-- Ordering rule reminder: the next supabase_consolidated_pending.sql MUST
-- re-include the ALTER TABLE lines below so that if this file was skipped in
-- an environment, the consolidated file still closes the gap.
--
-- Run once in the Supabase SQL editor. Verify block at the very bottom.
-- ══════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
-- orders — city + delivery fee (Task 26)
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE orders ADD COLUMN IF NOT EXISTS city              text;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_fee_usd  numeric;

-- Useful when the owner filters recent orders by delivery region.
CREATE INDEX IF NOT EXISTS orders_city_idx ON orders (city);


-- ══════════════════════════════════════════════════════════════════════════
-- VERIFY — every row should return >0 after the migration
-- ══════════════════════════════════════════════════════════════════════════
SELECT
  (SELECT count(*) FROM information_schema.columns
     WHERE table_name='orders' AND column_name IN ('city','delivery_fee_usd')) AS orders_new_cols;
