-- ============================================================================
-- Marina Hotel - Supabase Database Schema
-- ملف DDL الكامل للهجرة من PocketBase إلى Supabase
-- Initial Schema Migration - Full DDL
-- ============================================================================

-- Enable UUID extension
-- تفعيل امتداد UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- ROOMS TABLE - جدول الغرف
-- ============================================================================
CREATE TABLE IF NOT EXISTS rooms (
  -- Primary Key
  id BIGSERIAL PRIMARY KEY,
  
  -- Business Fields - الحقول الأساسية
  room_number TEXT NOT NULL UNIQUE,
  type TEXT NOT NULL,
  price NUMERIC(10, 2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'شاغرة',
  image_url TEXT,
  
  -- Sync Fields - حقول المزامنة
  local_uuid UUID NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
  server_id BIGINT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  last_modified TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  version INTEGER NOT NULL DEFAULT 1,
  origin TEXT NOT NULL DEFAULT 'local',
  
  -- Constraints
  CONSTRAINT rooms_status_check CHECK (status IN ('شاغرة', 'محجوزة', 'مشغولة', 'صيانة')),
  CONSTRAINT rooms_origin_check CHECK (origin IN ('local', 'server'))
);

-- Indexes for Rooms
CREATE INDEX idx_rooms_room_number ON rooms(room_number) WHERE deleted_at IS NULL;
CREATE INDEX idx_rooms_status ON rooms(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_rooms_local_uuid ON rooms(local_uuid);
CREATE INDEX idx_rooms_server_id ON rooms(server_id) WHERE server_id IS NOT NULL;
CREATE INDEX idx_rooms_last_modified ON rooms(last_modified);
CREATE INDEX idx_rooms_deleted_at ON rooms(deleted_at) WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- BOOKINGS TABLE - جدول الحجوزات
-- ============================================================================
CREATE TABLE IF NOT EXISTS bookings (
  -- Primary Key
  id BIGSERIAL PRIMARY KEY,
  
  -- Business Fields - الحقول الأساسية
  server_booking_id BIGINT UNIQUE,
  room_number TEXT NOT NULL REFERENCES rooms(room_number) ON DELETE CASCADE,
  
  -- Guest Information - معلومات النزيل
  guest_name TEXT NOT NULL,
  guest_phone TEXT NOT NULL,
  guest_id_type TEXT NOT NULL DEFAULT 'بطاقة شخصية',
  guest_id_number TEXT NOT NULL DEFAULT '',
  guest_id_issue_date TEXT,
  guest_id_issue_place TEXT,
  guest_nationality TEXT NOT NULL,
  guest_email TEXT,
  guest_address TEXT,
  
  -- Booking Dates - تواريخ الحجز
  checkin_date TIMESTAMPTZ NOT NULL,
  checkout_date TIMESTAMPTZ,
  actual_checkout TIMESTAMPTZ,
  
  -- Booking Status - حالة الحجز
  status TEXT NOT NULL DEFAULT 'محجوزة',
  notes TEXT,
  
  -- Nights Calculation - حساب الليالي
  expected_nights INTEGER NOT NULL DEFAULT 1,
  calculated_nights INTEGER NOT NULL DEFAULT 1,
  
  -- Sync Fields - حقول المزامنة
  local_uuid UUID NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
  server_id BIGINT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  last_modified TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  version INTEGER NOT NULL DEFAULT 1,
  origin TEXT NOT NULL DEFAULT 'local',
  
  -- Constraints
  CONSTRAINT bookings_status_check CHECK (status IN ('محجوزة', 'حالية', 'مغادرة', 'ملغاة')),
  CONSTRAINT bookings_origin_check CHECK (origin IN ('local', 'server'))
);

-- Indexes for Bookings
CREATE INDEX idx_bookings_room_number ON bookings(room_number) WHERE deleted_at IS NULL;
CREATE INDEX idx_bookings_status ON bookings(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_bookings_server_booking_id ON bookings(server_booking_id) WHERE server_booking_id IS NOT NULL;
CREATE INDEX idx_bookings_local_uuid ON bookings(local_uuid);
CREATE INDEX idx_bookings_server_id ON bookings(server_id) WHERE server_id IS NOT NULL;
CREATE INDEX idx_bookings_last_modified ON bookings(last_modified);
CREATE INDEX idx_bookings_checkin_date ON bookings(checkin_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_bookings_checkout_date ON bookings(checkout_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_bookings_deleted_at ON bookings(deleted_at) WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- BOOKING_NOTES TABLE - جدول ملاحظات الحجوزات
-- ============================================================================
CREATE TABLE IF NOT EXISTS booking_notes (
  -- Primary Key
  id BIGSERIAL PRIMARY KEY,
  
  -- Business Fields - الحقول الأساسية
  booking_id BIGINT NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  note_text TEXT NOT NULL,
  alert_type TEXT NOT NULL DEFAULT 'low',
  alert_until TIMESTAMPTZ,
  is_active INTEGER NOT NULL DEFAULT 1,
  
  -- Sync Fields - حقول المزامنة
  local_uuid UUID NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
  server_id BIGINT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  last_modified TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  version INTEGER NOT NULL DEFAULT 1,
  origin TEXT NOT NULL DEFAULT 'local',
  
  -- Constraints
  CONSTRAINT booking_notes_alert_type_check CHECK (alert_type IN ('low', 'medium', 'high', 'urgent')),
  CONSTRAINT booking_notes_origin_check CHECK (origin IN ('local', 'server'))
);

-- Indexes for Booking Notes
CREATE INDEX idx_booking_notes_booking_id ON booking_notes(booking_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_booking_notes_alert_type ON booking_notes(alert_type) WHERE is_active = 1 AND deleted_at IS NULL;
CREATE INDEX idx_booking_notes_local_uuid ON booking_notes(local_uuid);
CREATE INDEX idx_booking_notes_server_id ON booking_notes(server_id) WHERE server_id IS NOT NULL;
CREATE INDEX idx_booking_notes_last_modified ON booking_notes(last_modified);
CREATE INDEX idx_booking_notes_deleted_at ON booking_notes(deleted_at) WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- EMPLOYEES TABLE - جدول الموظفين
-- ============================================================================
CREATE TABLE IF NOT EXISTS employees (
  -- Primary Key
  id BIGSERIAL PRIMARY KEY,
  
  -- Business Fields - الحقول الأساسية
  name TEXT NOT NULL,
  basic_salary NUMERIC(10, 2) NOT NULL DEFAULT 0,
  position TEXT NOT NULL DEFAULT 'موظف',
  phone TEXT NOT NULL DEFAULT '',
  hire_date TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'active',
  
  -- Sync Fields - حقول المزامنة
  local_uuid UUID NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
  server_id BIGINT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  last_modified TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  version INTEGER NOT NULL DEFAULT 1,
  origin TEXT NOT NULL DEFAULT 'local',
  
  -- Constraints
  CONSTRAINT employees_status_check CHECK (status IN ('active', 'inactive', 'terminated')),
  CONSTRAINT employees_origin_check CHECK (origin IN ('local', 'server'))
);

-- Indexes for Employees
CREATE INDEX idx_employees_status ON employees(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_employees_local_uuid ON employees(local_uuid);
CREATE INDEX idx_employees_server_id ON employees(server_id) WHERE server_id IS NOT NULL;
CREATE INDEX idx_employees_last_modified ON employees(last_modified);
CREATE INDEX idx_employees_deleted_at ON employees(deleted_at) WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- EXPENSES TABLE - جدول المصروفات
-- ============================================================================
CREATE TABLE IF NOT EXISTS expenses (
  -- Primary Key
  id BIGSERIAL PRIMARY KEY,
  
  -- Business Fields - الحقول الأساسية
  expense_type TEXT NOT NULL,
  related_id BIGINT,
  description TEXT NOT NULL,
  amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
  date TEXT NOT NULL,
  cash_transaction_id BIGINT,
  
  -- Sync Fields - حقول المزامنة
  local_uuid UUID NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
  server_id BIGINT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  last_modified TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  version INTEGER NOT NULL DEFAULT 1,
  origin TEXT NOT NULL DEFAULT 'local',
  
  -- Constraints
  CONSTRAINT expenses_expense_type_check CHECK (expense_type IN ('salary', 'maintenance', 'utilities', 'supplies', 'other')),
  CONSTRAINT expenses_origin_check CHECK (origin IN ('local', 'server'))
);

-- Indexes for Expenses
CREATE INDEX idx_expenses_expense_type ON expenses(expense_type) WHERE deleted_at IS NULL;
CREATE INDEX idx_expenses_date ON expenses(date) WHERE deleted_at IS NULL;
CREATE INDEX idx_expenses_local_uuid ON expenses(local_uuid);
CREATE INDEX idx_expenses_server_id ON expenses(server_id) WHERE server_id IS NOT NULL;
CREATE INDEX idx_expenses_last_modified ON expenses(last_modified);
CREATE INDEX idx_expenses_deleted_at ON expenses(deleted_at) WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- CASH_TRANSACTIONS TABLE - جدول المعاملات النقدية
-- ============================================================================
CREATE TABLE IF NOT EXISTS cash_transactions (
  -- Primary Key
  id BIGSERIAL PRIMARY KEY,
  
  -- Business Fields - الحقول الأساسية
  register_id BIGINT,
  transaction_type TEXT NOT NULL,
  amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
  reference_type TEXT,
  reference_id BIGINT,
  description TEXT,
  transaction_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by BIGINT,
  
  -- Sync Fields - حقول المزامنة
  local_uuid UUID NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
  server_id BIGINT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  last_modified TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  version INTEGER NOT NULL DEFAULT 1,
  origin TEXT NOT NULL DEFAULT 'local',
  
  -- Constraints
  CONSTRAINT cash_transactions_type_check CHECK (transaction_type IN ('income', 'expense', 'opening_balance', 'closing_balance', 'adjustment')),
  CONSTRAINT cash_transactions_origin_check CHECK (origin IN ('local', 'server'))
);

-- Indexes for Cash Transactions
CREATE INDEX idx_cash_transactions_type ON cash_transactions(transaction_type) WHERE deleted_at IS NULL;
CREATE INDEX idx_cash_transactions_time ON cash_transactions(transaction_time) WHERE deleted_at IS NULL;
CREATE INDEX idx_cash_transactions_reference ON cash_transactions(reference_type, reference_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_cash_transactions_local_uuid ON cash_transactions(local_uuid);
CREATE INDEX idx_cash_transactions_server_id ON cash_transactions(server_id) WHERE server_id IS NOT NULL;
CREATE INDEX idx_cash_transactions_last_modified ON cash_transactions(last_modified);
CREATE INDEX idx_cash_transactions_deleted_at ON cash_transactions(deleted_at) WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- PAYMENTS TABLE - جدول الدفعات
-- ============================================================================
CREATE TABLE IF NOT EXISTS payments (
  -- Primary Key
  id BIGSERIAL PRIMARY KEY,
  
  -- Business Fields - الحقول الأساسية
  server_payment_id BIGINT UNIQUE,
  booking_local_id BIGINT REFERENCES bookings(id) ON DELETE CASCADE,
  server_booking_id BIGINT,
  room_number TEXT,
  amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
  payment_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes TEXT,
  payment_method TEXT NOT NULL DEFAULT 'نقدي',
  revenue_type TEXT NOT NULL DEFAULT 'room',
  cash_transaction_local_id BIGINT REFERENCES cash_transactions(id) ON DELETE SET NULL,
  cash_transaction_server_id BIGINT,
  reference_number TEXT,
  
  -- Sync Fields - حقول المزامنة
  local_uuid UUID NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
  server_id BIGINT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  last_modified TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  version INTEGER NOT NULL DEFAULT 1,
  origin TEXT NOT NULL DEFAULT 'local',
  
  -- Constraints
  CONSTRAINT payments_payment_method_check CHECK (payment_method IN ('نقدي', 'بطاقة', 'تحويل', 'آخر')),
  CONSTRAINT payments_revenue_type_check CHECK (revenue_type IN ('room', 'service', 'other')),
  CONSTRAINT payments_origin_check CHECK (origin IN ('local', 'server'))
);

-- Indexes for Payments
CREATE INDEX idx_payments_booking_local_id ON payments(booking_local_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_payments_server_booking_id ON payments(server_booking_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_payments_server_payment_id ON payments(server_payment_id) WHERE server_payment_id IS NOT NULL;
CREATE INDEX idx_payments_payment_date ON payments(payment_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_payments_payment_method ON payments(payment_method) WHERE deleted_at IS NULL;
CREATE INDEX idx_payments_local_uuid ON payments(local_uuid);
CREATE INDEX idx_payments_server_id ON payments(server_id) WHERE server_id IS NOT NULL;
CREATE INDEX idx_payments_last_modified ON payments(last_modified);
CREATE INDEX idx_payments_deleted_at ON payments(deleted_at) WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- DEBTS TABLE - جدول الديون
-- ============================================================================
CREATE TABLE IF NOT EXISTS debts (
  -- Primary Key
  id BIGSERIAL PRIMARY KEY,
  
  -- Business Fields - الحقول الأساسية
  booking_local_id BIGINT REFERENCES bookings(id) ON DELETE CASCADE,
  guest_name TEXT NOT NULL,
  checkin_date TEXT NOT NULL,
  checkout_date TEXT NOT NULL,
  date_recorded TEXT NOT NULL DEFAULT '',
  debt_reason TEXT NOT NULL DEFAULT '',
  total_amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
  paid_amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
  remaining_amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
  payment_date TEXT NOT NULL,
  is_settled INTEGER NOT NULL DEFAULT 0,
  pledge TEXT,
  pledge_type TEXT,
  note TEXT,
  
  -- Sync Fields - حقول المزامنة
  local_uuid UUID NOT NULL UNIQUE DEFAULT uuid_generate_v4(),
  server_id BIGINT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  last_modified TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  version INTEGER NOT NULL DEFAULT 1,
  origin TEXT NOT NULL DEFAULT 'local',
  
  -- Constraints
  CONSTRAINT debts_origin_check CHECK (origin IN ('local', 'server'))
);

-- Indexes for Debts
CREATE INDEX idx_debts_booking_local_id ON debts(booking_local_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_debts_is_settled ON debts(is_settled) WHERE deleted_at IS NULL;
CREATE INDEX idx_debts_local_uuid ON debts(local_uuid);
CREATE INDEX idx_debts_server_id ON debts(server_id) WHERE server_id IS NOT NULL;
CREATE INDEX idx_debts_last_modified ON debts(last_modified);
CREATE INDEX idx_debts_deleted_at ON debts(deleted_at) WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- OUTBOX TABLE - جدول صندوق الإرسال (للمزامنة)
-- ============================================================================
CREATE TABLE IF NOT EXISTS outbox (
  -- Primary Key
  id BIGSERIAL PRIMARY KEY,
  
  -- Outbox Fields - حقول صندوق الإرسال
  entity TEXT NOT NULL,
  op TEXT NOT NULL,
  local_uuid UUID NOT NULL,
  server_id BIGINT,
  payload JSONB NOT NULL,
  client_ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  
  -- Constraints
  CONSTRAINT outbox_op_check CHECK (op IN ('create', 'update', 'delete'))
);

-- Indexes for Outbox
CREATE INDEX idx_outbox_entity ON outbox(entity);
CREATE INDEX idx_outbox_local_uuid ON outbox(local_uuid);
CREATE INDEX idx_outbox_client_ts ON outbox(client_ts);
CREATE INDEX idx_outbox_attempts ON outbox(attempts);

-- ============================================================================
-- SYNC_STATE TABLE - جدول حالة المزامنة
-- ============================================================================
CREATE TABLE IF NOT EXISTS sync_state (
  -- Primary Key
  id INTEGER PRIMARY KEY DEFAULT 1,
  
  -- Sync State Fields - حقول حالة المزامنة
  last_server_ts TIMESTAMPTZ NOT NULL DEFAULT '1970-01-01 00:00:00+00',
  last_pull_ts TIMESTAMPTZ NOT NULL DEFAULT '1970-01-01 00:00:00+00',
  last_push_ts TIMESTAMPTZ NOT NULL DEFAULT '1970-01-01 00:00:00+00',
  is_syncing INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 1,
  
  -- Constraint to ensure only one row
  CONSTRAINT sync_state_id_check CHECK (id = 1)
);

-- Insert initial sync state
INSERT INTO sync_state (id, last_server_ts, last_pull_ts, last_push_ts, is_syncing, version)
VALUES (1, '1970-01-01 00:00:00+00', '1970-01-01 00:00:00+00', '1970-01-01 00:00:00+00', 0, 1)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- FUNCTION: update_updated_at_column()
-- دالة لتحديث updated_at تلقائياً عند أي تحديث
-- ============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  NEW.last_modified = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TRIGGERS: تحديث updated_at تلقائياً لكل جدول
-- ============================================================================
CREATE TRIGGER update_rooms_updated_at BEFORE UPDATE ON rooms
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_bookings_updated_at BEFORE UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_booking_notes_updated_at BEFORE UPDATE ON booking_notes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_employees_updated_at BEFORE UPDATE ON employees
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_expenses_updated_at BEFORE UPDATE ON expenses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_cash_transactions_updated_at BEFORE UPDATE ON cash_transactions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_payments_updated_at BEFORE UPDATE ON payments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_debts_updated_at BEFORE UPDATE ON debts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- COMMENTS - التعليقات التوثيقية
-- ============================================================================
COMMENT ON TABLE rooms IS 'جدول الغرف - يحتوي على معلومات جميع الغرف في الفندق';
COMMENT ON TABLE bookings IS 'جدول الحجوزات - يحتوي على معلومات الحجوزات والنزلاء';
COMMENT ON TABLE booking_notes IS 'جدول ملاحظات الحجوزات - يحتوي على التنبيهات والملاحظات الخاصة بكل حجز';
COMMENT ON TABLE employees IS 'جدول الموظفين - يحتوي على معلومات الموظفين ورواتبهم';
COMMENT ON TABLE expenses IS 'جدول المصروفات - يحتوي على جميع مصروفات الفندق';
COMMENT ON TABLE cash_transactions IS 'جدول المعاملات النقدية - يحتوي على جميع الحركات المالية';
COMMENT ON TABLE payments IS 'جدول الدفعات - يحتوي على دفعات النزلاء والإيرادات';
COMMENT ON TABLE debts IS 'جدول الديون - يحتوي على ديون النزلاء المتبقية';
COMMENT ON TABLE outbox IS 'جدول صندوق الإرسال - يحتوي على التغييرات المحلية قبل المزامنة مع السيرفر';
COMMENT ON TABLE sync_state IS 'جدول حالة المزامنة - يحتوي على آخر أوقات المزامنة';

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
