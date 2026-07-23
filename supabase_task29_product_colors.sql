-- ══════════════════════════════════════════════════════════════════════════
-- Zeina — Task 29: product color options
-- File:  supabase_task29_product_colors.sql
-- Scope: adds a `colors` jsonb column to public.products. Column holds an
--        array of objects like:
--          [
--            { "name_en":"Dusty rose", "name_ar":"وردي", "hex":"#C48B9F" },
--            { "name_en":"Sage",       "name_ar":"مريمية","hex":"#8FA98A" }
--          ]
--        Empty array = no colors, product is single-color.
--
--        This is SEPARATE from the variant_group system. A product can have
--        BOTH sizes (its variant siblings) AND colors (in-row). Which color
--        was chosen travels with the cart line item in the orders.items
--        jsonb — no schema change to orders required.
--
--        100% additive, 100% idempotent — safe to re-run.
--
-- Ordering rule reminder: the next supabase_consolidated_pending.sql MUST
-- re-include the column addition below.
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS colors jsonb NOT NULL DEFAULT '[]'::jsonb;

/* Guardrail: colors must be an array. Anything else (object, string, null)
   is rejected at insert / update time, so the shipped client can trust
   Array.isArray(row.colors) without extra checks. */
ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_colors_is_array;
ALTER TABLE public.products
  ADD CONSTRAINT products_colors_is_array
    CHECK (jsonb_typeof(colors) = 'array');


-- ══════════════════════════════════════════════════════════════════════════
-- VERIFY
-- ══════════════════════════════════════════════════════════════════════════
SELECT
  (SELECT count(*) FROM information_schema.columns
     WHERE table_schema='public' AND table_name='products' AND column_name='colors') AS colors_col_present,
  (SELECT count(*) FROM information_schema.check_constraints
     WHERE constraint_name='products_colors_is_array')                              AS colors_array_check_present;
