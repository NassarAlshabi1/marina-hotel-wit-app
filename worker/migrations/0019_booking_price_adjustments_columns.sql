-- ════════════════════════════════════════════════════════════════════
--  0019_booking_price_adjustments_columns.sql
--
--  الغرض: إضافة عمودَي التوافق `hotel_day_key` و`applied_date` إلى جدول
--  booking_price_adjustments على D1.
--
--  لماذا (تقرير 2026-11-23 / §10):
--    عميل Flutter يُصدر في `toJson` ثلاثة أسماء لنفس القيمة:
--      • effectiveHotelDay → effective_hotel_day  (الاسم القانوني على D1)
--      • hotelDayKey       → hotel_day_key        (عقد Appwrite القديم)
--      • appliedDate       → applied_date         (عقد Appwrite القديم)
--    والـworker لا يحوّل أسماء الأعمدة: `prepareInsertRow` يفلتر الحمولة
--    على أعمدة الجدول، فكان الاسمين القديمين **يُسقَطان صمتاً**. النتيجة:
--    أي عميل يرسل أحدهما وحده (نسخ أقدم، أو عميل Android) تصل تسويته بلا
--    يوم سريان، فتُستبعد من `_fetchActiveAdjustments` وتُحسب الليلة بسعر
--    أعلى من الصحيح.
--
--  القيمة بعد الترحيل:
--    الأعمدة الثلاثة تعني نفس الشيء، ويكتبها `normalizeBookingPriceAdjustment`
--    في `worker/src/database.ts` متزامنةً عند كل push (لا تضارب لاحق).
--
--  التشغيل: npm run db:migrate:bpa-columns
--                                  / :remote
--  ملاحظة: SQLite لا يدعم ADD COLUMN IF NOT EXISTS — نفّذ الملف مرة واحدة.
-- ════════════════════════════════════════════════════════════════════

ALTER TABLE booking_price_adjustments ADD COLUMN hotel_day_key TEXT;
ALTER TABLE booking_price_adjustments ADD COLUMN applied_date TEXT;

-- تعبئة الصفوف القائمة من الاسم القانوني (idempotent عملياً: لا يمسّ صفاً
-- له قيمة بالفعل، فإعادة التعبئة لا تغيّر شيئاً).
UPDATE booking_price_adjustments
SET hotel_day_key = effective_hotel_day
WHERE (hotel_day_key IS NULL OR TRIM(hotel_day_key) = '')
  AND effective_hotel_day IS NOT NULL
  AND TRIM(effective_hotel_day) <> '';

UPDATE booking_price_adjustments
SET applied_date = effective_hotel_day
WHERE (applied_date IS NULL OR TRIM(applied_date) = '')
  AND effective_hotel_day IS NOT NULL
  AND TRIM(effective_hotel_day) <> '';

-- فهرس هوية الحجز + اليوم: مسار إعادة الحساب والتسوية.
CREATE INDEX IF NOT EXISTS idx_bpa_booking_uuid
  ON booking_price_adjustments(booking_uuid, effective_hotel_day);

-- تحقّق بعد التنفيذ:
-- SELECT COUNT(*) FROM booking_price_adjustments WHERE hotel_day_key IS NULL OR applied_date IS NULL;
