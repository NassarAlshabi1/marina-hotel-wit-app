-- ملاحظات الحجز: عمود تخزين UUID الحجز — المفتاح العالمي لحلّ booking_id
-- عبر الأجهزة (نظير booking_uuid_cache في booking_nights وdebts وpayments
-- من هجرة 0005). الحلّ يقع في عميل السحب (uuid-cache ← server_id ظلّ ←
-- server_booking_id قديم) والعمود اختياري: عميل قديم لا يرسله والـWorker
-- يرشّحه قبل وجوده.
ALTER TABLE booking_notes ADD COLUMN booking_uuid_cache TEXT;
CREATE INDEX IF NOT EXISTS idx_booking_notes_uuid_cache ON booking_notes(booking_uuid_cache);
