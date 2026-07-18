-- ══════════════════════════════════════════════════════════════
-- Task 21: product discounts (percent + optional end date)
-- Run once in the Supabase SQL editor. Safe to re-run.
-- ══════════════════════════════════════════════════════════════

ALTER TABLE products ADD COLUMN IF NOT EXISTS discount_percent numeric CHECK (discount_percent IS NULL OR (discount_percent >= 0 AND discount_percent <= 90));
ALTER TABLE products ADD COLUMN IF NOT EXISTS discount_ends_at timestamptz;

CREATE INDEX IF NOT EXISTS products_discount_active_idx
  ON products (discount_percent)
  WHERE discount_percent IS NOT NULL AND discount_percent > 0;

-- Verify
SELECT
  count(*) FILTER (WHERE discount_percent IS NOT NULL AND discount_percent > 0
                     AND (discount_ends_at IS NULL OR discount_ends_at > now())) AS active_discounts,
  count(*) FILTER (WHERE discount_percent IS NOT NULL AND discount_percent > 0
                     AND discount_ends_at IS NOT NULL AND discount_ends_at <= now()) AS expired_discounts,
  count(*) AS total_products
FROM products;
