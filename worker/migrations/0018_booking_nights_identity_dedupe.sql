-- ════════════════════════════════════════════════════════════════════
--  0018_booking_nights_identity_dedupe.sql
--  الغرض: «لا ليالٍ مكررة» على Cloudflare D1.
--
--  الخلل (تقرير 2026-11-23):
--    • booking_nights يحمل UNIQUE (booking_local_id, hotel_day_key)
--      و booking_local_id رقم AUTOINCREMENT *محلي للجهاز المرسل*.
--      فليلة الجهاز A (حجز 7) تصطدم بليلة الجهاز B (حجز 7 آخر) لنفس
--      اليوم: القيد يرفض الإدراج أو يُكتب فوق صف مشروع → ليالٍ مفقودة
--      و1,975 صفاً عبر 115 معرّفاً متصادماً.
--    • القيد غير مشروط بـ deleted_at، فلا يمكن إخفاء نسخة وإدراج بديل
--      لنفس اليوم (كل محاولات «الإحلال» تفشل بـ SQLITE_CONSTRAINT).
--    • صفوف يتيمة أُنشئت من حمولات رقيقة بسبب إعادة تنفيذ update الغائب
--      كـ create بقيم 0/'' — 200 صفاً بـ booking_local_id=0 و hotel_day_key=''.
--
--  الحل: إعادة بناء الجدول بلا القيد المحلي، ثم فرض الهوية العالمية:
--    UNIQUE (booking_uuid_cache, hotel_day_key) WHERE deleted_at IS NULL.
--
--  التشغيل:
--    npm run db:migrate:booking-nights-identity          (محلي)
--    npm run db:migrate:booking-nights-identity:remote   (D1 إنتاج)
--  الخطوات idempotent: إعادة التشغيل لا تُفقد صفاً (نسخ + إسقاط فقط).
-- ════════════════════════════════════════════════════════════════════

-- ─── 0) إعادة بناء الجدول بلا UNIQUE المحلي ──────────────────────────
-- (SQLite لا يسمح بإسقاط قيد جدول: نُنشئ جدولاً مطابقاً بلا القيد، ننسخ،
--  نُسقط القديم، ثم نُعيد التسمية. لا مفاتيح أجنبية تشير إلى هذا الجدول.)
CREATE TABLE IF NOT EXISTS booking_nights_v2 (
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
  booking_uuid_cache TEXT,
  server_booking_id INTEGER,
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

INSERT INTO booking_nights_v2 (
  id, booking_local_id, hotel_day_key, night_start, night_end, nightly_rate,
  sequence, is_processed_by_auto_fix, base_rate, adjustment, final_rate,
  applied_adjustment_uuid, applied_adjustments_json, booking_uuid_cache,
  server_booking_id, local_uuid, server_id, created_at, updated_at,
  deleted_at, last_modified, created_at_iso, updated_at_iso, deleted_at_iso,
  created_at_epoch, last_modified_epoch, version, origin, vector_clock,
  device_id, idempotency_key
)
SELECT
  id, booking_local_id, hotel_day_key, night_start, night_end, nightly_rate,
  sequence, is_processed_by_auto_fix, base_rate, adjustment, final_rate,
  applied_adjustment_uuid, applied_adjustments_json, booking_uuid_cache,
  server_booking_id, local_uuid, server_id, created_at, updated_at,
  deleted_at, last_modified, created_at_iso, updated_at_iso, deleted_at_iso,
  created_at_epoch, last_modified_epoch, version, origin, vector_clock,
  device_id, idempotency_key
FROM booking_nights;

DROP TABLE booking_nights;
ALTER TABLE booking_nights_v2 RENAME TO booking_nights;

-- ─── 1) طيّ التكرار الحيّ ────────────────────────────────────────────
-- صف واحد لكل (booking_uuid_cache, hotel_day_key). الفائز: المرتبط فعلاً
-- بحجز هويته، ثم الأحدث updated_at، ثم الأكبر id. الباقي يُخفى (tombstone)
-- ويرتفع updated_at/version كي يفوز الإخفاء في LWW على النسخ القديمة.
UPDATE booking_nights
SET deleted_at = CAST(strftime('%s', 'now') AS INTEGER),
    deleted_at_iso = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
    updated_at = MAX(
      COALESCE(updated_at, 0),
      CAST(strftime('%s', 'now') AS INTEGER)
    ),
    last_modified = MAX(
      COALESCE(last_modified, 0),
      CAST(strftime('%s', 'now') AS INTEGER)
    ),
    version = COALESCE(version, 1) + 1
WHERE id IN (
  SELECT id FROM (
    SELECT
      n.id AS id,
      ROW_NUMBER() OVER (
        PARTITION BY lower(TRIM(n.booking_uuid_cache)), n.hotel_day_key
        ORDER BY
          CASE WHEN EXISTS (
                 SELECT 1 FROM bookings b
                 WHERE b.id = n.booking_local_id
                   AND lower(replace(b.local_uuid, '-', '')) =
                       lower(replace(n.booking_uuid_cache, '-', ''))
               ) THEN 0 ELSE 1 END,
          COALESCE(n.updated_at, 0) DESC,
          n.id DESC
      ) AS rn
    FROM booking_nights n
    WHERE n.deleted_at IS NULL
      AND n.booking_uuid_cache IS NOT NULL
      AND TRIM(n.booking_uuid_cache) <> ''
  )
  WHERE rn > 1
);

-- ─── 2) اليتامى والمشوّهون ───────────────────────────────────────────
-- «ليلة» بلا يوم أو بلا بداية/نهاية، أو بلا حجز (رقم 0) لا تُحتسب.
UPDATE booking_nights
SET deleted_at = CAST(strftime('%s', 'now') AS INTEGER),
    deleted_at_iso = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
    version = COALESCE(version, 1) + 1
WHERE deleted_at IS NULL
  AND (
    booking_local_id <= 0
    OR TRIM(COALESCE(hotel_day_key, '')) = ''
    OR TRIM(COALESCE(night_start, '')) = ''
    OR TRIM(COALESCE(night_end, '')) = ''
  );

-- ─── 3) الهوية الخادمية للرابط ───────────────────────────────────────
-- نربط الليلة بمعرّف الحجز الخادمي المستخرج من uuid الحجز، فتصبح
-- booking_local_id دلالة خادمية لا رقماً جهازياً.
UPDATE booking_nights
SET booking_local_id = (
  SELECT b.id FROM bookings b
  WHERE lower(replace(b.local_uuid, '-', '')) =
        lower(replace(booking_nights.booking_uuid_cache, '-', ''))
  LIMIT 1
)
WHERE deleted_at IS NULL
  AND booking_uuid_cache IS NOT NULL
  AND TRIM(booking_uuid_cache) <> ''
  AND EXISTS (
    SELECT 1 FROM bookings b
    WHERE lower(replace(b.local_uuid, '-', '')) =
          lower(replace(booking_nights.booking_uuid_cache, '-', ''))
  )
  AND booking_local_id <> (
    SELECT b.id FROM bookings b
    WHERE lower(replace(b.local_uuid, '-', '')) =
          lower(replace(booking_nights.booking_uuid_cache, '-', ''))
    LIMIT 1
  );

-- ─── 4) الدرع: هوية عالمية فريدة لكل ليلة حيّة ───────────────────────
-- (فهرس جزئي: الليالي المخفية لا تشارك، فتاريخ الإخفاء محفوظ.)
CREATE UNIQUE INDEX IF NOT EXISTS ux_booking_nights_booking_day_live
  ON booking_nights(booking_uuid_cache, hotel_day_key)
  WHERE deleted_at IS NULL
    AND booking_uuid_cache IS NOT NULL
    AND TRIM(booking_uuid_cache) <> '';

CREATE INDEX IF NOT EXISTS idx_booking_nights_updated
  ON booking_nights(updated_at);
CREATE INDEX IF NOT EXISTS idx_booking_nights_booking
  ON booking_nights(booking_local_id);
CREATE INDEX IF NOT EXISTS idx_booking_nights_uuid_cache
  ON booking_nights(booking_uuid_cache);
CREATE INDEX IF NOT EXISTS idx_booking_nights_slot
  ON booking_nights(booking_local_id, hotel_day_key);

-- ─── تحقّق سريع بعد التنفيذ (شغّله يدوياً) ──────────────────────────
-- SELECT COUNT(*) AS live_rows FROM booking_nights WHERE deleted_at IS NULL;
-- SELECT COUNT(*) AS duplicate_groups FROM (
--   SELECT 1 FROM booking_nights
--   WHERE deleted_at IS NULL AND TRIM(COALESCE(booking_uuid_cache,'')) <> ''
--   GROUP BY lower(TRIM(booking_uuid_cache)), hotel_day_key HAVING COUNT(*) > 1
-- );
-- SELECT COUNT(*) AS orphans FROM booking_nights
--   WHERE deleted_at IS NULL AND (booking_local_id <= 0 OR TRIM(hotel_day_key) = '');
