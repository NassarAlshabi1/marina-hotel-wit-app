-- Marina Hotel Sync Worker — D1 initial schema
-- Mirrors mobile/lib/services/local_db.dart (Drift) + worker sync tables.
-- Generated from the Drift schema (21 sync entities + outbox + remote_meta + watermark + sync_log).

PRAGMA foreign_keys = ON;

-- ── SyncFields mixin (shared by all 21 entities) ─────────────────────────
-- local_uuid TEXT PRIMARY KEY | server_id INTEGER | created_at/updated_at INTEGER
-- deleted_at INTEGER | last_modified INTEGER | *_Iso TEXT | *_Epoch INTEGER
-- version INTEGER DEFAULT 1 | origin TEXT DEFAULT 'local'
-- vector_clock TEXT DEFAULT '{}' | device_id TEXT DEFAULT ''
-- idempotency_key TEXT

CREATE TABLE IF NOT EXISTS rooms (
  local_uuid TEXT PRIMARY KEY,
  server_id INTEGER,
  id INTEGER,
  room_number TEXT UNIQUE,
  type TEXT,
  price REAL,
  status TEXT,
  image_url TEXT,
  cleaning_status TEXT DEFAULT 'clean',
  last_cleaned_hotel_day TEXT,
  last_occupied_hotel_day TEXT,
  requires_maintenance INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  last_modified INTEGER NOT NULL,
  created_at_iso TEXT,
  updated_at_iso TEXT,
  deleted_at_iso TEXT,
  created_at_epoch INTEGER DEFAULT 0,
  last_modified_epoch INTEGER DEFAULT 0,
  version INTEGER DEFAULT 1,
  origin TEXT DEFAULT 'local',
  vector_clock TEXT DEFAULT '{}',
  device_id TEXT DEFAULT '',
  idempotency_key TEXT
);
CREATE INDEX IF NOT EXISTS idx_rooms_status ON rooms (status, cleaning_status);
CREATE INDEX IF NOT EXISTS idx_rooms_maintenance ON rooms (requires_maintenance);
CREATE INDEX IF NOT EXISTS idx_rooms_updated_at ON rooms (updated_at);

CREATE TABLE IF NOT EXISTS bookings (
  local_uuid TEXT PRIMARY KEY,
  server_id INTEGER,
  id INTEGER,
  server_booking_id INTEGER,
  room_number TEXT,
  guest_name TEXT,
  guest_phone TEXT,
  guest_id_type TEXT DEFAULT 'بطاقة شخصية',
  guest_id_number TEXT DEFAULT '',
  guest_id_issue_date TEXT,
  guest_id_issue_place TEXT,
  guest_nationality TEXT,
  guest_email TEXT,
  guest_address TEXT,
  checkin_date TEXT,
  checkout_date TEXT,
  actual_checkout TEXT,
  status TEXT,
  notes TEXT,
  discount REAL DEFAULT 0,
  discount_type TEXT DEFAULT 'per_night',
  discount_start_date TEXT,
  expected_nights INTEGER DEFAULT 1,
  calculated_nights INTEGER DEFAULT 1,
  total_nights_cached INTEGER DEFAULT 0,
  stay_duration_iso TEXT,
  last_night_epoch INTEGER,
  is_overdue INTEGER DEFAULT 0,
  needs_checkout_review INTEGER DEFAULT 0,
  total_due_cached REAL DEFAULT 0.0,
  total_paid_cached REAL DEFAULT 0.0,
  remaining_balance_cached REAL DEFAULT 0.0,
  is_fully_paid INTEGER DEFAULT 0,
  hotel_day_checkin TEXT,
  hotel_day_checkout TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  last_modified INTEGER NOT NULL,
  created_at_iso TEXT,
  updated_at_iso TEXT,
  deleted_at_iso TEXT,
  created_at_epoch INTEGER DEFAULT 0,
  last_modified_epoch INTEGER DEFAULT 0,
  version INTEGER DEFAULT 1,
  origin TEXT DEFAULT 'local',
  vector_clock TEXT DEFAULT '{}',
  device_id TEXT DEFAULT '',
  idempotency_key TEXT
);
CREATE INDEX IF NOT EXISTS idx_bookings_status_day ON bookings (status, hotel_day_checkin);
CREATE INDEX IF NOT EXISTS idx_bookings_room ON bookings (room_number);
CREATE INDEX IF NOT EXISTS idx_bookings_guest ON bookings (guest_name);
CREATE INDEX IF NOT EXISTS idx_bookings_deleted ON bookings (deleted_at);
CREATE INDEX IF NOT EXISTS idx_bookings_checkin ON bookings (checkin_date);
CREATE INDEX IF NOT EXISTS idx_bookings_updated_at ON bookings (updated_at);