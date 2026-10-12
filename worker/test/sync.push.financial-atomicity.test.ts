// ═══════════════════════════════════════════════════════════════
//  sync.push.financial-atomicity.test.ts — الذرية المالية (2026-09-24)
//
//  «تأكد من الذرية المالية» — حارس اختباري بمسار الدفع الفعلي
//  (handlePush → executeOperationAtomically) على الجداول المالية
//  الحساسة (payments / cash_transactions) يثبت بالتنفيذ:
//    1. نفس المفتاح مرتين → صف مالي واحد + replay مخزَّن (exactly-once)
//    2. سباق متوازٍ بنفس المفتاح → صف واحد بالضبط (claim داخل الدفعة)
//    3. فشل العملية المالية نفسها → تراجع كامل: لا صف مالي ولا claim
//       يتيم (claim + mutation في db.batch واحدة = معاملة واحدة)
//    4. فشل عملية شقيقة في نفس الطلب لا يُسقط العملية المالية الناجحة
//       (ذرية لكل عملية — جزئية النجاح عقد صريح للعميل)
//    5. الـ claim يحمل الاستجابة في صفيه (replay بلا تنفيذ ثانٍ)
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  resetDb,
  adminAuthHeader,
  pushOp,
  pushOperations,
  paymentPayload,
  cashTransactionPayload,
  roomPayload,
  type PushResponseBody,
} from './helpers';

beforeEach(async () => {
  await resetDb();
});

async function countRows(
  table: 'payments' | 'cash_transactions' | 'rooms',
  localUuid: string
): Promise<number> {
  const row = await env.DB.prepare(`SELECT COUNT(*) AS c FROM ${table} WHERE local_uuid = ?`)
    .bind(localUuid)
    .first<{ c: number }>();
  return row?.c ?? 0;
}

async function countAmountSum(table: 'payments' | 'cash_transactions'): Promise<number> {
  const row = await env.DB.prepare(`SELECT COALESCE(SUM(amount), 0) AS s FROM ${table}`).first<{ s: number }>();
  return row?.s ?? 0;
}

describe('financial atomicity — payments exactly-once', () => {
  it('same key pushed twice → one payment row + stored claim replay', async () => {
    const auth = await adminAuthHeader();
    const payload = paymentPayload();
    const op = pushOp('payments', 'create', payload, { idempotencyKey: 'fin-pay-once-1' });

    const first = await pushOperations(auth, [op]);
    const firstBody = (await first.json()) as PushResponseBody;
    expect(firstBody.summary.success).toBe(1);
    expect(await countRows('payments', String(payload.local_uuid))).toBe(1);

    // الـ claim يحمل الاستجابة داخل صفيه — أساس replay بلا تنفيذ
    const claim = await env.DB.prepare('SELECT entity, operation, response FROM idempotency_log WHERE key = ?')
      .bind('fin-pay-once-1')
      .first<{ entity: string; operation: string; response: string }>();
    expect(claim?.entity).toBe('payments');
    expect(claim?.operation).toBe('create');
    expect(JSON.parse(claim!.response)).toMatchObject({ entity: 'payments', operation: 'create' });

    const second = await pushOperations(auth, [op]);
    const secondBody = (await second.json()) as PushResponseBody;
    expect(secondBody.results[0].success).toBe(true);
    expect(secondBody.results[0].skipped).toBe(true);
    expect(await countRows('payments', String(payload.local_uuid))).toBe(1);
    // لا مضاعفة مبلغ إجمالاً — المبلغ ظل مرة واحدة
    expect(await countAmountSum('payments')).toBeCloseTo(150.75, 6);
  });

  it('two parallel requests with the same key → exactly one payment row', async () => {
    const auth = await adminAuthHeader();
    const payload = paymentPayload();
    const op = pushOp('payments', 'create', payload, { idempotencyKey: 'fin-pay-race-1' });

    const [resA, resB] = await Promise.all([
      pushOperations(auth, [op]),
      pushOperations(auth, [op]),
    ]);
    const bodyA = (await resA.json()) as PushResponseBody;
    const bodyB = (await resB.json()) as PushResponseBody;

    const all = [...bodyA.results, ...bodyB.results];
    expect(all.every((r) => r.success)).toBe(true);
    expect(all.filter((r) => r.skipped)).toHaveLength(1); // واحد نفّذ والآخر replay
    expect(await countRows('payments', String(payload.local_uuid))).toBe(1);
    expect(await countAmountSum('payments')).toBeCloseTo(150.75, 6);
  });

  it('failed payment mutation → full rollback: no payment row AND no orphan claim', async () => {
    const auth = await adminAuthHeader();
    // amount: null صراحةً → INSERT يصطدم بـ NOT NULL constraint داخل
    // الدفعة الذرية → تراجع الـ claim معه (idempotency_log يبقى فارغاً)
    const key = 'fin-pay-rollback-1';
    const broken = paymentPayload({ amount: null });
    const op = pushOp('payments', 'create', broken, { idempotencyKey: key });

    const res = await pushOperations(auth, [op]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.failed).toBe(1);
    expect(body.results[0].success).toBe(false);
    expect(String(body.results[0].error)).toContain('NOT NULL constraint failed');

    expect(await countRows('payments', String(broken.local_uuid))).toBe(0);
    const claim = await env.DB.prepare('SELECT key FROM idempotency_log WHERE key = ?').bind(key).first();
    expect(claim).toBeNull();

    // إعادة محاولة سليمة (مفتاح جديد) تنفّذ طبيعياً — لا حالة فاسدة متبقية
    const valid = paymentPayload({ local_uuid: broken.local_uuid });
    const retry = await pushOperations(auth, [pushOp('payments', 'create', valid)]);
    const retryBody = (await retry.json()) as PushResponseBody;
    expect(retryBody.summary.success).toBe(1);
    expect(await countRows('payments', String(valid.local_uuid))).toBe(1);
  });

  it('sibling failure in the same request never rolls back the applied payment', async () => {
    const auth = await adminAuthHeader();
    // غرفة بنفس room_number فريد → عملية الغرفة تفشل حتماً داخل دفعتها
    const seeded = roomPayload({ room_number: 'FIN-COLLISION-1' });
    await pushOperations(auth, [pushOp('rooms', 'create', seeded)]);

    const payment = paymentPayload();
    const victimRoom = roomPayload({
      room_number: 'FIN-COLLISION-1',
      local_uuid: 'room-fin-victim-1',
    });

    const res = await pushOperations(auth, [
      pushOp('payments', 'create', payment),
      pushOp('rooms', 'create', victimRoom),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.total).toBe(2);
    expect(body.summary.success).toBe(1); // الدفعة المالية
    expect(body.summary.failed).toBe(1); // الغرفة المتصادمة

    // العملية المالية ناجحة ومعزولة عن فشل الشقيقة (ذرية لكل عملية)
    expect(await countRows('payments', String(payment.local_uuid))).toBe(1);
    expect(await countRows('rooms', String(victimRoom.local_uuid))).toBe(0);
  });
});

describe('financial atomicity — cash_transactions', () => {
  it('same key twice → one cash row; replay keeps the ledger sum intact', async () => {
    const auth = await adminAuthHeader();
    const payload = cashTransactionPayload();
    const op = pushOp('cash_transactions', 'create', payload, { idempotencyKey: 'fin-cash-once-1' });

    const first = await pushOperations(auth, [op]);
    const firstBody = (await first.json()) as PushResponseBody;
    expect(firstBody.summary.success).toBe(1);

    const second = await pushOperations(auth, [op]);
    const secondBody = (await second.json()) as PushResponseBody;
    expect(secondBody.results[0].skipped).toBe(true);

    expect(await countRows('cash_transactions', String(payload.local_uuid))).toBe(1);
    expect(await countAmountSum('cash_transactions')).toBeCloseTo(150.75, 6);
  });
});
