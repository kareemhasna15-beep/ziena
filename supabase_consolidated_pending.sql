-- ══════════════════════════════════════════════════════════════════════════
-- Zeina — CONSOLIDATED PENDING MIGRATIONS
-- File:  supabase_consolidated_pending.sql
-- Scope: everything the shipped client already expects but that may still be
--        missing from the live Supabase schema. 100% additive, 100%
--        idempotent — safe to re-run any number of times. No DELETE, no
--        TRUNCATE, no unrelated UPDATE.
--
-- Ordering rule for future consolidated files: EVERY new consolidated SQL
-- MUST re-include the pending pieces below so that if the previous file was
-- skipped, the next one still closes the gap. If a section becomes redundant
-- (already applied on every environment) it may be dropped — but the file
-- must never REMOVE something that is still expected by shipped code.
--
-- Run once in the Supabase SQL editor. Verify block at the very bottom.
-- ══════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
-- 1. admin_error_log  (Bug 3 — required by the client-side logCheckoutError)
-- ══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS admin_error_log (
  id           bigserial PRIMARY KEY,
  occurred_at  timestamptz NOT NULL DEFAULT now(),
  category     text        NOT NULL,        -- 'order_insert' | 'order_insert_retry' | 'email_send' | ...
  error_code   text,                         -- e.g. Postgres SQLSTATE '23502', or 'PGRST204'
  error        text        NOT NULL,        -- human-readable message; the client now prefixes '[step=<phase>]'
  context      jsonb                         -- best-effort payload snapshot
);

CREATE INDEX IF NOT EXISTS admin_error_log_recent_idx
  ON admin_error_log (occurred_at DESC);

ALTER TABLE admin_error_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "err_log_insert_any" ON admin_error_log;
DROP POLICY IF EXISTS "err_log_read_admin" ON admin_error_log;

-- Anonymous checkout users must be able to log their own failures so the
-- owner can see the real reason. Reads stay restricted to logged-in admins.
CREATE POLICY "err_log_insert_any"
  ON admin_error_log FOR INSERT
  WITH CHECK (true);

CREATE POLICY "err_log_read_admin"
  ON admin_error_log FOR SELECT
  USING (auth.role() = 'authenticated');


-- ══════════════════════════════════════════════════════════════════════════
-- 2. site_settings  (Bug 2 — master switch + storefront config)
--    Contract: exactly ONE row keyed by singleton = TRUE. loadSiteConfig()
--    calls .limit(1).maybeSingle(); an empty table means "feature off".
-- ══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS site_settings (
  id                    bigserial PRIMARY KEY,
  singleton             boolean     NOT NULL DEFAULT true,
  store_open            boolean     NOT NULL DEFAULT true,   -- master switch (true = accept orders)
  master_switch         boolean,                             -- optional alias, some clients read this name
  store_closed_message  text,                                -- shown to the customer when store_open = false
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT site_settings_singleton_uq UNIQUE (singleton)
);

-- Seed the default row. If it exists, do nothing — never overwrite a live
-- config the owner has already tuned.
INSERT INTO site_settings (singleton, store_open, master_switch, store_closed_message)
VALUES (true, true, true, NULL)
ON CONFLICT (singleton) DO NOTHING;

ALTER TABLE site_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "site_settings_read_any"   ON site_settings;
DROP POLICY IF EXISTS "site_settings_write_admin" ON site_settings;

-- Everyone can read the master switch. Only authenticated admins can flip it.
CREATE POLICY "site_settings_read_any"
  ON site_settings FOR SELECT
  USING (true);

CREATE POLICY "site_settings_write_admin"
  ON site_settings FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');


-- ══════════════════════════════════════════════════════════════════════════
-- 3. discount_codes  (Task 24 forward-compat — the client already caches
--    this table at page load with a fail-soft try/catch, so seeding is
--    optional. Ships empty; adding codes never destructive.)
-- ══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS discount_codes (
  id          bigserial PRIMARY KEY,
  code        text        NOT NULL,
  percent     numeric     CHECK (percent IS NULL OR (percent >= 0 AND percent <= 90)),
  amount_usd  numeric     CHECK (amount_usd IS NULL OR amount_usd >= 0),
  active      boolean     NOT NULL DEFAULT true,
  expires_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS discount_codes_code_uidx
  ON discount_codes (upper(code));

ALTER TABLE discount_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "discount_codes_read_active" ON discount_codes;
DROP POLICY IF EXISTS "discount_codes_write_admin"  ON discount_codes;

-- Public read of active codes only. Full CRUD reserved for admins.
CREATE POLICY "discount_codes_read_active"
  ON discount_codes FOR SELECT
  USING (active = true AND (expires_at IS NULL OR expires_at > now()));

CREATE POLICY "discount_codes_write_admin"
  ON discount_codes FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');


-- ══════════════════════════════════════════════════════════════════════════
-- 4. orders — Task 24 + Task 26 forward-compat columns (schema-lag safety)
--    Client-side sendOrder retries without these if PGRST204 fires, but the
--    columns are trivial to add so we may as well.
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE orders ADD COLUMN IF NOT EXISTS has_tbd_items          boolean;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS discount_code          text;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS discount_code_amount   numeric;
-- Task 26: delivery city + fee
ALTER TABLE orders ADD COLUMN IF NOT EXISTS city                   text;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_fee_usd       numeric;
CREATE INDEX IF NOT EXISTS orders_city_idx ON orders (city);


-- ══════════════════════════════════════════════════════════════════════════
-- 5. products — Task 21 discount columns (re-included per re-run policy)
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE products ADD COLUMN IF NOT EXISTS discount_percent numeric
  CHECK (discount_percent IS NULL OR (discount_percent >= 0 AND discount_percent <= 90));
ALTER TABLE products ADD COLUMN IF NOT EXISTS discount_ends_at timestamptz;

CREATE INDEX IF NOT EXISTS products_discount_active_idx
  ON products (discount_percent)
  WHERE discount_percent IS NOT NULL AND discount_percent > 0;


-- ══════════════════════════════════════════════════════════════════════════
-- 6. products — Task 17 descriptions (re-included per re-run policy)
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE products ADD COLUMN IF NOT EXISTS description_en text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS description_ar text;


-- ══════════════════════════════════════════════════════════════════════════
-- 7. products — Task 8 sub-category & Task 2 variants (re-included)
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE products ADD COLUMN IF NOT EXISTS sub_category      text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS variant_group     text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS variant_label_en  text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS variant_label_ar  text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS variant_order     integer;


-- ══════════════════════════════════════════════════════════════════════════
-- 8. Task 25 forward-compat — categories catalog table (empty; storefront
--    still derives display names from sub_category, so this is purely
--    additive scaffolding).
-- ══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS categories (
  id           bigserial PRIMARY KEY,
  slug         text NOT NULL,
  name_en      text NOT NULL,
  name_ar      text,
  sort_order   integer NOT NULL DEFAULT 0,
  active       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS categories_slug_uidx ON categories (slug);

ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "categories_read_any"    ON categories;
DROP POLICY IF EXISTS "categories_write_admin" ON categories;
CREATE POLICY "categories_read_any"    ON categories FOR SELECT USING (true);
CREATE POLICY "categories_write_admin" ON categories FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');


-- ══════════════════════════════════════════════════════════════════════════
-- 9. orders RLS + place_order RPC (Task 27 — re-included per re-run policy)
--    Anon calls place_order(jsonb) which allow-lists a fixed set of columns
--    and returns the new order id. Admin keeps full access via the
--    authenticated policy. NO anon SELECT/UPDATE/DELETE, NO direct anon
--    INSERT — checkout was silently 42501 without this.
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.place_order(order_data jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  new_id bigint;
BEGIN
  INSERT INTO public.orders (
    name, phone, address, note,
    city, delivery_fee_usd,
    items, total,
    has_tbd_items, status,
    discount_code, discount_code_amount
  ) VALUES (
    NULLIF(order_data->>'name',                 ''),
    NULLIF(order_data->>'phone',                ''),
    NULLIF(order_data->>'address',              ''),
    NULLIF(order_data->>'note',                 ''),
    NULLIF(order_data->>'city',                 ''),
    NULLIF(order_data->>'delivery_fee_usd',     '')::numeric,
    COALESCE(order_data->'items',               '[]'::jsonb),
    NULLIF(order_data->>'total',                '')::numeric,
    NULLIF(order_data->>'has_tbd_items',        '')::boolean,
    COALESCE(NULLIF(order_data->>'status', ''), 'new'),
    NULLIF(order_data->>'discount_code',        ''),
    NULLIF(order_data->>'discount_code_amount', '')::numeric
  )
  RETURNING id INTO new_id;
  RETURN new_id;
END;
$$;

REVOKE ALL   ON FUNCTION public.place_order(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.place_order(jsonb) TO anon, authenticated;

DROP POLICY IF EXISTS "orders_admin_all" ON public.orders;
CREATE POLICY "orders_admin_all"
  ON public.orders
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

REVOKE ALL ON TABLE public.orders FROM anon;
GRANT  SELECT, INSERT, UPDATE, DELETE ON TABLE public.orders TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- VERIFY — run this block after the migration; every row should return >0
-- (or 0 for admin_error_log if nothing has crashed yet, which is fine).
-- ══════════════════════════════════════════════════════════════════════════
SELECT
  (SELECT count(*) FROM admin_error_log)                                  AS admin_error_log_rows,
  (SELECT count(*) FROM site_settings)                                    AS site_settings_rows,
  (SELECT store_open FROM site_settings LIMIT 1)                          AS store_open,
  (SELECT count(*) FROM discount_codes)                                   AS discount_codes_rows,
  (SELECT count(*) FROM information_schema.columns
     WHERE table_name='orders' AND column_name IN
       ('has_tbd_items','discount_code','discount_code_amount',
        'city','delivery_fee_usd'))                                      AS orders_new_cols,
  (SELECT count(*) FROM information_schema.columns
     WHERE table_name='products' AND column_name IN
       ('discount_percent','discount_ends_at','description_en',
        'description_ar','sub_category','variant_group','variant_label_en',
        'variant_label_ar','variant_order'))                              AS products_expected_cols,
  (SELECT count(*) FROM categories)                                       AS categories_rows,
  (SELECT relrowsecurity FROM pg_class
     WHERE relname='orders' AND relnamespace='public'::regnamespace)      AS orders_rls_enabled,
  (SELECT count(*) FROM pg_proc
     WHERE proname='place_order' AND pronamespace='public'::regnamespace) AS place_order_fn_present,
  (SELECT count(*) FROM pg_policies
     WHERE schemaname='public' AND tablename='orders')                    AS orders_policy_count;
