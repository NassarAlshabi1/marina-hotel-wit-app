-- 0012 — per-write audit timestamps for sync observability.
-- No foreign-key dependency on entity tables; safe for legacy rows.
CREATE TABLE IF NOT EXISTS sync_write_times (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  idempotency_key TEXT NOT NULL UNIQUE,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL,
  device_id TEXT NOT NULL DEFAULT '',
  client_timestamp INTEGER,
  server_timestamp INTEGER NOT NULL,
  created_at INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_sync_write_times_entity
  ON sync_write_times(entity, entity_id, server_timestamp);
