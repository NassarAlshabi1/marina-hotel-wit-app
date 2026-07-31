-- ═══════════════════════════════════════════════════════════════
--  Marina Hotel — Cloudflare D1 Database Schema
--  Production-ready schema with sync fields, indexes, and triggers
-- ═══════════════════════════════════════════════════════════════

-- ─── Users table (for JWT auth) ───────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'staff', -- 'admin', 'manager', 'staff'
  device_id TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

-- ─── Rooms ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rooms (
  id TEXT PRIMARY KEY,
  server_id TEXT,
  room_number TEXT NOT NULL UNIQUE,
  type TEXT NOT NULL,
  price REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'available',
  image_url TEXT,
  cleaning_status TEXT DEFAULT 'clean',
  requires_maintenance INTEGER DEFAULT 0,
  -- Sync fields
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  version INTEGER NOT NULL DEFAULT 1,
  device_id TEXT DEFAULT '',
  vector_clock TEXT DEFAULT '{}',
  origin TEXT DEFAULT 'local',
  idempotency_key TEXT
);

CREATE INDEX IF NOT EXISTS idx_rooms_updated ON rooms(updated_at);
CREATE INDEX IF NOT EXISTS idx_rooms_status ON rooms(status, deleted_at);
CREATE INDEX IF NOT EXISTS idx_rooms_deleted ON rooms(deleted_at);

-- ─── Bookings ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bookings (
  id TEXT PRIMARY KEY,
  server_id TEXT,
  room_number TEXT NOT NULL,
  guest_name TEXT NOT NULL,
  guest_phone TEXT NOT NULL,
  guest_nationality TEXT NOT NULL,
  guest_email TEXT,
  guest_address TEXT,
  checkin_date TEXT NOT NULL,
  checkout_date TEXT,
  actual_checkout TEXT,
  status TEXT NOT NULL,
  notes TEXT,
  discount REAL DEFAULT 0,
  discount_type TEXT DEFAULT 'per_night',
  expected_nights INTEGER DEFAULT 1,
  calculated_nights INTEGER DEFAULT 1,
  total_due REAL DEFAULT 0,
  total_paid REAL DEFAULT 0,
  remaining_balance REAL DEFAULT 0,
  is_fully_paid INTEGER DEFAULT 0,
  is_overdue INTEGER DEFAULT 0,
  hotel_day_checkin TEXT,
  hotel_day_checkout TEXT,
  -- Sync fields
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  version INTEGER NOT NULL DEFAULT 1,
  device_id TEXT DEFAULT '',
  vector_clock TEXT DEFAULT '{}',
  origin TEXT DEFAULT 'local',
  idempotency_key TEXT
);

CREATE INDEX IF NOT EXISTS idx_bookings_updated ON bookings(updated_at);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status, deleted_at);
CREATE INDEX IF NOT EXISTS idx_bookings_room ON bookings(room_number);
CREATE INDEX IF NOT EXISTS idx_bookings_deleted ON bookings(deleted_at);

-- ─── Payments ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS payments (
  id TEXT PRIMARY KEY,
  server_id TEXT,
  booking_id TEXT,
  room_number TEXT,
  amount REAL NOT NULL,
  payment_date TEXT NOT NULL,
  payment_method TEXT NOT NULL,
  revenue_type TEXT NOT NULL,
  notes TEXT,
  hotel_day_key TEXT,
  is_voided INTEGER DEFAULT 0,
  voided_at INTEGER,
  voided_by TEXT,
  -- Sync fields
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  version INTEGER NOT NULL DEFAULT 1,
  device_id TEXT DEFAULT '',
  vector_clock TEXT DEFAULT '{}',
  origin TEXT DEFAULT 'local',
  idempotency_key TEXT
);

CREATE INDEX IF NOT EXISTS idx_payments_updated ON payments(updated_at);
CREATE INDEX IF NOT EXISTS idx_payments_booking ON payments(booking_id);
CREATE INDEX IF NOT EXISTS idx_payments_deleted ON payments(deleted_at);

-- ─── Expenses ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS expenses (
  id TEXT PRIMARY KEY,
  server_id TEXT,
  expense_type TEXT NOT NULL,
  description TEXT NOT NULL,
  amount REAL NOT NULL,
  date TEXT NOT NULL,
  hotel_day_key TEXT,
  related_id INTEGER,
  cash_transaction_id INTEGER,
  employee_uuid TEXT,
  is_auto_generated INTEGER DEFAULT 0,
  -- Sync fields
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  version INTEGER NOT NULL DEFAULT 1,
  device_id TEXT DEFAULT '',
  vector_clock TEXT DEFAULT '{}',
  origin TEXT DEFAULT 'local',
  idempotency_key TEXT
);

CREATE INDEX IF NOT EXISTS idx_expenses_updated ON expenses(updated_at);
CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date);
CREATE INDEX IF NOT EXISTS idx_expenses_deleted ON expenses(deleted_at);

-- ─── Employees ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS employees (
  id TEXT PRIMARY KEY,
  server_id TEXT,
  name TEXT NOT NULL,
  basic_salary REAL NOT NULL,
  position TEXT DEFAULT 'موظف',
  phone TEXT DEFAULT '',
  hire_date TEXT DEFAULT '',
  status TEXT NOT NULL,
  termination_date TEXT,
  termination_reason TEXT,
  employee_id TEXT,
  -- Sync fields
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  version INTEGER NOT NULL DEFAULT 1,
  device_id TEXT DEFAULT '',
  vector_clock TEXT DEFAULT '{}',
  origin TEXT DEFAULT 'local',
  idempotency_key TEXT
);

CREATE INDEX IF NOT EXISTS idx_employees_updated ON employees(updated_at);
CREATE INDEX IF NOT EXISTS idx_employees_status ON employees(status, deleted_at);
CREATE INDEX IF NOT EXISTS idx_employees_deleted ON employees(deleted_at);

-- ─── Sync Log (audit trail for every change) ──────────────────
CREATE TABLE IF NOT EXISTS sync_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL, -- 'create', 'update', 'delete'
  version INTEGER NOT NULL,
  device_id TEXT,
  timestamp INTEGER NOT NULL,
  payload TEXT -- JSON snapshot of the change
);

CREATE INDEX IF NOT EXISTS idx_sync_log_entity ON sync_log(entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_sync_log_timestamp ON sync_log(timestamp);

-- ─── Sync Conflicts ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sync_conflicts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  local_payload TEXT NOT NULL, -- JSON
  remote_payload TEXT NOT NULL, -- JSON
  local_vector_clock TEXT,
  remote_vector_clock TEXT,
  resolution TEXT NOT NULL, -- 'last_write_wins', 'local_wins', 'remote_wins', 'manual'
  resolved_at INTEGER,
  created_at INTEGER NOT NULL,
  device_id TEXT
);

CREATE INDEX IF NOT EXISTS idx_conflicts_entity ON sync_conflicts(entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_conflicts_created ON sync_conflicts(created_at);

-- ─── Idempotency Log (prevents duplicate operations) ──────────
CREATE TABLE IF NOT EXISTS idempotency_log (
  key TEXT PRIMARY KEY,
  entity TEXT NOT NULL,
  operation TEXT NOT NULL,
  entity_id TEXT,
  processed_at INTEGER NOT NULL,
  response TEXT -- JSON response to return for duplicate requests
);

CREATE INDEX IF NOT EXISTS idx_idempotency_entity ON idempotency_log(entity, entity_id);
