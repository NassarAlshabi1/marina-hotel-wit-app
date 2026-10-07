-- 0014_sync_write_times.sql
-- Parity unification: ports branch3's 0014 migration to branch2.
-- Wall-clock conflict timestamps must not use the logical pull cursor.
-- Restore this table alongside entity data; rotate epoch after a server restore.
CREATE TABLE IF NOT EXISTS sync_write_times (
  entity TEXT NOT NULL,
  local_uuid TEXT NOT NULL,
  edited_at INTEGER NOT NULL,
  PRIMARY KEY (entity, local_uuid)
);
