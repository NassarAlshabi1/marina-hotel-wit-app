-- ════════════════════════════════════════════════════════════════
--  0006_salary_withdrawals_employee_uuid.sql
--  (2026-09-10) إصلاح جذري لـ«107 سجل محجوب: أب غير محلول»
--
--  التشخيص (بالأدلة، لا التخمين):
--  1. حمولات salary_withdrawals لا تحمل أبداً employeeUuid — فقط
--     employee_id الرقمي وهو id المحلي على جهاز المصدر.
--  2. worker createRecord يجبر server_id=null (وهو عمود هجرة فقط)
--     → لا يمكن حل الأب رقمياً على أي جهاز غير مصدر الصف، ولا حتى
--     على جهاز المصدر نفسه (echo-filter يمنع عودة صف الأب إليه).
--  3. الأدلة من D1: 95 سحوبة تشير إلى employees.server_id=5 (عمار
--     الدبادي، device_id=da2c98b9...) و30 سحوبة يتيمة بنيوياً (لا أب
--     له على الإطلاق) = 125 ≈ 107 المحجوبة بعد الحجر التدريجي.
--
--  العلاج: عمود employee_uuid (مرجع مستقر عبر الأجهزة) + ردّم
--  تاريخي بضم employees عبر server_id. العميل يقرأ employee_uuid
--  أصلاً في resolveRefs (كان جاهزاً للـ uuid قبل الوقت) — فتُطبَّق
--  الصفوف المحجوبة تلقائياً في أول سحب بعد هذا الترقية.
--  السحوبات اليتيمة (30) تبقى بلا uuid → serverId → فشل حتمي →
--  الحجر التدريجي (عتبة 3 دورات) يعزلها ويتقدم المؤشر تلقائياً.
-- ════════════════════════════════════════════════════════════════

ALTER TABLE salary_withdrawals ADD COLUMN employee_uuid TEXT;

CREATE INDEX IF NOT EXISTS idx_salary_withdrawals_employee_uuid
  ON salary_withdrawals(employee_uuid);

-- ردّم تاريخي: uuid الأب من جدول employees عبر server_id
-- (server_id على D1 = id المحلي للأب على جهاز المصدر في بيانات الهجرة).
UPDATE salary_withdrawals
   SET employee_uuid = (
     SELECT e.local_uuid FROM employees e
      WHERE e.server_id = salary_withdrawals.employee_id
      LIMIT 1
   )
 WHERE employee_uuid IS NULL;
