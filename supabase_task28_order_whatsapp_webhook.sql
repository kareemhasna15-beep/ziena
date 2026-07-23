-- ══════════════════════════════════════════════════════════════════════════
-- Zeina — Task 28: database webhook that POSTs new orders to the
--                  order-whatsapp Edge Function (owner push notification)
-- File:  supabase_task28_order_whatsapp_webhook.sql
-- Scope: adds an AFTER INSERT trigger on public.orders that calls the
--        supabase Edge Function via pg_net.http_post. 100% additive,
--        100% idempotent — safe to re-run. Does NOT modify data.
--
-- Prerequisite: deploy the function first (see supabase/functions/order-
-- whatsapp/index.ts and the deploy checklist in the Task 1 commit summary).
--
-- The trigger sends a Supabase-Database-Webhook-shaped body:
--   { type: 'INSERT', table: 'orders', record: {…} }
-- so the Edge Function code works whether it's invoked from this trigger OR
-- from a dashboard-configured Supabase Database Webhook.
--
-- CONFIG rows live in a plain settings table so the URL and secret can be
-- rotated later without a migration. Two rows required:
--   name = 'order_whatsapp_url'     value = 'https://<ref>.functions.supabase.co/order-whatsapp'
--   name = 'order_whatsapp_secret'  value = '<same value as WEBHOOK_SECRET in the function>'
-- If either row is missing, the trigger no-ops silently — checkout keeps
-- working. Do the seed via UPSERT from the SQL editor after deploy.
--
-- Ordering rule reminder: the next supabase_consolidated_pending.sql MUST
-- re-include the pieces below.
-- ══════════════════════════════════════════════════════════════════════════

-- pg_net gives us `net.http_post` from inside SQL. Bundled with Supabase but
-- not enabled by default on every project.
CREATE EXTENSION IF NOT EXISTS pg_net;


-- ══════════════════════════════════════════════════════════════════════════
-- 1. webhook_config — plain key/value settings the trigger reads at call
--    time. Not RLS-exposed to anon; only used by the SECURITY DEFINER
--    function below.
-- ══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.webhook_config (
  name        text PRIMARY KEY,
  value       text NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.webhook_config ENABLE ROW LEVEL SECURITY;

/* No policies — only SECURITY DEFINER functions read this table. Anon and
   authenticated users get zero access. */
REVOKE ALL ON TABLE public.webhook_config FROM PUBLIC, anon, authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 2. notify_order_whatsapp() — trigger function that POSTs the new row to
--    the Edge Function. Non-blocking (pg_net is async), errors are logged
--    to net._http_response so a failed webhook never rolls back the INSERT.
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.notify_order_whatsapp()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, net
AS $$
DECLARE
  fn_url    text;
  fn_secret text;
  req_id    bigint;
BEGIN
  SELECT value INTO fn_url     FROM public.webhook_config WHERE name = 'order_whatsapp_url';
  SELECT value INTO fn_secret  FROM public.webhook_config WHERE name = 'order_whatsapp_secret';
  IF fn_url IS NULL OR fn_url = '' THEN
    /* Not configured yet — silently skip. Do NOT raise; checkout must not
       fail because a notifier isn't wired. */
    RETURN NEW;
  END IF;

  SELECT net.http_post(
    url     := fn_url,
    body    := jsonb_build_object(
                 'type',   'INSERT',
                 'table',  'orders',
                 'record', row_to_json(NEW)::jsonb
               ),
    headers := jsonb_build_object(
                 'Content-Type',      'application/json',
                 'X-Webhook-Secret',  COALESCE(fn_secret, '')
               ),
    timeout_milliseconds := 5000
  ) INTO req_id;

  RETURN NEW;
END;
$$;


-- ══════════════════════════════════════════════════════════════════════════
-- 3. Attach the trigger. Idempotent via DROP-IF-EXISTS then CREATE.
-- ══════════════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS orders_whatsapp_notify ON public.orders;
CREATE TRIGGER orders_whatsapp_notify
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_order_whatsapp();


-- ══════════════════════════════════════════════════════════════════════════
-- 4. VERIFY — should return 1 for every row after apply.
-- ══════════════════════════════════════════════════════════════════════════
SELECT
  (SELECT count(*) FROM pg_extension WHERE extname='pg_net')                          AS pg_net_installed,
  (SELECT count(*) FROM pg_trigger
     WHERE tgname='orders_whatsapp_notify' AND NOT tgisinternal)                       AS trigger_present,
  (SELECT count(*) FROM pg_proc
     WHERE proname='notify_order_whatsapp' AND pronamespace='public'::regnamespace)    AS fn_present,
  (SELECT count(*) FROM information_schema.tables
     WHERE table_schema='public' AND table_name='webhook_config')                     AS config_table_present;


-- ══════════════════════════════════════════════════════════════════════════
-- After you deploy the Edge Function AND set its secrets, seed the two
-- config rows (run this snippet in the SQL editor with your real values):
--
--   INSERT INTO public.webhook_config (name, value) VALUES
--     ('order_whatsapp_url',    'https://<project-ref>.functions.supabase.co/order-whatsapp'),
--     ('order_whatsapp_secret', '<same value as WEBHOOK_SECRET in the function>')
--   ON CONFLICT (name) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
--
-- To disable the notifier without dropping anything: DELETE FROM
-- public.webhook_config WHERE name = 'order_whatsapp_url';
-- ══════════════════════════════════════════════════════════════════════════
