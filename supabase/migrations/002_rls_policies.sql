-- ============================================================================
-- Marina Hotel - Supabase RLS (Row Level Security) Policies
-- سياسات الأمان على مستوى الصفوف
-- RLS Policies for all tables
-- ============================================================================

-- ============================================================================
-- ENABLE RLS - تفعيل RLS لجميع الجداول
-- ============================================================================
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE debts ENABLE ROW LEVEL SECURITY;
ALTER TABLE outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_state ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- ROOMS POLICIES - سياسات جدول الغرف
-- ============================================================================

-- SELECT: يمكن لأي مستخدم مُسجل قراءة الغرف غير المحذوفة
CREATE POLICY "rooms_select_policy" ON rooms
  FOR SELECT
  USING (auth.uid() IS NOT NULL AND deleted_at IS NULL);

-- INSERT: يمكن لأي مستخدم مُسجل إضافة غرف
CREATE POLICY "rooms_insert_policy" ON rooms
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE: يمكن لأي مستخدم مُسجل تحديث الغرف
CREATE POLICY "rooms_update_policy" ON rooms
  FOR UPDATE
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- DELETE: يمكن لأي مستخدم مُسجل حذف الغرف (soft delete)
CREATE POLICY "rooms_delete_policy" ON rooms
  FOR DELETE
  USING (auth.uid() IS NOT NULL);

-- ============================================================================
-- BOOKINGS POLICIES - سياسات جدول الحجوزات
-- ============================================================================

-- SELECT: يمكن لأي مستخدم مُسجل قراءة الحجوزات غير المحذوفة
CREATE POLICY "bookings_select_policy" ON bookings
  FOR SELECT
  USING (auth.uid() IS NOT NULL AND deleted_at IS NULL);

-- INSERT: يمكن لأي مستخدم مُسجل إضافة حجوزات
CREATE POLICY "bookings_insert_policy" ON bookings
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE: يمكن لأي مستخدم مُسجل تحديث الحجوزات
CREATE POLICY "bookings_update_policy" ON bookings
  FOR UPDATE
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- DELETE: يمكن لأي مستخدم مُسجل حذف الحجوزات (soft delete)
CREATE POLICY "bookings_delete_policy" ON bookings
  FOR DELETE
  USING (auth.uid() IS NOT NULL);

-- ============================================================================
-- BOOKING_NOTES POLICIES - سياسات جدول ملاحظات الحجوزات
-- ============================================================================

-- SELECT: يمكن لأي مستخدم مُسجل قراءة الملاحظات غير المحذوفة
CREATE POLICY "booking_notes_select_policy" ON booking_notes
  FOR SELECT
  USING (auth.uid() IS NOT NULL AND deleted_at IS NULL);

-- INSERT: يمكن لأي مستخدم مُسجل إضافة ملاحظات
CREATE POLICY "booking_notes_insert_policy" ON booking_notes
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE: يمكن لأي مستخدم مُسجل تحديث الملاحظات
CREATE POLICY "booking_notes_update_policy" ON booking_notes
  FOR UPDATE
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- DELETE: يمكن لأي مستخدم مُسجل حذف الملاحظات (soft delete)
CREATE POLICY "booking_notes_delete_policy" ON booking_notes
  FOR DELETE
  USING (auth.uid() IS NOT NULL);

-- ============================================================================
-- EMPLOYEES POLICIES - سياسات جدول الموظفين
-- ============================================================================

-- SELECT: يمكن لأي مستخدم مُسجل قراءة الموظفين غير المحذوفين
CREATE POLICY "employees_select_policy" ON employees
  FOR SELECT
  USING (auth.uid() IS NOT NULL AND deleted_at IS NULL);

-- INSERT: يمكن لأي مستخدم مُسجل إضافة موظفين
CREATE POLICY "employees_insert_policy" ON employees
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE: يمكن لأي مستخدم مُسجل تحديث الموظفين
CREATE POLICY "employees_update_policy" ON employees
  FOR UPDATE
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- DELETE: يمكن لأي مستخدم مُسجل حذف الموظفين (soft delete)
CREATE POLICY "employees_delete_policy" ON employees
  FOR DELETE
  USING (auth.uid() IS NOT NULL);

-- ============================================================================
-- EXPENSES POLICIES - سياسات جدول المصروفات
-- ============================================================================

-- SELECT: يمكن لأي مستخدم مُسجل قراءة المصروفات غير المحذوفة
CREATE POLICY "expenses_select_policy" ON expenses
  FOR SELECT
  USING (auth.uid() IS NOT NULL AND deleted_at IS NULL);

-- INSERT: يمكن لأي مستخدم مُسجل إضافة مصروفات
CREATE POLICY "expenses_insert_policy" ON expenses
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE: يمكن لأي مستخدم مُسجل تحديث المصروفات
CREATE POLICY "expenses_update_policy" ON expenses
  FOR UPDATE
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- DELETE: يمكن لأي مستخدم مُسجل حذف المصروفات (soft delete)
CREATE POLICY "expenses_delete_policy" ON expenses
  FOR DELETE
  USING (auth.uid() IS NOT NULL);

-- ============================================================================
-- CASH_TRANSACTIONS POLICIES - سياسات جدول المعاملات النقدية
-- ============================================================================

-- SELECT: يمكن لأي مستخدم مُسجل قراءة المعاملات غير المحذوفة
CREATE POLICY "cash_transactions_select_policy" ON cash_transactions
  FOR SELECT
  USING (auth.uid() IS NOT NULL AND deleted_at IS NULL);

-- INSERT: يمكن لأي مستخدم مُسجل إضافة معاملات
CREATE POLICY "cash_transactions_insert_policy" ON cash_transactions
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE: يمكن لأي مستخدم مُسجل تحديث المعاملات
CREATE POLICY "cash_transactions_update_policy" ON cash_transactions
  FOR UPDATE
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- DELETE: يمكن لأي مستخدم مُسجل حذف المعاملات (soft delete)
CREATE POLICY "cash_transactions_delete_policy" ON cash_transactions
  FOR DELETE
  USING (auth.uid() IS NOT NULL);

-- ============================================================================
-- PAYMENTS POLICIES - سياسات جدول الدفعات
-- ============================================================================

-- SELECT: يمكن لأي مستخدم مُسجل قراءة الدفعات غير المحذوفة
CREATE POLICY "payments_select_policy" ON payments
  FOR SELECT
  USING (auth.uid() IS NOT NULL AND deleted_at IS NULL);

-- INSERT: يمكن لأي مستخدم مُسجل إضافة دفعات
CREATE POLICY "payments_insert_policy" ON payments
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE: يمكن لأي مستخدم مُسجل تحديث الدفعات
CREATE POLICY "payments_update_policy" ON payments
  FOR UPDATE
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- DELETE: يمكن لأي مستخدم مُسجل حذف الدفعات (soft delete)
CREATE POLICY "payments_delete_policy" ON payments
  FOR DELETE
  USING (auth.uid() IS NOT NULL);

-- ============================================================================
-- DEBTS POLICIES - سياسات جدول الديون
-- ============================================================================

-- SELECT: يمكن لأي مستخدم مُسجل قراءة الديون غير المحذوفة
CREATE POLICY "debts_select_policy" ON debts
  FOR SELECT
  USING (auth.uid() IS NOT NULL AND deleted_at IS NULL);

-- INSERT: يمكن لأي مستخدم مُسجل إضافة ديون
CREATE POLICY "debts_insert_policy" ON debts
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE: يمكن لأي مستخدم مُسجل تحديث الديون
CREATE POLICY "debts_update_policy" ON debts
  FOR UPDATE
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- DELETE: يمكن لأي مستخدم مُسجل حذف الديون (soft delete)
CREATE POLICY "debts_delete_policy" ON debts
  FOR DELETE
  USING (auth.uid() IS NOT NULL);

-- ============================================================================
-- OUTBOX POLICIES - سياسات جدول صندوق الإرسال
-- ============================================================================

-- SELECT: يمكن لأي مستخدم مُسجل قراءة صندوق الإرسال
CREATE POLICY "outbox_select_policy" ON outbox
  FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- INSERT: يمكن لأي مستخدم مُسجل إضافة إلى صندوق الإرسال
CREATE POLICY "outbox_insert_policy" ON outbox
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE: يمكن لأي مستخدم مُسجل تحديث صندوق الإرسال
CREATE POLICY "outbox_update_policy" ON outbox
  FOR UPDATE
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- DELETE: يمكن لأي مستخدم مُسجل حذف من صندوق الإرسال
CREATE POLICY "outbox_delete_policy" ON outbox
  FOR DELETE
  USING (auth.uid() IS NOT NULL);

-- ============================================================================
-- SYNC_STATE POLICIES - سياسات جدول حالة المزامنة
-- ============================================================================

-- SELECT: يمكن لأي مستخدم مُسجل قراءة حالة المزامنة
CREATE POLICY "sync_state_select_policy" ON sync_state
  FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- UPDATE: يمكن لأي مستخدم مُسجل تحديث حالة المزامنة
CREATE POLICY "sync_state_update_policy" ON sync_state
  FOR UPDATE
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- ============================================================================
-- NOTES - ملاحظات مهمة
-- ============================================================================

-- ملاحظة 1: جميع السياسات الحالية تسمح لأي مستخدم مُسجل بالوصول
-- يمكنك تخصيص السياسات بناءً على احتياجاتك:
-- - إضافة صلاحيات حسب الدور (admin, employee, etc.)
-- - تقييد الوصول بناءً على بيانات إضافية
-- - إضافة فلترة حسب المستخدم الذي أنشأ السجل

-- ملاحظة 2: RLS يحمي البيانات على مستوى قاعدة البيانات
-- حتى لو حصل شخص على ANON_KEY، لا يمكنه الوصول بدون auth

-- ملاحظة 3: للبيئة الحالية، نفترض أن جميع المستخدمين المسجلين موثوقين
-- إذا كنت تريد صلاحيات أكثر تفصيلاً، يمكنك:
-- 1. إنشاء جدول users مع أدوار (roles)
-- 2. تحديث السياسات لاستخدام الأدوار
-- 3. إضافة دالة للتحقق من الصلاحيات

-- مثال على دالة التحقق من الصلاحيات (اختياري):
-- CREATE OR REPLACE FUNCTION user_has_role(required_role TEXT)
-- RETURNS BOOLEAN AS $$
-- BEGIN
--   RETURN EXISTS (
--     SELECT 1 FROM users
--     WHERE id = auth.uid()
--     AND role = required_role
--   );
-- END;
-- $$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- END OF RLS POLICIES
-- ============================================================================
