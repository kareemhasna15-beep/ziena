-- ══════════════════════════════════════════════════════════════
-- Task 10: order email failure log (optional but useful)
-- Run once in the Supabase SQL editor. Safe to re-run.
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS order_email_failures (
  id           bigserial PRIMARY KEY,
  order_id     bigint,
  error        text,
  occurred_at  timestamptz DEFAULT now()
);

-- RLS: anon can INSERT (so the site logs failures when EmailJS errors client-side),
--      authenticated (admin) can SELECT.
ALTER TABLE order_email_failures ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "email_fail_insert_any"   ON order_email_failures;
DROP POLICY IF EXISTS "email_fail_read_admin"   ON order_email_failures;

CREATE POLICY "email_fail_insert_any"
  ON order_email_failures FOR INSERT
  WITH CHECK (true);

CREATE POLICY "email_fail_read_admin"
  ON order_email_failures FOR SELECT
  USING (auth.role() = 'authenticated');

SELECT count(*) AS existing_failures FROM order_email_failures;
