-- ══════════════════════════════════════════════════════════════
-- Checkout hotfix: admin error log for order-insert failures.
-- Additive only — CREATE TABLE + policies, no DELETE / TRUNCATE.
-- Run once in the Supabase SQL editor.
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS admin_error_log (
  id           bigserial PRIMARY KEY,
  occurred_at  timestamptz NOT NULL DEFAULT now(),
  category     text        NOT NULL,               -- 'order_insert' | 'email_send' | ...
  error_code   text,                                -- e.g. Postgres SQLSTATE '23502'
  error        text        NOT NULL,               -- human-readable message
  context      jsonb                                -- best-effort payload snapshot
);

CREATE INDEX IF NOT EXISTS admin_error_log_recent_idx
  ON admin_error_log (occurred_at DESC);

ALTER TABLE admin_error_log ENABLE ROW LEVEL SECURITY;

-- Idempotent policy setup
DROP POLICY IF EXISTS "err_log_insert_any" ON admin_error_log;
DROP POLICY IF EXISTS "err_log_read_admin" ON admin_error_log;

CREATE POLICY "err_log_insert_any"
  ON admin_error_log FOR INSERT
  WITH CHECK (true);

CREATE POLICY "err_log_read_admin"
  ON admin_error_log FOR SELECT
  USING (auth.role() = 'authenticated');

-- Verify
SELECT count(*) AS logged_errors FROM admin_error_log;
