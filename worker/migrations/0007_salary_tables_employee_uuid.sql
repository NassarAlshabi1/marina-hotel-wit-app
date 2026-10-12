-- ════════════════════════════════════════════════════════════════
--  0007_salary_tables_employee_uuid.sql
--  (2026-09-19) إغلاق فجوة employee_uuid في جداول الرواتب كاملة
--  + ردم تاريخي محروس — «لا فقدان بيانات نهائياً»
--
--  التشخيص (بالأدلة من D1 الإنتاجي):
--  1. salary_withdrawals: 620 صفًا حيًا، صفر منها يحمل employee_uuid —
--     حمولات الدفع من التطبيق لا ترسل العمود إطلاقاً (toJson يرسل
--     employee_id فقط، وهو id محلي على جهاز المصدر)، وردم 0006 فقد
--     أثره بعد إعادة مزامنة الصفوف لاحقاً.
--  2. expenses: 623/687 من صفوف الرواتب تحمل uuid، و68 صفًا قديماً
--     ما زال مرتبطاً بـ related_id (id الموظف المحلي) فقط.
--  3. salary_cycles / salary_payments: العمود غير موجود إطلاقاً.
--
--  القرار المعماري (توجيه المستخدم): employee_uuid في كل جداول
--  الرواتب كما في expenses — المفتاح المستقر عبر الأجهزة.
--
--  ترتيب دقة الردم (تنازلي) — UPDATE فقط، لا DROP ولا DELETE:
--    أ) employees.server_id = <fk> (دلالة الهجرة: id الموظف على جهاز
--       المصدر — أثبتتها جنائية 0006 على employee_id=5 → عمار الدبادي)
--       بشرط الوحدة، ثم تفضيل الموظف الحي عند تعدد المرشحين
--    ب) employees.id = <fk> (احتياطي) — فقط حين لا يوجد أي مرشح
--       server_id على الإطلاق (e.id رقم تسلسلي عام قابل للمصادفة)
--  الصفوف التي لا تحل (يتيمة/ملتبسة) تبقى NULL محفوظة كما هي —
--  لا تُحذف ولا تُعدل مبالغها وتواريخها أبداً.
-- ════════════════════════════════════════════════════════════════

-- ─── 1) العمودان الناقصان ──────────────────────────────────────
ALTER TABLE salary_cycles ADD COLUMN employee_uuid TEXT;
ALTER TABLE salary_payments ADD COLUMN employee_uuid TEXT;

CREATE INDEX IF NOT EXISTS idx_salary_cycles_employee_uuid
  ON salary_cycles(employee_uuid);
CREATE INDEX IF NOT EXISTS idx_salary_payments_employee_uuid
  ON salary_payments(employee_uuid);

-- ─── 2) ردم salary_withdrawals (620 صفاً معلقة) ─────────────────
-- أ) server_id فريد إجمالاً (حياً كان الموظف أو مُسرّحاً)
UPDATE salary_withdrawals
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.server_id = salary_withdrawals.employee_id
   )
 WHERE employee_uuid IS NULL
   AND employee_id IS NOT NULL
   AND (SELECT COUNT(*) FROM employees e2
         WHERE e2.server_id = salary_withdrawals.employee_id) = 1;

-- ب) server_id متعدد المرشحين لكن حي واحد بالضبط → الحي
--    (إنتاج: server_id=1 مشترك بين صف محذوف ومحمد احمد الحي)
UPDATE salary_withdrawals
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.server_id = salary_withdrawals.employee_id
        AND e.deleted_at IS NULL
   )
 WHERE employee_uuid IS NULL
   AND employee_id IS NOT NULL
   AND (SELECT COUNT(*) FROM employees e2
         WHERE e2.server_id = salary_withdrawals.employee_id) > 1
   AND (SELECT COUNT(*) FROM employees e3
         WHERE e3.server_id = salary_withdrawals.employee_id
           AND e3.deleted_at IS NULL) = 1;

-- ج) لا مرشح server_id إطلاقاً → احتياطي e.id الفريد
UPDATE salary_withdrawals
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.id = salary_withdrawals.employee_id
   )
 WHERE employee_uuid IS NULL
   AND employee_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM employees e2
                    WHERE e2.server_id = salary_withdrawals.employee_id)
   AND (SELECT COUNT(*) FROM employees e3
         WHERE e3.id = salary_withdrawals.employee_id) = 1;

-- ─── 3) ردم expenses (68 صفاً قديماً بـ related_id فقط) ─────────
-- related_id في التطبيق = id الموظف المحلي للسحبات/السلف (لا يُضبط
-- إلا لمصروفات الموظفين — expenses_list.dart: isSalaryExpense فقط)
UPDATE expenses
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.server_id = expenses.related_id
   )
 WHERE employee_uuid IS NULL
   AND related_id IS NOT NULL
   AND (SELECT COUNT(*) FROM employees e2
         WHERE e2.server_id = expenses.related_id) = 1;

UPDATE expenses
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.server_id = expenses.related_id
        AND e.deleted_at IS NULL
   )
 WHERE employee_uuid IS NULL
   AND related_id IS NOT NULL
   AND (SELECT COUNT(*) FROM employees e2
         WHERE e2.server_id = expenses.related_id) > 1
   AND (SELECT COUNT(*) FROM employees e3
         WHERE e3.server_id = expenses.related_id
           AND e3.deleted_at IS NULL) = 1;

UPDATE expenses
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.id = expenses.related_id
   )
 WHERE employee_uuid IS NULL
   AND related_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM employees e2
                    WHERE e2.server_id = expenses.related_id)
   AND (SELECT COUNT(*) FROM employees e3
         WHERE e3.id = expenses.related_id) = 1;

-- ─── 4) ردم salary_cycles (نفس سلسلة الدقة) ────────────────────
UPDATE salary_cycles
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.server_id = salary_cycles.employee_id
   )
 WHERE employee_uuid IS NULL
   AND employee_id IS NOT NULL
   AND (SELECT COUNT(*) FROM employees e2
         WHERE e2.server_id = salary_cycles.employee_id) = 1;

UPDATE salary_cycles
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.server_id = salary_cycles.employee_id
        AND e.deleted_at IS NULL
   )
 WHERE employee_uuid IS NULL
   AND employee_id IS NOT NULL
   AND (SELECT COUNT(*) FROM employees e2
         WHERE e2.server_id = salary_cycles.employee_id) > 1
   AND (SELECT COUNT(*) FROM employees e3
         WHERE e3.server_id = salary_cycles.employee_id
           AND e3.deleted_at IS NULL) = 1;

UPDATE salary_cycles
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.id = salary_cycles.employee_id
   )
 WHERE employee_uuid IS NULL
   AND employee_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM employees e2
                    WHERE e2.server_id = salary_cycles.employee_id)
   AND (SELECT COUNT(*) FROM employees e3
         WHERE e3.id = salary_cycles.employee_id) = 1;

-- ─── 5) ردم salary_payments عبر دورتها ─────────────────────────
-- أ) المفتاح الأساسي (دائماً فريد)
UPDATE salary_payments
   SET employee_uuid = (
     SELECT sc.employee_uuid FROM salary_cycles sc
      WHERE sc.id = salary_payments.cycle_id
   )
 WHERE employee_uuid IS NULL
   AND cycle_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM salary_cycles sc
                WHERE sc.id = salary_payments.cycle_id
                  AND sc.employee_uuid IS NOT NULL);

-- ب) دلالة الهجرة (server_id للدورة = id جهاز المصدر)
UPDATE salary_payments
   SET employee_uuid = (
     SELECT sc.employee_uuid FROM salary_cycles sc
      WHERE sc.server_id = salary_payments.cycle_id
   )
 WHERE employee_uuid IS NULL
   AND cycle_id IS NOT NULL
   AND (SELECT COUNT(*) FROM salary_cycles sc
         WHERE sc.server_id = salary_payments.cycle_id
           AND sc.employee_uuid IS NOT NULL) = 1;
