-- ═══════════════════════════════════════════════════════════════
--  Marina Hotel — Cloudflare D1 Database Schema (v2 — aligned)
--  Fully aligned with mobile/lib/services/local_db.dart (Drift):
--    * every synced table carries local_uuid TEXT NOT NULL UNIQUE
--      (the client identity used by pull/push/migrate)
--    * id INTEGER PRIMARY KEY AUTOINCREMENT (server-generated,
--      never referenced by clients — clients strip `id` on pull)
--    * SyncFields columns identical to the Drift mixin
--    * NO FOREIGN KEY constraints: the migration client intentionally
--      sends reference columns as-is and D1 enforces FKs by default;
--      referential integrity is owned by the app layer.
--  Apply with: npm run db:init
-- ═══════════════════════════════════════════════════════════════

PRAGMA foreign_keys = OFF;

-- ─── Users (JWT auth) ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'staff', -- 'admin' | 'manager' | 'staff'
  device_id TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

-- ─── Global sync clock (monotonic unique updated_at allocator) ─
-- Guarantees every server-written updated_at is strictly greater
-- than every previous one, making the integer pull cursor lossless.
CREATE TABLE IF NOT EXISTS sync_clock (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  last_ts INTEGER NOT NULL
);
INSERT OR IGNORE INTO sync_clock (id, last_ts) VALUES (1, 0);

-- ─── Rate limiting (D1-based; no KV daily-write cap) ──────────
CREATE TABLE IF NOT EXISTS rate_limits (
  client_id TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (client_id, window_start)
);

-- ─── Devices (device registry + FCM targets — sync entity) ───
-- User directive 2026-09-05: devices joins the default sync scope with
-- pull/push + outbox delta sync. Columns mirror the local Drift table
-- Devices (local_db.dart, schemaVersion 67) which mirrors the live
-- Appwrite devices collection in snake_case. device_id is BOTH the
-- device identity and the SyncFields writer column (unified — for a
-- device row, the writer IS the device).
CREATE TABLE IF NOT EXISTS devices (
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
CREATE INDEX IF NOT EXISTS idx_devices_status ON devices(status);
CREATE INDEX IF NOT EXISTS idx_devices_updated ON devices(updated_at);
CREATE INDEX IF NOT EXISTS idx_devices_deleted ON devices(deleted_at);

-- ─── Sync Log (audit trail) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS sync_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL, -- 'create' | 'update' | 'delete'
  version INTEGER NOT NULL,
  device_id TEXT,
  timestamp INTEGER NOT NULL,
  payload TEXT
);
CREATE INDEX IF NOT EXISTS idx_sync_log_entity ON sync_log(entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_sync_log_timestamp ON sync_log(timestamp);

-- ─── Sync Conflicts ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sync_conflicts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  local_payload TEXT NOT NULL,
  remote_payload TEXT NOT NULL,
  local_vector_clock TEXT,
  remote_vector_clock TEXT,
  resolution TEXT NOT NULL,
  resolved_at INTEGER,
  created_at INTEGER NOT NULL,
  device_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_conflicts_entity ON sync_conflicts(entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_conflicts_created ON sync_conflicts(created_at);

-- ─── Idempotency Log ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS idempotency_log (
  key TEXT PRIMARY KEY,
  entity TEXT NOT NULL,
  operation TEXT NOT NULL,
  entity_id TEXT,
  processed_at INTEGER NOT NULL,
  response TEXT
);
CREATE INDEX IF NOT EXISTS idx_idempotency_entity ON idempotency_log(entity, entity_id);

-- ═══════════════════════════════════════════════════════════════
--  Synced entity tables (columns = Drift tables + SyncFields)
-- ═══════════════════════════════════════════════════════════════

-- ─── Rooms ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rooms (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  room_number TEXT NOT NULL UNIQUE,
  type TEXT NOT NULL,
  price REAL NOT NULL,
  status TEXT NOT NULL,
  image_url TEXT,
  cleaning_status TEXT NOT NULL DEFAULT 'clean',
  last_cleaned_hotel_day TEXT,
  last_occupied_hotel_day TEXT,
  requires_maintenance INTEGER NOT NULL DEFAULT 0,
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
CREATE INDEX IF NOT EXISTS idx_rooms_updated ON rooms(updated_at);
CREATE INDEX IF NOT EXISTS idx_rooms_status ON rooms(status, cleaning_status);
CREATE INDEX IF NOT EXISTS idx_rooms_deleted ON rooms(deleted_at);

-- ─── Employees ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS employees (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  basic_salary REAL NOT NULL,
  position TEXT NOT NULL DEFAULT 'موظف',
  phone TEXT NOT NULL DEFAULT '',
  hire_date TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL,
  termination_date TEXT,
  termination_reason TEXT,
  employee_id TEXT,
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
CREATE INDEX IF NOT EXISTS idx_employees_updated ON employees(updated_at);
CREATE INDEX IF NOT EXISTS idx_employees_name ON employees(name);
CREATE INDEX IF NOT EXISTS idx_employees_status ON employees(status);
CREATE INDEX IF NOT EXISTS idx_employees_deleted ON employees(deleted_at);

-- ─── Salary Cycles ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS salary_cycles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  employee_id INTEGER NOT NULL,
  cycle_key TEXT NOT NULL,
  hotel_day_start TEXT,
  hotel_day_end TEXT,
  expected_amount INTEGER NOT NULL DEFAULT 0,
  actual_paid INTEGER NOT NULL DEFAULT 0,
  remaining_amount INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'draft',
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
  idempotency_key TEXT,
  UNIQUE (employee_id, cycle_key)
);
CREATE INDEX IF NOT EXISTS idx_salary_cycles_updated ON salary_cycles(updated_at);

-- ─── Cash Transactions ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cash_transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  register_id INTEGER,
  transaction_type TEXT NOT NULL,
  amount REAL NOT NULL,
  reference_type TEXT,
  reference_id INTEGER,
  description TEXT,
  transaction_time TEXT NOT NULL,
  created_by INTEGER,
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
CREATE INDEX IF NOT EXISTS idx_cash_trans_updated ON cash_transactions(updated_at);
CREATE INDEX IF NOT EXISTS idx_cash_trans_type_time ON cash_transactions(transaction_type, transaction_time);
CREATE INDEX IF NOT EXISTS idx_cash_trans_ref ON cash_transactions(reference_type, reference_id);

-- ─── Bookings ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bookings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_booking_id INTEGER,
  room_number TEXT NOT NULL,
  guest_name TEXT NOT NULL,
  guest_phone TEXT NOT NULL,
  guest_id_type TEXT NOT NULL DEFAULT 'بطاقة شخصية',
  guest_id_number TEXT NOT NULL DEFAULT '',
  guest_id_issue_date TEXT,
  guest_id_issue_place TEXT,
  guest_nationality TEXT NOT NULL,
  guest_email TEXT,
  guest_address TEXT,
  checkin_date TEXT NOT NULL,
  checkout_date TEXT,
  actual_checkout TEXT,
  status TEXT NOT NULL,
  notes TEXT,
  discount REAL NOT NULL DEFAULT 0,
  discount_type TEXT NOT NULL DEFAULT 'per_night',
  discount_start_date TEXT,
  expected_nights INTEGER NOT NULL DEFAULT 1,
  calculated_nights INTEGER NOT NULL DEFAULT 1,
  total_nights_cached INTEGER NOT NULL DEFAULT 0,
  stay_duration_iso TEXT,
  last_night_epoch INTEGER,
  is_overdue INTEGER NOT NULL DEFAULT 0,
  needs_checkout_review INTEGER NOT NULL DEFAULT 0,
  total_due_cached REAL NOT NULL DEFAULT 0,
  total_paid_cached REAL NOT NULL DEFAULT 0,
  remaining_balance_cached REAL NOT NULL DEFAULT 0,
  is_fully_paid INTEGER NOT NULL DEFAULT 0,
  hotel_day_checkin TEXT,
  hotel_day_checkout TEXT,
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
CREATE INDEX IF NOT EXISTS idx_bookings_updated ON bookings(updated_at);
CREATE INDEX IF NOT EXISTS idx_bookings_status_day ON bookings(status, hotel_day_checkin);
CREATE INDEX IF NOT EXISTS idx_bookings_room ON bookings(room_number);
CREATE INDEX IF NOT EXISTS idx_bookings_guest ON bookings(guest_name);
CREATE INDEX IF NOT EXISTS idx_bookings_deleted ON bookings(deleted_at);
CREATE INDEX IF NOT EXISTS idx_bookings_checkin ON bookings(checkin_date);

-- ─── Guest Infos ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS guest_infos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  room_number TEXT NOT NULL,
  guest_name TEXT NOT NULL,
  nationality TEXT NOT NULL,
  id_number TEXT NOT NULL,
  id_type TEXT NOT NULL DEFAULT 'بطاقة شخصية',
  issue_date TEXT,
  issue_place TEXT,
  governorate TEXT,
  notes TEXT,
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
CREATE INDEX IF NOT EXISTS idx_guest_infos_updated ON guest_infos(updated_at);
CREATE INDEX IF NOT EXISTS idx_guest_infos_room ON guest_infos(room_number);

-- ─── Booking Notes ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS booking_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  booking_id INTEGER NOT NULL,
  note_text TEXT NOT NULL,
  alert_type TEXT NOT NULL,
  alert_until TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
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
CREATE INDEX IF NOT EXISTS idx_booking_notes_updated ON booking_notes(updated_at);
CREATE INDEX IF NOT EXISTS idx_booking_notes_booking ON booking_notes(booking_id);

-- ─── Booking Nights ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS booking_nights (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  booking_local_id INTEGER NOT NULL,
  hotel_day_key TEXT NOT NULL,
  night_start TEXT NOT NULL,
  night_end TEXT NOT NULL,
  nightly_rate REAL NOT NULL DEFAULT 0,
  sequence INTEGER NOT NULL DEFAULT 0,
  is_processed_by_auto_fix INTEGER NOT NULL DEFAULT 0,
  base_rate REAL NOT NULL DEFAULT 0,
  adjustment REAL NOT NULL DEFAULT 0,
  final_rate REAL NOT NULL DEFAULT 0,
  applied_adjustment_uuid TEXT,
  applied_adjustments_json TEXT,
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
  idempotency_key TEXT,
  UNIQUE (booking_local_id, hotel_day_key)
);
CREATE INDEX IF NOT EXISTS idx_booking_nights_updated ON booking_nights(updated_at);
CREATE INDEX IF NOT EXISTS idx_booking_nights_booking ON booking_nights(booking_local_id);

-- ─── Booking Price Adjustments ────────────────────────────────
CREATE TABLE IF NOT EXISTS booking_price_adjustments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  booking_local_uuid TEXT NOT NULL,
  booking_local_id INTEGER,
  room_number TEXT,
  adjustment_type INTEGER NOT NULL DEFAULT 0,
  adjustment_mode TEXT NOT NULL DEFAULT 'per_night',
  amount REAL NOT NULL DEFAULT 0,
  effective_hotel_day TEXT NOT NULL,
  end_hotel_day TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  reason TEXT,
  applied_by TEXT,
  cancelled_at TEXT,
  cancelled_by TEXT,
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
CREATE INDEX IF NOT EXISTS idx_bpa_updated ON booking_price_adjustments(updated_at);
CREATE INDEX IF NOT EXISTS idx_bpa_booking ON booking_price_adjustments(booking_local_uuid, is_active);
CREATE INDEX IF NOT EXISTS idx_bpa_dates ON booking_price_adjustments(effective_hotel_day, end_hotel_day);

-- ─── Payments ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_payment_id INTEGER,
  booking_local_id INTEGER,
  server_booking_id INTEGER,
  room_number TEXT,
  amount REAL NOT NULL,
  payment_date TEXT NOT NULL,
  notes TEXT,
  payment_method TEXT NOT NULL,
  revenue_type TEXT NOT NULL,
  cash_transaction_local_id INTEGER,
  cash_transaction_server_id INTEGER,
  reference_number TEXT,
  hotel_day_key TEXT,
  is_pending_balance INTEGER NOT NULL DEFAULT 0,
  linked_debt_uuid TEXT,
  booking_uuid_cache TEXT,
  discount_amount REAL,
  discount_start_date TEXT,
  is_voided INTEGER NOT NULL DEFAULT 0,
  voided_at INTEGER,
  voided_by TEXT,
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
CREATE INDEX IF NOT EXISTS idx_payments_updated ON payments(updated_at);
CREATE INDEX IF NOT EXISTS idx_payments_booking ON payments(booking_local_id, hotel_day_key);
CREATE INDEX IF NOT EXISTS idx_payments_room_day ON payments(room_number, hotel_day_key);
CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date);
CREATE INDEX IF NOT EXISTS idx_payments_revenue ON payments(revenue_type, hotel_day_key);
CREATE INDEX IF NOT EXISTS idx_payments_void ON payments(is_voided);
CREATE INDEX IF NOT EXISTS idx_payments_deleted ON payments(deleted_at);

-- ─── Expenses ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  expense_type TEXT NOT NULL,
  related_id INTEGER,
  description TEXT NOT NULL,
  amount REAL NOT NULL,
  date TEXT NOT NULL,
  cash_transaction_id INTEGER,
  hotel_day_key TEXT,
  category_uuid TEXT,
  cash_flow_uuid TEXT,
  is_auto_generated INTEGER NOT NULL DEFAULT 0,
  employee_uuid TEXT,
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
CREATE INDEX IF NOT EXISTS idx_expenses_updated ON expenses(updated_at);
CREATE INDEX IF NOT EXISTS idx_expenses_hotel_day ON expenses(hotel_day_key);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category_uuid);
CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date);
CREATE INDEX IF NOT EXISTS idx_expenses_deleted ON expenses(deleted_at);

-- ─── Debts ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS debts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  booking_local_id INTEGER,
  guest_name TEXT NOT NULL,
  checkin_date TEXT NOT NULL,
  checkout_date TEXT NOT NULL,
  date_recorded TEXT NOT NULL DEFAULT '',
  debt_reason TEXT NOT NULL DEFAULT '',
  total_amount REAL NOT NULL,
  paid_amount REAL NOT NULL,
  remaining_amount REAL NOT NULL,
  payment_date TEXT NOT NULL,
  is_settled INTEGER NOT NULL DEFAULT 0,
  pledge TEXT,
  pledge_type TEXT,
  note TEXT,
  debt_uuid TEXT,
  hotel_day_opened TEXT,
  hotel_day_closed TEXT,
  is_from_auto_fix INTEGER NOT NULL DEFAULT 0,
  settlement_confirmed INTEGER NOT NULL DEFAULT 0,
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
CREATE INDEX IF NOT EXISTS idx_debts_updated ON debts(updated_at);
CREATE INDEX IF NOT EXISTS idx_debts_status ON debts(is_settled, is_from_auto_fix);
CREATE INDEX IF NOT EXISTS idx_debts_guest ON debts(guest_name);
CREATE INDEX IF NOT EXISTS idx_debts_booking ON debts(booking_local_id);
CREATE INDEX IF NOT EXISTS idx_debts_payment_date ON debts(payment_date);
CREATE INDEX IF NOT EXISTS idx_debts_deleted ON debts(deleted_at);

-- ─── Salary Payments ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS salary_payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cycle_id INTEGER NOT NULL,
  amount INTEGER NOT NULL DEFAULT 0,
  hotel_day_key TEXT,
  payment_date_iso TEXT NOT NULL,
  method TEXT,
  is_auto_generated INTEGER NOT NULL DEFAULT 0,
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
CREATE INDEX IF NOT EXISTS idx_salary_payments_updated ON salary_payments(updated_at);
CREATE INDEX IF NOT EXISTS idx_salary_payments_cycle ON salary_payments(cycle_id, hotel_day_key);

-- ─── Salary Withdrawals ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS salary_withdrawals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  employee_id INTEGER NOT NULL,
  amount REAL NOT NULL,
  withdraw_date TEXT NOT NULL,
  reason TEXT,
  hotel_day_key TEXT,
  withdrawal_type TEXT,
  description TEXT,
  expense_id INTEGER,
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
CREATE INDEX IF NOT EXISTS idx_salary_withdrawals_updated ON salary_withdrawals(updated_at);
CREATE INDEX IF NOT EXISTS idx_salary_withdrawals_employee ON salary_withdrawals(employee_id);
CREATE INDEX IF NOT EXISTS idx_salary_withdrawals_expense ON salary_withdrawals(expense_id);
CREATE INDEX IF NOT EXISTS idx_salary_withdrawals_hotel_day ON salary_withdrawals(hotel_day_key);

-- ─── Salary Carry-Over Logs ───────────────────────────────────
CREATE TABLE IF NOT EXISTS salary_carry_over_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  employee_id INTEGER NOT NULL,
  amount REAL NOT NULL,
  previous_cycle_start TEXT NOT NULL,
  previous_cycle_end TEXT NOT NULL,
  new_cycle_start TEXT NOT NULL,
  new_cycle_end TEXT NOT NULL,
  reason TEXT NOT NULL,
  carried_at INTEGER NOT NULL,
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
CREATE INDEX IF NOT EXISTS idx_salary_carryover_updated ON salary_carry_over_logs(updated_at);
CREATE INDEX IF NOT EXISTS idx_salary_carryover_employee ON salary_carry_over_logs(employee_id);

-- ─── Shift Notes ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS shift_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'medium',
  shift_type TEXT NOT NULL DEFAULT 'all',
  is_read INTEGER NOT NULL DEFAULT 0,
  expires_at TEXT,
  created_by TEXT NOT NULL DEFAULT 'user',
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
CREATE INDEX IF NOT EXISTS idx_shift_notes_updated ON shift_notes(updated_at);
CREATE INDEX IF NOT EXISTS idx_shift_notes_created_by ON shift_notes(created_by);
CREATE INDEX IF NOT EXISTS idx_shift_notes_read ON shift_notes(is_read);
CREATE INDEX IF NOT EXISTS idx_shift_notes_priority ON shift_notes(priority);
CREATE INDEX IF NOT EXISTS idx_shift_notes_shift_type ON shift_notes(shift_type);

-- ─── Hotel Day Ledger ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS hotel_day_ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  hotel_day_key TEXT NOT NULL UNIQUE,
  total_income REAL NOT NULL DEFAULT 0,
  total_expenses REAL NOT NULL DEFAULT 0,
  pending_balances REAL NOT NULL DEFAULT 0,
  occupancy_rate REAL NOT NULL DEFAULT 0,
  bookings_processed INTEGER NOT NULL DEFAULT 0,
  payments_processed INTEGER NOT NULL DEFAULT 0,
  debts_processed INTEGER NOT NULL DEFAULT 0,
  expenses_processed INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'draft',
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
CREATE INDEX IF NOT EXISTS idx_hotel_day_ledger_updated ON hotel_day_ledger(updated_at);

-- ─── Price Adjustments ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS price_adjustments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_type TEXT NOT NULL,
  target_uuid TEXT NOT NULL,
  adjustment_type TEXT NOT NULL,
  previous_value INTEGER NOT NULL,
  new_value INTEGER NOT NULL,
  reason TEXT,
  effective_date TEXT NOT NULL,
  applied_by TEXT NOT NULL,
  hotel_day_key TEXT NOT NULL,
  is_reversed INTEGER NOT NULL DEFAULT 0,
  reversed_at TEXT,
  reversed_by TEXT,
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
CREATE INDEX IF NOT EXISTS idx_price_adj_updated ON price_adjustments(updated_at);
CREATE INDEX IF NOT EXISTS idx_price_adj_target ON price_adjustments(target_type, target_uuid);
CREATE INDEX IF NOT EXISTS idx_price_adj_day ON price_adjustments(hotel_day_key);

-- ─── Audit Logs ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  operation_type TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_uuid TEXT NOT NULL,
  entity_id INTEGER,
  previous_state TEXT,
  new_state TEXT,
  changed_fields TEXT,
  performed_by TEXT NOT NULL,
  ip_address TEXT,
  hotel_day_key TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  timestamp_iso TEXT NOT NULL,
  is_financial INTEGER NOT NULL DEFAULT 0,
  amount_impact INTEGER,
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
CREATE INDEX IF NOT EXISTS idx_audit_updated ON audit_logs(updated_at);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_type, entity_uuid);
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_audit_financial ON audit_logs(is_financial, hotel_day_key);

-- ─── Payment Voids ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS payment_voids (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  original_payment_uuid TEXT NOT NULL UNIQUE,
  original_payment_id INTEGER NOT NULL,
  booking_uuid TEXT NOT NULL,
  voided_amount INTEGER NOT NULL,
  void_reason TEXT NOT NULL,
  voided_by TEXT NOT NULL,
  voided_at INTEGER NOT NULL,
  voided_at_iso TEXT NOT NULL,
  hotel_day_key TEXT NOT NULL,
  reversal_payment_uuid TEXT,
  approved_by TEXT,
  note TEXT,
  original_amount REAL,
  payment_uuid TEXT,
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
CREATE INDEX IF NOT EXISTS idx_payment_voids_updated ON payment_voids(updated_at);
CREATE INDEX IF NOT EXISTS idx_void_booking ON payment_voids(booking_uuid);
CREATE INDEX IF NOT EXISTS idx_void_day ON payment_voids(hotel_day_key);
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

-- ─── app_users ──────────────────────────────────────────────
-- App users (auth accounts) — user directive 2026-09-05: default sync
-- scope includes user_app with pull/push + outbox delta sync. Columns
-- mirror the local Drift table AppUsers (local_db.dart, schemaVersion 66)
-- which mirrors the live Appwrite app_users collection
-- (schema_extract.json validFieldsPerCollection) in snake_case; the
-- collection's duplicate userType/user_type pair maps to one user_type
-- column (the creating code always writes identical values).
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
