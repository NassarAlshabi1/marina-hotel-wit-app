-- ═══════════════════════════════════════════════════════════════
--  0002 — Add inventory_items / inventory_transactions / blacklist
--
--  Gap closure (plan task 2.1 / D7): the Appwrite contract (27
--  collections) includes inventory_items, inventory_transactions and
--  blacklist; the worker's ENTITY_TABLES and D1 schema omitted them —
--  any inventory/blacklist record pushed or migrated would be lost.
--
--  Column source of truth:
--    * inventory_items / inventory_transactions:
--        perf branch mobile/lib/services/local_db.dart (Drift,
--        schemaVersion 65, classes InventoryItems / InventoryTransactions)
--        — snake_case mirror per plan D4.
--    * blacklist: has NO Drift table (cloud-only entity). Columns mirror
--        the Appwrite typed contract (appwrite_sync_utils.dart blacklist
--        whitelist) converted camelCase → snake_case.
--
--  Conventions identical to schema.sql (no sync_timestamp — that column
--  is Appwrite-only and does not exist in the Drift SyncFields mixin;
--  booleans stored as INTEGER NOT NULL DEFAULT 0/1; last_modified
--  NOT NULL DEFAULT 0; idx_<table>_updated / idx_<table>_deleted).
--
--    * id INTEGER PRIMARY KEY AUTOINCREMENT (server-generated)
--    * local_uuid TEXT NOT NULL UNIQUE (client identity)
--    * SyncFields columns identical to the Drift mixin
--    * NO FOREIGN KEY constraints — referential integrity is owned by
--      the app layer (migration client sends references as-is)
--
--  Apply with: npm run db:migrate
-- ═══════════════════════════════════════════════════════════════

-- ─── inventory_items ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS inventory_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  local_uuid TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  unit TEXT NOT NULL DEFAULT 'قطعة',
  category TEXT,
  quantity INTEGER NOT NULL DEFAULT 0,
  minimum_quantity INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
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
CREATE INDEX IF NOT EXISTS idx_inventory_items_updated ON inventory_items(updated_at);
CREATE INDEX IF NOT EXISTS idx_inventory_items_deleted ON inventory_items(deleted_at);
CREATE INDEX IF NOT EXISTS idx_inventory_items_active_name ON inventory_items(is_active, name);
CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_items_name ON inventory_items(name) WHERE deleted_at IS NULL;

-- ─── inventory_transactions ──────────────────────────────────
CREATE TABLE IF NOT EXISTS inventory_transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  local_uuid TEXT NOT NULL UNIQUE,
  item_local_uuid TEXT,
  item_id INTEGER NOT NULL,
  movement_type TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  balance_after INTEGER NOT NULL,
  note TEXT,
  user_id INTEGER,
  user_name TEXT,
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
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_updated ON inventory_transactions(updated_at);
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_deleted ON inventory_transactions(deleted_at);
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_item_date ON inventory_transactions(item_id, created_at DESC);

-- ─── blacklist ───────────────────────────────────────────────
-- Cloud-only entity (no Drift table): guests blacklisted across devices.
CREATE TABLE IF NOT EXISTS blacklist (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  local_uuid TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  nationality TEXT NOT NULL DEFAULT '',
  national_id TEXT,
  phone TEXT,
  reason TEXT,
  notes TEXT,
  reported_by TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  guest_name TEXT,
  guest_phone TEXT,
  guest_id_number TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  added_date TEXT,
  added_by TEXT,
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
CREATE INDEX IF NOT EXISTS idx_blacklist_updated ON blacklist(updated_at);
CREATE INDEX IF NOT EXISTS idx_blacklist_deleted ON blacklist(deleted_at);
CREATE INDEX IF NOT EXISTS idx_blacklist_national_id ON blacklist(national_id);
CREATE INDEX IF NOT EXISTS idx_blacklist_guest_id_number ON blacklist(guest_id_number);
