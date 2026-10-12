-- ═══════════════════════════════════════════════════════════════
--  0004 — Rebuild devices as a sync-entity table
--
--  User directive (2026-09-05): devices joins the default sync scope
--  with pull/push + outbox delta sync. The old table was a narrow FCM
--  target list (id TEXT PK, no local_uuid, no SyncFields) — it could
--  not serve the sync protocol (createRecord/updateRecord anchor rows
--  by local_uuid; pull streams rows by the monotonic updated_at).
--
--  This migration rebuilds the table in place, PRESERVING existing
--  rows (FCM tokens must survive): each legacy row gets a
--  deterministic local_uuid ('device:' || device_id) so a later
--  outbox push from the owning device (local_uuid = its deviceId…
--  registered via /api/devices/register) can be de-duplicated by
--  device_id uniqueness without losing the token.
--
--  Column source of truth:
--    * local Drift table Devices (mobile/lib/services/local_db.dart,
--      schemaVersion 67) mirroring the live Appwrite devices
--      collection (appwrite_sync_utils.dart whitelist) in snake_case.
--    * device_id is BOTH the device identity and the SyncFields
--      writer column (unified — for a device row the writer IS the
--      device).
--
--  Conventions identical to schema.sql / 0002 / 0003 (booleans as
--  INTEGER NOT NULL DEFAULT 0/1; last_modified NOT NULL DEFAULT 0;
--  idx_<table>_updated / idx_<table>_deleted).
--
--  Writers: /api/devices/register (upsert by device_id, allocateUpdatedAt
--  via sync_clock), sync push/pull (ENTITY_TABLES), bulk migration.
--
--  Apply with: npm run db:migrate
-- ═══════════════════════════════════════════════════════════════

-- ─── devices (rebuild, rows preserved) ──────────────────────
CREATE TABLE devices_sync_rebuild (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  local_uuid TEXT NOT NULL UNIQUE,
  device_id TEXT NOT NULL UNIQUE,
  device_name TEXT NOT NULL DEFAULT '',
  device_model TEXT,
  device_type TEXT,
  os_version TEXT,
  platform TEXT,
  app_version TEXT,
  fcm_token TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  is_active INTEGER NOT NULL DEFAULT 1,
  last_seen TEXT,
  last_active INTEGER,
  -- SyncFields (Drift mixin mirror)
  server_id INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  last_modified INTEGER NOT NULL DEFAULT 0,
  created_at_iso TEXT,
  updated_at_iso TEXT,
  deleted_at_iso TEXT,
  created_at_epoch INTEGER NOT NULL DEFAULT 0,
  last_modified_epoch INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 1,
  origin TEXT NOT NULL DEFAULT 'local',
  vector_clock TEXT NOT NULL DEFAULT '{}',
  idempotency_key TEXT
);

INSERT INTO devices_sync_rebuild (
  local_uuid, device_id, device_name, platform, fcm_token, status,
  created_at, updated_at, last_modified, last_modified_epoch, version,
  origin
)
SELECT
  'device:' || device_id,
  device_id,
  COALESCE(device_name, ''),
  platform,
  fcm_token,
  COALESCE(status, 'active'),
  created_at,
  updated_at,
  updated_at,
  updated_at,
  1,
  'local'
FROM devices;

DROP TABLE devices;

ALTER TABLE devices_sync_rebuild RENAME TO devices;

CREATE INDEX IF NOT EXISTS idx_devices_status ON devices(status);
CREATE INDEX IF NOT EXISTS idx_devices_updated ON devices(updated_at);
CREATE INDEX IF NOT EXISTS idx_devices_deleted ON devices(deleted_at);
