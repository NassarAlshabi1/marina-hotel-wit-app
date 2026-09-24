// ═══════════════════════════════════════════════════════════════
//  maintenance.ts — D1 Scheduled (cron) maintenance jobs
//
//  ✅ (2026-09-24) يغلق ملاحظة المراجعة القديمة:
//  «idempotency_log بلا TTL/cleanup — ينمو بلا حد».
//
//  الاستدعاء: wrangler.toml [triggers] crons = ["17 3 * * *"] →
//  index.ts scheduled() → handleScheduledCleanup(env) هنا.
//
//  ─── لماذا الحذف آمن على exactly-once (تحليل، لا تخمين) ───────
//  صف الـ claim في idempotency_log مطلوب فقط لمدة نافذة إعادة
//  المحاولة المحتملة للعميل (timeout/انقطاع → نفس المفتاح يُرسل
//  ثانيةً). نافذة إعادة المحاولة الواقعية دقائق؛ حد الاحتفاظ
//  الافتراضي 30 يوماً يفوقها بأوامر حجم. وحتى في أسوأ فرضية
//  (وصل retry بعد حذف الـ claim):
//    * create → dupLocalUuid (UNIQUE محلي على كل جدول) → skip.
//    * update → LWW يعيد القرار ويكتب نفس الحمولة (لا مضاعفة
//      مبلغ — المبالغ تسكن صفوف الكيانات بمفتاح local_uuid
//      UNIQUE، لا في الـ claim) + version bump زائد فقط.
//    * delete → tombstone قائم → UPDATE المحرس يصطدم بـ
//      deleted_at IS NULL → 0 صف → noop ناجح.
//  السجل المالي الكامل يبقى في sync_log (audit trail) — الـ claim
//  لا يحوي مبالغ أصلاً، فقط JSON الاستجابة.
// ═══════════════════════════════════════════════════════════════

import type { D1Database } from '@cloudflare/workers-types';

// ─── Env contract ─────────────────────────────────────────────

export interface MaintenanceEnv {
  DB: D1Database;
  /** أيام الاحتفاظ بصفوف idempotency_log (نص في [vars]) — افتراضي 30. */
  IDEMPOTENCY_RETENTION_DAYS?: string;
  /** حجم دفعة الحذف الواحدة — افتراضي 500 (وسقف صلب 500). */
  IDEMPOTENCY_CLEANUP_BATCH?: string;
}

export interface IdempotencyCleanupResult {
  /** مجموع الصفوف المحذوفة في هذا التشغيل. */
  deleted: number;
  /** عدد عبارات DELETE المنفذة (الدفعات). */
  chunks: number;
  /** الطابع الفاصل: حُذف ما كان أقدم منه (processed_at < cutoff). */
  cutoff: number;
  retentionDays: number;
  batchSize: number;
}

export const DEFAULT_IDEMPOTENCY_RETENTION_DAYS = 30;
export const DEFAULT_IDEMPOTENCY_CLEANUP_BATCH = 500;
/** سقف صلب لدفعة الحذف — كل DELETE معاملة ضمنية صغيرة مهما أخطأ المشغّل. */
export const MAX_IDEMPOTENCY_CLEANUP_BATCH = 500;
/** سقف الاحتفاظ (10 سنوات) — حماية من قيمة مطبوعة بالخطأ مثل 99999. */
export const MAX_IDEMPOTENCY_RETENTION_DAYS = 3650;

// ─── Env parsing (fail-safe) ──────────────────────────────────

/**
 * قيمة غير رقمية → الافتراضي. قيمة رقمية → تقييد [1, 3650]:
 * «0» يعني حذف claims من نفس اليوم (نافذة retry حية) — يُرفع إلى 1؛
 * والاحتفاظ الأطول من 10 سنوات خطأ مطبعي يُقصّ لا يُنفّذ.
 * ⚠️ (من الاختبارات) Number('') = 0 وليس NaN — الفراغ/المسافات تُعامَل
 * كقيمة غير مضبوطة → الافتراضي، لا الأرضية 1.
 */
export function parseRetentionDays(raw: string | undefined): number {
  if (raw === undefined || raw.trim() === '') return DEFAULT_IDEMPOTENCY_RETENTION_DAYS;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) return DEFAULT_IDEMPOTENCY_RETENTION_DAYS;
  return Math.min(Math.max(Math.floor(parsed), 1), MAX_IDEMPOTENCY_RETENTION_DAYS);
}

/**
 * حجم الدفعة أثر أداء فقط (لا صحة) — قيمة غير رقمية أو <1 → الافتراضي،
 * وما فوق السقف 500 يُقصّ ليظل كل DELETE معاملة صغيرة.
 */
export function parseCleanupBatch(raw: string | undefined): number {
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed < 1) return DEFAULT_IDEMPOTENCY_CLEANUP_BATCH;
  return Math.min(Math.floor(parsed), MAX_IDEMPOTENCY_CLEANUP_BATCH);
}

// ─── Core cleanup ─────────────────────────────────────────────

/**
 * حذف صفوف idempotency_log المنتهية (processed_at < cutoff) على دفعات.
 *
 * لماذا `rowid IN (SELECT … LIMIT n)` بدل `DELETE … LIMIT n`؟
 * صيغة DELETE...LIMIT تتطلب SQLITE_ENABLE_UPDATE_DELETE_LIMIT وقت ترجمة
 * SQLite — غير مضمون على D1. نمط الـ sub-select بـ rowid SQLite قياسي
 * ويعمل في كل بيئة، ويحدّ كل عبارة بـ n صفاً كحد أقصى (بلا مسح كامل
 * بفضل idx_idempotency_processed_at — ترحيل 0008).
 *
 * كل DELETE معاملة ضمنية مستقلة: فشل منتصفَ الطريق يترك الدفعات
 * السابقة محذوفة — مقبول ومطمئن: الحذف رتيب ومتكرر الأمان
 * (idempotent) والتشغيل القادم يكمل البقية.
 */
export async function cleanupIdempotencyLog(
  db: D1Database,
  retentionDays: number,
  batchSize: number
): Promise<IdempotencyCleanupResult> {
  const now = Math.floor(Date.now() / 1000);
  const cutoff = now - retentionDays * 86400;

  let deleted = 0;
  let chunks = 0;
  for (;;) {
    const result = await db
      .prepare(
        `DELETE FROM idempotency_log
         WHERE processed_at < ?1
           AND rowid IN (
             SELECT rowid FROM idempotency_log WHERE processed_at < ?1 LIMIT ?2
           )`
      )
      .bind(cutoff, batchSize)
      .run();
    const removed = result.meta?.changes ?? 0;
    chunks += 1;
    deleted += removed;
    if (removed < batchSize) break;
  }

  return { deleted, chunks, cutoff, retentionDays, batchSize };
}

// ─── Scheduled entry point ────────────────────────────────────

/** نقطة الاستدعاء من scheduled() في index.ts — منفصلة لقابلية الاختبار. */
export async function handleScheduledCleanup(
  env: MaintenanceEnv
): Promise<IdempotencyCleanupResult> {
  const retentionDays = parseRetentionDays(env.IDEMPOTENCY_RETENTION_DAYS);
  const batchSize = parseCleanupBatch(env.IDEMPOTENCY_CLEANUP_BATCH);
  return cleanupIdempotencyLog(env.DB, retentionDays, batchSize);
}
