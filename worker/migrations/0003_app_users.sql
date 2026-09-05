-- ═══════════════════════════════════════════════════════════════
--  0003 — Add app_users
--
--  User directive (2026-09-05): default sync scope includes user_app
--  (app_users) with pull/push + outbox delta sync. The entity was
--  synced via Appwrite Cloud (mobile appwrite_config.dart:116,
--  outbox_dao.dart _entityTableMap, auth_local_store outbox ops) but
--  the Cloudflare layer dropped it entirely: no ENTITY_TABLES entry,
--  no D1 table — account changes never reached D1 and pulls would
--  advance the cursor past rows the client cannot land.
--
--  Column source of truth:
--    * local Drift table AppUsers (mobile/lib/services/local_db.dart,
--      schemaVersion 66) which mirrors the live Appwrite app_users
--      collection (schema_extract.json validFieldsPerCollection) in
--      snake_case. The collection's duplicate userType / user_type
--      pair maps to one user_type column (the creating code always
--      writes identical values — auth_local_store).
--
--  Conventions identical to schema.sql / 0002 (no sync_timestamp —
--  that column is Appwrite-only; booleans stored as INTEGER NOT NULL
--  DEFAULT 0/1; last_modified NOT NULL DEFAULT 0;
--  idx_<table>_updated / idx_<table>_deleted):
--
--    * id INTEGER PRIMARY KEY AUTOINCREMENT (server-generated)
--    * local_uuid TEXT NOT NULL UNIQUE (client identity — for
--      app_users this is the deterministic cloud doc id
--      `_cloudDocumentId(username)`, matching the outbox ops that
--      auth_local_store already enqueues)
--    * SyncFields columns identical to the Drift mixin
--    * NO FOREIGN KEY constraints — referential integrity is owned by
--      the app layer
--
--  Apply with: npm run db:migrate
-- ═══════════════════════════════════════════════════════════════

-- ─── app_users ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app_users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  local_uuid TEXT NOT NULL UNIQUE,
  username TEXT NOT NULL,
  password TEXT,
  full_name TEXT NOT NULL DEFAULT '',
  user_type TEXT NOT NULL DEFAULT '',
  permissions TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  last_login INTEGER,
  credentials_version INTEGER NOT NULL DEFAULT 0,
  role TEXT,
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
  device_id TEXT NOT NULL DEFAULT '',
  idempotency_key TEXT
);
CREATE INDEX IF NOT EXISTS idx_app_users_updated ON app_users(updated_at);
CREATE INDEX IF NOT EXISTS idx_app_users_deleted ON app_users(deleted_at);
CREATE INDEX IF NOT EXISTS idx_app_users_username ON app_users(username);
