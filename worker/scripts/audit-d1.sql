-- ════════════════════════════════════════════════════════════════════
--  audit-d1.sql — فحص قراءة فقط لصحة قاعدة D1 (marina-hotel-db)
--
--  التشغيل:
--    npm run audit:d1:remote          # على D1 الحقيقي
--    npm run audit:d1                 # على D1 محلي مبني من schema.sql
--
--  كل استعلام يُرجع صفاً واحداً بعمود `finding` و`value`:
--  القيمة 0 = سليم. أي رقم > 0 يحتاج تحقيقاً.
--  لا يوجد أي INSERT/UPDATE/DELETE هنا — الملف للقراءة فقط.
-- ════════════════════════════════════════════════════════════════════

-- 1) ليالٍ حيّة مكررة على نفس (uuid الحجز، اليوم) — الخطر الأول
SELECT 'duplicate_live_nights' AS finding, COUNT(*) AS value FROM (
  SELECT lower(replace(trim(booking_uuid_cache), '-', '')) AS u,
         trim(hotel_day_key) AS d
    FROM booking_nights
   WHERE deleted_at IS NULL
     AND booking_uuid_cache IS NOT NULL
     AND trim(booking_uuid_cache) <> ''
   GROUP BY u, d
  HAVING COUNT(*) > 1
);

-- 2) ليالٍ حيّة بلا هوية حجز عالمية (تتجاوز الفهرس الفريد أعلاه)
SELECT 'live_nights_without_booking_uuid' AS finding, COUNT(*) AS value
  FROM booking_nights
 WHERE deleted_at IS NULL
   AND (booking_uuid_cache IS NULL OR trim(booking_uuid_cache) = '');

-- 3) ليالٍ يتيمة: uuid حجز لا وجود له في bookings
SELECT 'orphan_nights_missing_booking' AS finding, COUNT(*) AS value
  FROM booking_nights n
 WHERE n.deleted_at IS NULL
   AND n.booking_uuid_cache IS NOT NULL
   AND trim(n.booking_uuid_cache) <> ''
   AND NOT EXISTS (
     SELECT 1 FROM bookings b
      WHERE b.deleted_at IS NULL
        AND lower(replace(b.local_uuid, '-', '')) =
            lower(replace(n.booking_uuid_cache, '-', ''))
   );

-- 4) ليالٍ مربوطة بحجز غير الحجز المذكور في uuidها (تصادم أرقام أجهزة)
SELECT 'nights_linked_to_wrong_booking' AS finding, COUNT(*) AS value
  FROM booking_nights n
  JOIN bookings b
    ON lower(replace(b.local_uuid, '-', '')) =
       lower(replace(n.booking_uuid_cache, '-', ''))
 WHERE n.deleted_at IS NULL
   AND b.deleted_at IS NULL
   AND n.booking_local_id IS NOT NULL
   AND n.booking_local_id > 0
   AND n.booking_local_id <> b.id;

-- 5) ليالٍ بمعرّف حجز صفري (رابط جهاز غير مترجم)
SELECT 'nights_with_zero_booking_link' AS finding, COUNT(*) AS value
  FROM booking_nights
 WHERE deleted_at IS NULL
   AND (booking_local_id IS NULL OR booking_local_id = 0);

-- 6) صفوف بلا هوية عالمية أو بهوية فارغة — تفشل في الرفع
--    (مجموع استعلامات مستقلة: SQLite يحدّ عدد أطراف UNION في D1)
SELECT 'rows_without_local_uuid' AS finding,
       (SELECT COUNT(*) FROM bookings
         WHERE local_uuid IS NULL OR trim(local_uuid) = '')
     + (SELECT COUNT(*) FROM booking_nights
         WHERE local_uuid IS NULL OR trim(local_uuid) = '')
     + (SELECT COUNT(*) FROM payments
         WHERE local_uuid IS NULL OR trim(local_uuid) = '')
     + (SELECT COUNT(*) FROM debts
         WHERE local_uuid IS NULL OR trim(local_uuid) = '')
     + (SELECT COUNT(*) FROM employees
         WHERE local_uuid IS NULL OR trim(local_uuid) = '')
     + (SELECT COUNT(*) FROM expenses
         WHERE local_uuid IS NULL OR trim(local_uuid) = '')
     + (SELECT COUNT(*) FROM booking_price_adjustments
         WHERE local_uuid IS NULL OR trim(local_uuid) = '') AS value;

-- 7) هويات مكررة داخل نفس الجدول (يكسر upsert بالهوية)
SELECT 'duplicate_bookings_by_uuid' AS finding, COUNT(*) AS value FROM (
  SELECT lower(replace(trim(local_uuid), '-', '')) u FROM bookings
   GROUP BY u HAVING COUNT(*) > 1
);

-- 8) مدفوعات بلا هوية حجز بينما الحجز مطلوب للتسوية
SELECT 'payments_without_booking_uuid' AS finding, COUNT(*) AS value
  FROM payments
 WHERE deleted_at IS NULL
   AND (booking_uuid_cache IS NULL OR trim(booking_uuid_cache) = '');

-- 9) مدفوعات مربوطة بحجز خاطئ (نفس فحص الليالي)
SELECT 'payments_linked_to_wrong_booking' AS finding, COUNT(*) AS value
  FROM payments p
  JOIN bookings b
    ON lower(replace(b.local_uuid, '-', '')) =
       lower(replace(p.booking_uuid_cache, '-', ''))
 WHERE p.deleted_at IS NULL
   AND b.deleted_at IS NULL
   AND p.booking_local_id IS NOT NULL
   AND p.booking_local_id > 0
   AND p.booking_local_id <> b.id;

-- 10) ديون بلا هوية حجز
SELECT 'debts_without_booking_uuid' AS finding, COUNT(*) AS value
  FROM debts
 WHERE deleted_at IS NULL
   AND (booking_uuid_cache IS NULL OR trim(booking_uuid_cache) = '');

-- 11) سحوبات رواتب بلا uuid موظف (سبب حجز «أب غير محلول» سابقاً)
SELECT 'withdrawals_without_employee_uuid' AS finding, COUNT(*) AS value
  FROM salary_withdrawals
 WHERE deleted_at IS NULL
   AND (employee_uuid IS NULL OR trim(employee_uuid) = '');

-- 12) مصروفات مرتبطة بموظف غير موجود
SELECT 'expenses_orphan_employee' AS finding, COUNT(*) AS value
  FROM expenses e
 WHERE e.deleted_at IS NULL
   AND e.employee_uuid IS NOT NULL
   AND trim(e.employee_uuid) <> ''
   AND NOT EXISTS (
     SELECT 1 FROM employees em
      WHERE em.deleted_at IS NULL
        AND lower(replace(em.local_uuid, '-', '')) =
            lower(replace(e.employee_uuid, '-', ''))
   );

-- 13) إصدارات غير صالحة (0 أو NULL) — تفشل حماية LWW على الخادم
SELECT 'rows_with_invalid_version' AS finding,
       (SELECT COUNT(*) FROM bookings
         WHERE version IS NULL OR version < 1)
     + (SELECT COUNT(*) FROM booking_nights
         WHERE version IS NULL OR version < 1)
     + (SELECT COUNT(*) FROM payments
         WHERE version IS NULL OR version < 1)
     + (SELECT COUNT(*) FROM debts
         WHERE version IS NULL OR version < 1)
     + (SELECT COUNT(*) FROM employees
         WHERE version IS NULL OR version < 1)
     + (SELECT COUNT(*) FROM expenses
         WHERE version IS NULL OR version < 1)
     + (SELECT COUNT(*) FROM booking_price_adjustments
         WHERE version IS NULL OR version < 1) AS value;

-- 14) إخفاءات مشوّهة: deleted_at بلا updated_at أحدث (تسريب ظلّي)
SELECT 'tombstones_older_than_updated_at' AS finding, COUNT(*) AS value
  FROM booking_nights
 WHERE deleted_at IS NOT NULL
   AND deleted_at > updated_at;

-- 15) تسويات سعر بلا يوم سريان (بعد 0019 يجب أن تكون صفراً)
SELECT 'price_adjustments_without_day' AS finding, COUNT(*) AS value
  FROM booking_price_adjustments
 WHERE deleted_at IS NULL
   AND (effective_hotel_day IS NULL OR trim(effective_hotel_day) = '');

-- 16) تسويات سعر لم تُزامَن أسماؤها القديمة (يكشف 0019 غير المنفَّذ)
SELECT 'price_adjustments_day_aliases_null' AS finding, COUNT(*) AS value
  FROM booking_price_adjustments
 WHERE deleted_at IS NULL
   AND (hotel_day_key IS NULL OR applied_date IS NULL);

-- 17) سجلات idempotency (تتراكم — التنظيف اليومي يتوقع < 5000)
SELECT 'idempotency_log_rows' AS finding, COUNT(*) AS value
  FROM idempotency_log;

-- 18) مؤشرات النمو
SELECT 'audit_logs_rows' AS finding, COUNT(*) AS value FROM audit_logs;
SELECT 'sync_log_rows' AS finding, COUNT(*) AS value FROM sync_log;
SELECT 'sync_conflicts_rows' AS finding, COUNT(*) AS value FROM sync_conflicts;

-- 19) أحجام الجداول الأساسية (للمقارنة مع أرقام التقرير: 356 حجزاً)
SELECT 'bookings_rows' AS finding, COUNT(*) AS value FROM bookings WHERE deleted_at IS NULL;
SELECT 'booking_nights_rows' AS finding, COUNT(*) AS value FROM booking_nights WHERE deleted_at IS NULL;
SELECT 'booking_nights_tombstones' AS finding, COUNT(*) AS value FROM booking_nights WHERE deleted_at IS NOT NULL;
SELECT 'payments_rows' AS finding, COUNT(*) AS value FROM payments WHERE deleted_at IS NULL;
SELECT 'debts_rows' AS finding, COUNT(*) AS value FROM debts WHERE deleted_at IS NULL;
SELECT 'employees_rows' AS finding, COUNT(*) AS value FROM employees WHERE deleted_at IS NULL;
SELECT 'expenses_rows' AS finding, COUNT(*) AS value FROM expenses WHERE deleted_at IS NULL;
SELECT 'booking_price_adjustments_rows' AS finding, COUNT(*) AS value
  FROM booking_price_adjustments WHERE deleted_at IS NULL;

-- 20) ليالٍ لكل حجز (أكثر من 60 ليلة لحجز واحد = اشتباه تضخّم)
SELECT 'bookings_with_more_than_60_nights' AS finding, COUNT(*) AS value FROM (
  SELECT booking_local_id
    FROM booking_nights
   WHERE deleted_at IS NULL
     AND booking_local_id > 0
   GROUP BY booking_local_id
  HAVING COUNT(*) > 60
);
