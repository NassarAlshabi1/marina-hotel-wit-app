-- ═══════════════════════════════════════════════════════════════
--  0010 — sync_meta: server-side sync data generation (epoch)
--
--  Rotating this value after a restore/import forces all clients to
--  discard cursors that may point past rows with restored timestamps.
--  The worker also tolerates deployments without this table, so this
--  migration can be applied independently of deploying the Worker code.
--  Apply with: npm run db:migrate:sync-meta
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS sync_meta (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL,
  updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);

INSERT OR IGNORE INTO sync_meta (k, v)
VALUES ('epoch', lower(hex(randomblob(16))));
