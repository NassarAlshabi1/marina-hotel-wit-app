-- ════════════════════════════════════════════════════════════════
--  0011_carryover_employee_uuid_payments_cycle_uuid.sql
--  (2026-10-05) إغلاق فجوتَي الهوية عبر الأجهزة في جداول الرواتب
--  — «لا فقدان بيانات نهائياً» (نفس توجيه 0006/0007)
--
--  التشخيص (من تحليل fk_rules.dart + worker/src/database.ts):
--  1. salary_carry_over_logs: المنتج (salary_entitlement_service)
--     يرسل employee_id فقط — رقم محلي على جهاز المصدر، وبلا عمود
--     uuid ولا ذاكرة حل في fk_rules → سجلات الترحيل تتيّم بنيوياً
--     على كل جهاز آخر (تُؤجَّل ثم تُحجر).
--  2. salary_payments.cycle_id: نفس المشكلة مع الدورة — وصفوف
--     Worker تُنشأ بـ server_id=NULL (database.ts يفرض null) فلا
--     يوجد ظلّ هوية يُطابق cycle_id أصلاً → الدفعة لا تربط بدورتها
--     على أي جهاز آخر.
--
--  القرار المعماري (نفس عقد expenses/withdrawals):
--    employee_uuid لسجلات الترحيل، و cycle_uuid لذكرة الدورة —
--    المفتاحان المستقران عبر الأجهزة، ويفعّلان uuidCacheColumn في
--    fk_rules.dart (المفتاح الأول للحل قبل server_id).
--
--  ترتيب دقة الردم (تنازلي) — UPDATE فقط، لا DROP ولا DELETE:
--    الصفوف التي لا تحل (يتيمة/ملتبسة) تبقى NULL محفوظة كما هي —
--    لا تُحذف ولا تُعدل مبالغها وتواريخها أبداً. الصفوف الجديدة
--    تحمل المفتاحين من المصدر بعد ترقية التطبيق (migration 69).
-- ════════════════════════════════════════════════════════════════

-- ─── 1) الأعمدة الناقصة ────────────────────────────────────────
ALTER TABLE salary_carry_over_logs ADD COLUMN employee_uuid TEXT;
ALTER TABLE salary_payments ADD COLUMN cycle_uuid TEXT;

CREATE INDEX IF NOT EXISTS idx_salary_carryover_employee_uuid
  ON salary_carry_over_logs(employee_uuid);
CREATE INDEX IF NOT EXISTS idx_salary_payments_cycle_uuid
  ON salary_payments(cycle_uuid);

-- ─── 2) ردم salary_carry_over_logs.employee_uuid ───────────────
-- أ) server_id فريد إجمالاً (حياً كان الموظف أو مُسرّحاً)
--    (دلالة الهجرة: employee_id على صفوف الهجرة = id جهاز المصدر)
UPDATE salary_carry_over_logs
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.server_id = salary_carry_over_logs.employee_id
   )
 WHERE employee_uuid IS NULL
   AND employee_id IS NOT NULL
   AND (SELECT COUNT(*) FROM employees e2
         WHERE e2.server_id = salary_carry_over_logs.employee_id) = 1;

-- ب) server_id متعدد المرشحين لكن حي واحد بالضبط → الحي
UPDATE salary_carry_over_logs
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.server_id = salary_carry_over_logs.employee_id
        AND e.deleted_at IS NULL
   )
 WHERE employee_uuid IS NULL
   AND employee_id IS NOT NULL
   AND (SELECT COUNT(*) FROM employees e2
         WHERE e2.server_id = salary_carry_over_logs.employee_id) > 1
   AND (SELECT COUNT(*) FROM employees e3
         WHERE e3.server_id = salary_carry_over_logs.employee_id
           AND e3.deleted_at IS NULL) = 1;

-- ج) لا مرشح server_id إطلاقاً → احتياطي e.id الفريد
--    (صفوف جهاز الترحيل الأصلي: employee_id = employees.id على D1)
UPDATE salary_carry_over_logs
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.id = salary_carry_over_logs.employee_id
   )
 WHERE employee_uuid IS NULL
   AND employee_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM employees e2
                    WHERE e2.server_id = salary_carry_over_logs.employee_id)
   AND (SELECT COUNT(*) FROM employees e3
         WHERE e3.id = salary_carry_over_logs.employee_id) = 1;

-- ─── 3) ردم salary_payments.cycle_uuid ─────────────────────────
-- أ) المفتاح الأساسي (دائماً فريد): cycle_id في فضاء D1 — صفوف
--    جهاز الترحيل الأصلي والصفوف المكتوبة بعده بنفس الفضاء.
UPDATE salary_payments
   SET cycle_uuid = (
     SELECT sc.local_uuid FROM salary_cycles sc
      WHERE sc.id = salary_payments.cycle_id
   )
 WHERE cycle_uuid IS NULL
   AND cycle_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM salary_cycles sc
                WHERE sc.id = salary_payments.cycle_id
                  AND sc.local_uuid IS NOT NULL);

-- ب) دلالة الهجرة (server_id للدورة = id جهاز المصدر) — الوحدة شرط
UPDATE salary_payments
   SET cycle_uuid = (
     SELECT sc.local_uuid FROM salary_cycles sc
      WHERE sc.server_id = salary_payments.cycle_id
   )
 WHERE cycle_uuid IS NULL
   AND cycle_id IS NOT NULL
   AND (SELECT COUNT(*) FROM salary_cycles sc
         WHERE sc.server_id = salary_payments.cycle_id
           AND sc.local_uuid IS NOT NULL) = 1;
