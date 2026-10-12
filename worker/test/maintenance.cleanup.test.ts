// ═══════════════════════════════════════════════════════════════
//  maintenance.cleanup.test.ts — idempotency_log TTL cleanup (2026-09-24)
//
//  يغلق ملاحظة المراجعة «idempotency_log ينمو بلا حد» بحارس اختباري:
//    - الحذف يحصر نفسه في الأقدم من نافذة الاحتفاظ (حد فاصل صارم <)
//    - التراكم الأكبر من دفعة واحدة يُنظف على دفعات (rowid IN … LIMIT)
//    - فهرس ترحيل 0008 موجود (لا مسح جدول كامل في كل تشغيل)
//    - تحليل متغيرات البيئة آمن: قيم خاطئة → افتراضيات/تقييد، لا انفجار
//    - handleScheduledCleanup يقرأ قيم wrangler.toml الفعلية (30/500)
//    - أسوأ فرضية مالية: retry بعد حذف الـ claim يبقى exactly-once
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  cleanupIdempotencyLog,
  handleScheduledCleanup,
  parseRetentionDays,
  parseCleanupBatch,
  DEFAULT_IDEMPOTENCY_RETENTION_DAYS,
  DEFAULT_IDEMPOTENCY_CLEANUP_BATCH,
  MAX_IDEMPOTENCY_CLEANUP_BATCH,
  MAX_IDEMPOTENCY_RETENTION_DAYS,
} from '../src/maintenance';
import {
  resetDb,
  adminAuthHeader,
  pushOp,
  pushOperations,
  paymentPayload,
  type PushResponseBody,
} from './helpers';

beforeEach(async () => {
  await resetDb();
});

const DAY = 86400;

async function insertClaim(key: string, processedAt: number): Promise<void> {
  await env.DB.prepare(
    'INSERT INTO idempotency_log (key, entity, operation, entity_id, processed_at, response) VALUES (?, ?, ?, ?, ?, ?)'
  )
    .bind(key, 'payments', 'create', key, processedAt, '{"entity":"payments"}')
    .run();
}

async function countClaims(): Promise<number> {
  const row = await env.DB.prepare('SELECT COUNT(*) AS c FROM idempotency_log').first<{ c: number }>();
  return row?.c ?? 0;
}

describe('cleanupIdempotencyLog — retention window', () => {
  it('deletes strictly-older-than-cutoff rows and keeps the cutoff boundary', async () => {
    // تشغيل فارغ أولاً للحصول على cutoff الفعلي بنفس الخوارزمية
    const probe = await cleanupIdempotencyLog(env.DB, 30, 500);
    expect(probe.deleted).toBe(0);

    await insertClaim('expired-1', probe.cutoff - 1); // أقدم بثانية → يُحذف
    await insertClaim('boundary-1', probe.cutoff); // على الحد بالضبط → يبقى (< صارم)
    await insertClaim('fresh-1', probe.cutoff + DAY);

    const result = await cleanupIdempotencyLog(env.DB, 30, 500);
    expect(result.deleted).toBe(1);
    expect(result.retentionDays).toBe(30);
    expect(result.batchSize).toBe(500);
    expect(await countClaims()).toBe(2); // boundary + fresh
  });

  it('chunks a backlog larger than one batch (7 stale rows, batch=3 → 3 chunks)', async () => {
    const stale = Math.floor(Date.now() / 1000) - 40 * DAY;
    for (let i = 0; i < 7; i += 1) await insertClaim(`stale-${i}`, stale);

    const result = await cleanupIdempotencyLog(env.DB, 30, 3);
    expect(result.deleted).toBe(7);
    expect(result.chunks).toBe(3); // 3 + 3 + 1
    expect(await countClaims()).toBe(0);
  });

  it('mixed backlog: stale rows go, live claims survive untouched', async () => {
    const now = Math.floor(Date.now() / 1000);
    for (let i = 0; i < 5; i += 1) await insertClaim(`old-${i}`, now - 31 * DAY);
    for (let i = 0; i < 5; i += 1) await insertClaim(`live-${i}`, now - DAY);

    const result = await cleanupIdempotencyLog(env.DB, 30, 500);
    expect(result.deleted).toBe(5);
    expect(await countClaims()).toBe(5);

    const survivors = await env.DB.prepare(
      "SELECT key FROM idempotency_log WHERE key LIKE 'live-%' ORDER BY key"
    ).all<{ key: string }>();
    expect(survivors.results).toHaveLength(5);
  });
});

describe('migration 0008 — TTL index exists', () => {
  it('idx_idempotency_processed_at is present so cleanup never full-scans', async () => {
    const row = await env.DB.prepare(
      "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='idempotency_log' AND name='idx_idempotency_processed_at'"
    ).first<{ name: string }>();
    expect(row?.name).toBe('idx_idempotency_processed_at');
  });
});

describe('env parsing — fail-safe defaults', () => {
  it('retention: non-numeric → default; numeric clamped to [1, 3650]', () => {
    expect(parseRetentionDays(undefined)).toBe(DEFAULT_IDEMPOTENCY_RETENTION_DAYS);
    expect(parseRetentionDays('')).toBe(DEFAULT_IDEMPOTENCY_RETENTION_DAYS);
    expect(parseRetentionDays('abc')).toBe(DEFAULT_IDEMPOTENCY_RETENTION_DAYS);
    // «0» يعني حذف claims اليوم نفسه (نافذة retry حية) → يُرفع للأرضية 1
    expect(parseRetentionDays('0')).toBe(1);
    expect(parseRetentionDays('-5')).toBe(1);
    expect(parseRetentionDays('7')).toBe(7);
    expect(parseRetentionDays('99999')).toBe(MAX_IDEMPOTENCY_RETENTION_DAYS);
  });

  it('batch: non-numeric or <1 → default; hard-capped at 500', () => {
    expect(parseCleanupBatch(undefined)).toBe(DEFAULT_IDEMPOTENCY_CLEANUP_BATCH);
    expect(parseCleanupBatch('abc')).toBe(DEFAULT_IDEMPOTENCY_CLEANUP_BATCH);
    expect(parseCleanupBatch('0')).toBe(DEFAULT_IDEMPOTENCY_CLEANUP_BATCH);
    expect(parseCleanupBatch('1')).toBe(1);
    expect(parseCleanupBatch('100000')).toBe(MAX_IDEMPOTENCY_CLEANUP_BATCH);
  });
});

describe('handleScheduledCleanup — real env contract', () => {
  it('uses wrangler.toml vars (retention=30, batch=500) end-to-end', async () => {
    const now = Math.floor(Date.now() / 1000);
    await insertClaim('expired-env-1', now - 31 * DAY);
    await insertClaim('live-env-1', now - DAY);

    // env يحمل IDEMPOTENCY_* من [vars] في wrangler.toml عبر miniflare
    expect(env.IDEMPOTENCY_RETENTION_DAYS).toBe('30');
    expect(env.IDEMPOTENCY_CLEANUP_BATCH).toBe('500');

    const result = await handleScheduledCleanup(env);
    expect(result.retentionDays).toBe(30);
    expect(result.batchSize).toBe(500);
    expect(result.deleted).toBe(1);
    expect(await countClaims()).toBe(1);
  });

  it('operator overrides win (retention=1, batch=2) — 2-day-old claims go', async () => {
    const now = Math.floor(Date.now() / 1000);
    for (let i = 0; i < 3; i += 1) await insertClaim(`ovr-${i}`, now - 2 * DAY);

    const result = await handleScheduledCleanup({
      DB: env.DB,
      IDEMPOTENCY_RETENTION_DAYS: '1',
      IDEMPOTENCY_CLEANUP_BATCH: '2',
    });
    expect(result.retentionDays).toBe(1);
    expect(result.batchSize).toBe(2);
    expect(result.deleted).toBe(3);
    expect(await countClaims()).toBe(0);
  });

  it('garbage env values degrade to defaults, never explode', async () => {
    const now = Math.floor(Date.now() / 1000);
    await insertClaim('garbage-1', now - 100 * DAY);

    const result = await handleScheduledCleanup({
      DB: env.DB,
      IDEMPOTENCY_RETENTION_DAYS: 'not-a-number',
      IDEMPOTENCY_CLEANUP_BATCH: 'also-bad',
    });
    expect(result.retentionDays).toBe(DEFAULT_IDEMPOTENCY_RETENTION_DAYS);
    expect(result.batchSize).toBe(DEFAULT_IDEMPOTENCY_CLEANUP_BATCH);
    expect(result.deleted).toBe(1);
  });
});

describe('financial worst case — retry after the claim was cleaned', () => {
  it('payment replay after claim deletion stays exactly-once (dup local_uuid → skip)', async () => {
    const auth = await adminAuthHeader();
    const payload = paymentPayload();
    const op = pushOp('payments', 'create', payload, { idempotencyKey: 'pay-claim-cleaned-1' });

    const first = await pushOperations(auth, [op]);
    const firstBody = (await first.json()) as PushResponseBody;
    expect(firstBody.summary.success).toBe(1);

    // عمّر صف الـ claim كأن 31 يوماً مرّت ثم شغّل التنظيف
    await env.DB.prepare('UPDATE idempotency_log SET processed_at = processed_at - 31 * 86400 WHERE key = ?')
      .bind('pay-claim-cleaned-1')
      .run();
    const cleaned = await handleScheduledCleanup(env);
    expect(cleaned.deleted).toBe(1);

    // الـ claim حُذف فعلاً
    const claim = await env.DB.prepare('SELECT key FROM idempotency_log WHERE key = ?')
      .bind('pay-claim-cleaned-1')
      .first();
    expect(claim).toBeNull();

    // retry بنفس المفتاح بعد حذف الـ claim: لا صف مالي ثانٍ مهما حدث
    const retry = await pushOperations(auth, [op]);
    const retryBody = (await retry.json()) as PushResponseBody;
    expect(retryBody.results[0].success).toBe(true);

    const row = await env.DB
      .prepare('SELECT COUNT(*) AS c FROM payments WHERE local_uuid = ?')
      .bind(payload.local_uuid)
      .first<{ c: number }>();
    expect(row?.c).toBe(1);
  });
});
