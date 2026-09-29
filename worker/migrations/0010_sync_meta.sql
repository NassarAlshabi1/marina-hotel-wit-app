-- ═══════════════════════════════════════════════════════════════
--  0010 — sync_meta: جيل بيانات المزامنة (epoch)
--
--  مؤشر السحب زمني (updated_at) فيبقى صالحاً عبر الكتابات العادية، لكن
--  جراحة بيانات خادمية تحفظ الطوابع القديمة (إعادة استيراد، استعادة
--  Time Travel، إصلاح جماعي) تترك صفوفاً أقدم من مؤشرات الأجهزة فلا
--  تصلها أبداً. epoch هو الرافعة الصريحة: يُعاد مع كل رد سحب، وتدويره
--  (POST /api/admin/sync/rotate-epoch — admin فقط) يجعل كل جهاز يصفّر
--  مؤشره ويعيد السحب الكامل من الصفر.
--
--  إضافي بحت (لا يمس أي جدول قائم). القيمة الأولى تُزرع هنا، والـ Worker
--  يزرعها كسولاً أيضاً (INSERT OR IGNORE) لو طُبّق schema.sql بدل الترحيل.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS sync_meta (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL,
  updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);

INSERT OR IGNORE INTO sync_meta (k, v) VALUES ('epoch', lower(hex(randomblob(16))));
