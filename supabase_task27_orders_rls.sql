-- ══════════════════════════════════════════════════════════════════════════
-- Zeina — Task 27: fix orders RLS (production checkout was 42501)
-- File:  supabase_task27_orders_rls.sql
-- Scope: RLS on the orders table WITHOUT exposing customer PII to anon.
--        Anonymous checkout now goes through a SECURITY DEFINER RPC that
--        only writes an allowlist of known columns; admin keeps full access
--        via an authenticated policy. 100% additive, 100% idempotent —
--        safe to re-run any number of times. No DELETE, no TRUNCATE, no
--        unrelated UPDATE.
--
-- Background: RLS was enabled on `orders` in a previous change with NO
-- policies attached, so every insert (INSERT + the follow-up SELECT for the
-- returned id) failed with Postgres 42501 "insufficient privilege". This
-- file lands the missing pieces:
--
--   1. `place_order(order_data jsonb)` — the anon-callable path. Reads only
--      known columns from the jsonb (name, phone, address, note, city,
--      delivery_fee_usd, items, total, has_tbd_items, status, discount_code,
--      discount_code_amount). Any other key in the jsonb is IGNORED — this
--      also obsoletes the client-side OPTIONAL_ORDER_FIELDS strip-and-retry
--      dance and blocks a compromised client from writing arbitrary columns.
--
--   2. Admin policy — logged-in admin (authenticated JWT) has full CRUD.
--      That's how admin.html continues to list / cycle status / delete.
--
--   3. NO anon SELECT / UPDATE / DELETE policies, and NO anon INSERT policy.
--      Anon cannot read a single order row — customer PII (name, phone,
--      address) is only visible to the logged-in owner.
--
-- Ordering rule reminder: the next supabase_consolidated_pending.sql MUST
-- re-include the pieces below so that if this file was skipped in an
-- environment, the consolidated file still closes the gap.
--
-- Run once in the Supabase SQL editor. Verify block at the very bottom.
-- ══════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
-- 1. Enable RLS on orders (no-op if already enabled)
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;


-- ══════════════════════════════════════════════════════════════════════════
-- 2. place_order(jsonb) — anon-safe checkout entry point
--
--    Reads a fixed allowlist of columns from the passed jsonb; anything else
--    is silently ignored. SECURITY DEFINER means the function runs as its
--    owner (postgres in Supabase) and bypasses RLS on the INSERT, so we can
--    grant EXECUTE to anon without granting a direct INSERT policy.
--
--    NULLIF(x, '') collapses missing-or-blank strings to NULL before the
--    type cast so numeric/boolean fields don't blow up on '' inputs. The
--    `status` default of 'new' matches what the client used to send.
-- ══════════════════════════════════════════════════════════════════════════
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

-- Explicit grants: strip the default PUBLIC EXECUTE, then hand it to the
-- two Supabase JWT roles the storefront and admin use.
REVOKE ALL   ON FUNCTION public.place_order(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.place_order(jsonb) TO anon, authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 3. Admin policy — full access for anyone with a Supabase Auth session.
--    admin.html uses sb.auth.signInWithPassword; that JWT lands as
--    auth.role() = 'authenticated' on every request.
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "orders_admin_all" ON public.orders;
CREATE POLICY "orders_admin_all"
  ON public.orders
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- NOTE: we deliberately do NOT create anon SELECT/UPDATE/DELETE policies,
-- and we do NOT create a direct anon INSERT policy. All customer inserts
-- flow through place_order() above; everything else is admin-only.

-- Belt-and-braces: revoke any stray table grants that might let anon read
-- rows via base-table privileges. RLS still blocks it, but zero-grants keeps
-- the Supabase security advisor quiet and encodes the intent clearly.
REVOKE ALL ON TABLE public.orders FROM anon;
GRANT  SELECT, INSERT, UPDATE, DELETE ON TABLE public.orders TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- VERIFY — every row should return >0 after the migration
-- ══════════════════════════════════════════════════════════════════════════
SELECT
  (SELECT relrowsecurity FROM pg_class
     WHERE relname='orders' AND relnamespace='public'::regnamespace)         AS orders_rls_enabled,
  (SELECT count(*) FROM pg_proc
     WHERE proname='place_order' AND pronamespace='public'::regnamespace)    AS place_order_fn_present,
  (SELECT count(*) FROM pg_policies
     WHERE schemaname='public' AND tablename='orders')                       AS orders_policy_count;
