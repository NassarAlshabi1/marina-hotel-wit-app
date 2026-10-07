-- ════════════════════════════════════════════════════════════════
--  0008_idempotency_log_cleanup.sql
--  (2026-09-24) فهرس TTL لجدول idempotency_log — تمكين cleanup job
--
--  التشخيص (بالأدلة من schema.sql قبل هذا الترحيل):
--  idempotency_log كان يحمل فهرساً وحيداً (entity, entity_id) —
--  أي حذف بحسب عمر الصف (processed_at) = مسح جدول كامل في كل تشغيل.
--  مع نمو الجدول بلا حد (بلا TTL/cleanup) صار التنظيف الدوري سينمو
--  خطياً مع حجم الجدول. هذا الفهرس يجعل حذف الصفوف المنتهية
--  (processed_at < cutoff) بحثاً فهرسياً O(log n) بدل O(n).
--
--  الـ cleanup نفسه: D1 Scheduled handler (cron يومي 03:17 UTC في
--  wrangler.toml) → src/maintenance.ts handleScheduledCleanup().
--
--  لماذا لا نحذف الأعمدة/الصفوف هنا؟ لا شيء يحذفه هذا الترحيل —
--  إضافة فهرس فقط، آمنة للتشغيل المتكرر (IF NOT EXISTS) وبلا لمس
--  لأي صف مالي أو سجل idempotency قائم.
-- ════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_idempotency_processed_at
  ON idempotency_log(processed_at);
