// ═══════════════════════════════════════════════════════════════
//  sync.push.idempotency.test.ts — P0 atomic idempotency (2026-09-24)
//
//  يحرس عقد exactly-once للرفع بعد إعادة تصميم handlePush:
//    - نفس idempotencyKey مرتين → mutation مرة واحدة + نفس الاستجابة
//    - سباق مكرر (طلبان متوازيان بنفس المفتاح) → mutation واحدة بالضبط
//      (claim ذري داخل db.batch — أول عبارة ترفض التكرار فتراجع الكل)
//    - فشل الـ mutation → لا سجل idempotency → إعادة المحاولة تنفّذ
//    - نفس local_uuid من جهازين (مفتاحان مختلفان) → صف واحد
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  resetDb,
  adminAuthHeader,
  pushOp,
  pushOperations,
  roomPayload,
  type PushResponseBody,
} from './helpers';

beforeEach(async () => {
  await resetDb();
});

async function countRooms(localUuid: string): Promise<number> {
  const row = await env.DB.prepare('SELECT COUNT(*) AS c FROM rooms WHERE local_uuid = ?')
    .bind(localUuid)
    .first<{ c: number }>();
  return row?.c ?? 0;
}

describe('P0 idempotency: exactly-once effect', () => {
  it('same key twice → mutation once → same response twice (skipped replay)', async () => {
    const auth = await adminAuthHeader();
    const payload = roomPayload();
    const key = 'idem-exactly-once-1';
    const op = pushOp('rooms', 'create', payload, { idempotencyKey: key });

    const first = await pushOperations(auth, [op]);
    const firstBody = (await first.json()) as PushResponseBody;
    expect(firstBody.summary.success).toBe(1);
    expect(firstBody.results[0].skipped).toBeUndefined();
    expect(firstBody.results[0].entityId).toBe(payload.local_uuid);

    const second = await pushOperations(auth, [op]);
    const secondBody = (await second.json()) as PushResponseBody;
    expect(secondBody.results[0].idempotencyKey).toBe(key);
    expect(secondBody.results[0].success).toBe(true);
    expect(secondBody.results[0].skipped).toBe(true);
    // نفس entityId المخزَّن مع نتيجة التنفيذ الأولى — replay وليس تنفيذاً جديداً
    expect(secondBody.results[0].entityId).toBe(String(payload.local_uuid));
    expect(await countRooms(String(payload.local_uuid))).toBe(1);
  });

  it('concurrent duplicate: two parallel requests with the same key → exactly one mutation', async () => {
    const auth = await adminAuthHeader();
    const payload = roomPayload();
    const op = pushOp('rooms', 'create', payload, { idempotencyKey: 'idem-race-1' });

    const [resA, resB] = await Promise.all([
      pushOperations(auth, [op]),
      pushOperations(auth, [op]),
    ]);
    const bodyA = (await resA.json()) as PushResponseBody;
    const bodyB = (await resB.json()) as PushResponseBody;

    const all = [...bodyA.results, ...bodyB.results];
    expect(all).toHaveLength(2);
    // كلا الطلبين ينجحان (واحد نفّذ والآخر replay)
    expect(all.every((r) => r.success)).toBe(true);
    const applied = all.filter((r) => !r.skipped);
    const replayed = all.filter((r) => r.skipped);
    expect(applied).toHaveLength(1);
    expect(replayed).toHaveLength(1);
    expect(await countRooms(String(payload.local_uuid))).toBe(1);
  });

  it('failed mutation → idempotency NOT committed → the same key can execute on retry', async () => {
    const auth = await adminAuthHeader();
    // فشل حتمي: rooms.room_number فريد — إدراج غرفة بنفس الرقم ومفتاح
    // local_uuid مختلف يفشل بـ UNIQUE constraint داخل الدفعة الذرية،
    // فيتراجع الـ claim معه (idempotency_log يبقى فارغاً للمفتاح).
    const seeded = roomPayload({ room_number: 'UNIQUE-COLLISION-1' });
    await pushOperations(auth, [pushOp('rooms', 'create', seeded)]);

    const colliding = roomPayload({
      room_number: 'UNIQUE-COLLISION-1',
      local_uuid: 'room-collision-victim-1',
    });
    const key = 'idem-failed-mutation-1';
    const op = pushOp('rooms', 'create', colliding, { idempotencyKey: key });

    const first = await pushOperations(auth, [op]);
    const firstBody = (await first.json()) as PushResponseBody;
    expect(firstBody.summary.failed).toBe(1);

    // لا سجل idempotency — الفشل تراجع عن الـ claim معه
    const idem = await env.DB.prepare('SELECT key FROM idempotency_log WHERE key = ?')
      .bind(key)
      .first();
    expect(idem).toBeNull();

    // إعادة المحاولة بنفس المفتاح تنفّذ من جديد (لا skipped replay لنتيجة وهمية)
    const retry = await pushOperations(auth, [op]);
    const retryBody = (await retry.json()) as PushResponseBody;
    expect(retryBody.summary.failed).toBe(1);
    expect(retryBody.results[0].skipped).toBeUndefined();
    expect(await countRooms(String(colliding.local_uuid))).toBe(0);
  });

  it('same local_uuid from two devices (different keys) → no duplicate row', async () => {
    const auth = await adminAuthHeader();
    const payloadA = roomPayload({ device_id: 'device-A' });
    const payloadB = { ...payloadA, device_id: 'device-B' };

    const resA = await pushOperations(auth, [pushOp('rooms', 'create', payloadA)]);
    const resB = await pushOperations(auth, [pushOp('rooms', 'create', payloadB)]);
    const bodyA = (await resA.json()) as PushResponseBody;
    const bodyB = (await resB.json()) as PushResponseBody;

    expect(bodyA.summary.success).toBe(1);
    expect(bodyB.summary.success).toBe(1);
    expect(await countRooms(String(payloadA.local_uuid))).toBe(1);
  });

  it('update retried with the same key → one version bump only', async () => {
    const auth = await adminAuthHeader();
    const payload = roomPayload();
    await pushOperations(auth, [pushOp('rooms', 'create', payload)]);

    const op = pushOp('rooms', 'update', { ...payload, price: 300 }, {
      vectorClock: '{"device-A":2}',
      updatedAt: 1700000100,
      idempotencyKey: 'idem-update-once-1',
    });
    await pushOperations(auth, [op]);
    const again = await pushOperations(auth, [op]);
    const againBody = (await again.json()) as PushResponseBody;
    expect(againBody.results[0].skipped).toBe(true);

    const row = await env.DB.prepare('SELECT version, price FROM rooms WHERE local_uuid = ?')
      .bind(payload.local_uuid)
      .first<{ version: number; price: number }>();
    expect(row?.version).toBe(2); // bump واحد فقط
    expect(row?.price).toBe(300);
  });
});
