-- ═══════════════════════════════════════════════════════════════
--  0005 — Schema parity: D1 mirrors the mobile Drift sync contract
--
--  Audit (2026-09-05): scripts/parity_audit.py diffed every Drift
--  table (mobile/lib/services/local_db.dart) against schema.sql.
--  Result: 26 contract columns missing across 8 tables, plus a
--  declared type conflict on price_adjustments.previous_value /
--  new_value (Wave 6b made the Drift columns RealColumn to match
--  the cloud 'double' contract and prevent 1500.75 truncation;
--  the worker schema stayed INTEGER).
--
--  Why this matters: the sync push path sends payload keys verbatim
--  and the worker filters them to table columns (database.ts
--  getTableColumns) — any column absent here is silently dropped,
--  and the pull path writes payload keys generically (_applyChange).
--  Missing columns = columns that can never sync, now or later.
--
--  Notes:
--  * SQLite cannot ALTER a column type → price_adjustments is
--    rebuilt in place, rows preserved (same pattern as 0004).
--    SQLite's INTEGER affinity already stored fractional payloads
--    as REAL, so no value rewriting is needed — this makes the
--    DECLARATION match the Drift/cloud contract.
--  * All added columns are nullable or defaulted → compatible with
--    existing rows and with the worker's NOT-NULL filler.
--
--  Apply with: npm run db:migrate
-- ═══════════════════════════════════════════════════════════════

-- ─── bookings: financial freeze metadata ────────────────────
ALTER TABLE bookings ADD COLUMN financial_frozen_at INTEGER;
ALTER TABLE bookings ADD COLUMN financial_hash TEXT;

-- ─── guest_infos ────────────────────────────────────────────
ALTER TABLE guest_infos ADD COLUMN guest_phone TEXT;

-- ─── booking_nights ─────────────────────────────────────────
ALTER TABLE booking_nights ADD COLUMN booking_uuid_cache TEXT;
ALTER TABLE booking_nights ADD COLUMN server_booking_id INTEGER;

-- ─── booking_price_adjustments ──────────────────────────────
ALTER TABLE booking_price_adjustments ADD COLUMN booking_uuid TEXT;
ALTER TABLE booking_price_adjustments ADD COLUMN applied_at INTEGER;

-- ─── payments: full void metadata + Option A attribution ────
ALTER TABLE payments ADD COLUMN void_reason TEXT;
ALTER TABLE payments ADD COLUMN is_immutable INTEGER NOT NULL DEFAULT 0;
ALTER TABLE payments ADD COLUMN received_by_user_id INTEGER;
ALTER TABLE payments ADD COLUMN received_by_name TEXT;
ALTER TABLE payments ADD COLUMN received_session_uuid TEXT;
ALTER TABLE payments ADD COLUMN received_by_cloud_id TEXT;

-- ─── debts: Wave-6 Appwrite contract columns ────────────────
ALTER TABLE debts ADD COLUMN guest_phone TEXT;
ALTER TABLE debts ADD COLUMN description TEXT;
ALTER TABLE debts ADD COLUMN status TEXT;
ALTER TABLE debts ADD COLUMN due_date TEXT;
ALTER TABLE debts ADD COLUMN booking_uuid_cache TEXT;
ALTER TABLE debts ADD COLUMN debtor_name TEXT;
ALTER TABLE debts ADD COLUMN amount REAL;
ALTER TABLE debts ADD COLUMN date TEXT;

-- ─── salary_carry_over_logs ─────────────────────────────────
ALTER TABLE salary_carry_over_logs ADD COLUMN from_cycle_id TEXT;
ALTER TABLE salary_carry_over_logs ADD COLUMN to_cycle_id TEXT;
ALTER TABLE salary_carry_over_logs ADD COLUMN carry_date TEXT;
ALTER TABLE salary_carry_over_logs ADD COLUMN performed_by TEXT;
ALTER TABLE salary_carry_over_logs ADD COLUMN hotel_day_key TEXT;

-- ─── price_adjustments: rebuild (type fix + 3 columns) ──────
CREATE TABLE price_adjustments_parity_rebuild (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_type TEXT NOT NULL,
  target_uuid TEXT NOT NULL,
  adjustment_type TEXT NOT NULL,
  -- Wave 6b: REAL per the Drift/cloud 'double' contract
  previous_value REAL NOT NULL,
  new_value REAL NOT NULL,
  reason TEXT,
  effective_date TEXT NOT NULL,
  applied_by TEXT NOT NULL,
  hotel_day_key TEXT NOT NULL,
  is_reversed INTEGER NOT NULL DEFAULT 0,
  reversed_at TEXT,
  reversed_by TEXT,
  adjustment_mode TEXT NOT NULL DEFAULT 'per_night',
  booking_uuid TEXT,
  applied_at INTEGER,
  local_uuid TEXT NOT NULL UNIQUE,
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

INSERT INTO price_adjustments_parity_rebuild (
  id, target_type, target_uuid, adjustment_type, previous_value,
  new_value, reason, effective_date, applied_by, hotel_day_key,
  is_reversed, reversed_at, reversed_by, adjustment_mode,
  local_uuid, server_id, created_at, updated_at, deleted_at,
  last_modified, created_at_iso, updated_at_iso, deleted_at_iso,
  created_at_epoch, last_modified_epoch, version, origin,
  vector_clock, device_id, idempotency_key
)
SELECT
  id, target_type, target_uuid, adjustment_type, previous_value,
  new_value, reason, effective_date, applied_by, hotel_day_key,
  is_reversed, reversed_at, reversed_by,
  -- legacy table has NO adjustment_mode yet — seed the declared default
  'per_night',
  local_uuid, server_id, created_at, updated_at, deleted_at,
  last_modified, created_at_iso, updated_at_iso, deleted_at_iso,
  created_at_epoch, last_modified_epoch, version, origin,
  vector_clock, device_id, idempotency_key
FROM price_adjustments;

DROP TABLE price_adjustments;
ALTER TABLE price_adjustments_parity_rebuild RENAME TO price_adjustments;

CREATE INDEX IF NOT EXISTS idx_price_adj_updated ON price_adjustments(updated_at);
CREATE INDEX IF NOT EXISTS idx_price_adj_target ON price_adjustments(target_type, target_uuid);
CREATE INDEX IF NOT EXISTS idx_price_adj_day ON price_adjustments(hotel_day_key);
