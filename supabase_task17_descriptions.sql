-- ══════════════════════════════════════════════════════════════
-- Task 17: product descriptions (EN + AR) for the product edit
-- panel, quick pricing table, and import review queue.
-- Run once in the Supabase SQL editor. Safe to re-run.
-- ══════════════════════════════════════════════════════════════

ALTER TABLE products ADD COLUMN IF NOT EXISTS description_en text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS description_ar text;

SELECT
  count(*) FILTER (WHERE description_en IS NOT NULL AND description_en <> '') AS with_en,
  count(*) FILTER (WHERE description_ar IS NOT NULL AND description_ar <> '') AS with_ar,
  count(*) AS total
FROM products;
