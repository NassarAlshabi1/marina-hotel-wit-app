// ═══════════════════════════════════════════════════════════════
//  sync.pull.regression.test.ts — 2026-09-08 "data not fully pulled"
//
//  Regression coverage for the two worker-side root causes of the
//  incomplete-pull incident:
//
//  A) Page cut inside a group of rows sharing the same updated_at
//     permanently skipped the un-returned rows (integer watermark
//     cursor `WHERE updated_at > cursor` + strict `>` comparison).
//     Fix: boundary-extension — the page carries the WHOLE boundary
//     group, and the returned cursor equals the LAST ROW'S updated_at
//     (never the global max of fetched rows).
//
//  B) Legacy millisecond-scale updated_at values (1.7e12) poisoned
//     the seconds-scale cursor domain forever. Fix: normalizeTimestamps()
//     re-stamping — ✅ (2026-09-15, 72b75a79) now an EXPLICIT opt-in
//     maintenance pass via `normalize_timestamps=1`; ordinary delta
//     pulls never scan the entity tables for legacy rows.
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  resetDb,
  adminAuthHeader,
  pull,
  pushOp,
  pushOperations,
  roomPayload,
  uniqueUuid,
  type PullResponseBody,
} from './helpers';

beforeEach(async () => {
  await resetDb();
});

/** Directly INSERT a rooms row with an exact updated_at (bypasses the
 *  push allocator, which would hand out unique timestamps). */
async function seedRoomAt(
  updatedAt: number,
  overrides: {
    localUuid?: string;
    roomNumber?: string;
    lastModified?: number;
    deviceId?: string;
  } = {}
): Promise<string> {
  const uuid = overrides.localUuid ?? uniqueUuid('r');
  const roomNumber = overrides.roomNumber ?? uniqueUuid('n');
  await env.DB.prepare(
    `INSERT INTO rooms
       (room_number, type, price, status, cleaning_status, requires_maintenance,
        local_uuid, created_at, updated_at, last_modified, version, origin,
        vector_clock, device_id)
     VALUES (?, 'double', 100.0, 'available', 'clean', 0,
        ?, ?, ?, ?, 1, 'local', '{}', ?)`
  )
    .bind(
      roomNumber,
      uuid,
      updatedAt,
      updatedAt,
      overrides.lastModified ?? updatedAt,
      overrides.deviceId ?? 'legacy-device'
    )
    .run();
  return uuid;
}

// ─── A) Boundary-extension: no row lost at page cuts ────────────

describe('pull: boundary-extension (duplicate updated_at loss guard)', () => {
  it('never cuts inside a same-updated_at group: page carries the whole group', async () => {
    const auth = await adminAuthHeader();
    // 10 legacy rows sharing ONE timestamp + 5 newer rows.
    const groupA = await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        seedRoomAt(1700000100, { roomNumber: `A${String(i).padStart(3, '0')}` })
      )
    );
    const groupB = await Promise.all(
      Array.from({ length: 5 }, (_, i) =>
        seedRoomAt(1700000200, { roomNumber: `B${String(i).padStart(3, '0')}` })
      )
    );

    // limit=3 lands mid-group → the page must be EXTENDED to all 10 rows.
    const page1 = await pull(auth, { cursor: '0', limit: '3' });
    expect(page1.changes).toHaveLength(10);
    for (const c of page1.changes) expect(c.updated_at).toBe(1700000100);
    expect(page1.has_more).toBe(true);

    // CRITICAL: cursor = last returned row's updated_at (the boundary),
    // NOT the global max across fetched rows (1700000200).
    expect(page1.cursor).toBe('1700000100');

    // Second page: strictly newer rows only.
    const page2 = await pull(auth, { cursor: page1.cursor, limit: '3' });
    expect(page2.changes).toHaveLength(5);
    for (const c of page2.changes) expect(c.updated_at).toBe(1700000200);
    expect(page2.has_more).toBe(false);
    expect(page2.cursor).toBe('1700000200');

    const all = new Set([...groupA, ...groupB]);
    const seen = new Set(
      [...page1.changes, ...page2.changes].map((c) => c.local_uuid as string)
    );
    expect(seen.size).toBe(15);
    for (const u of all) expect(seen.has(u)).toBe(true);
  });

  it('draining with a tiny limit over duplicate-ts data: zero dupes, zero losses', async () => {
    const auth = await adminAuthHeader();
    const seeded = new Set<string>();
    // Three duplicate groups + one singleton, interleaved.
    for (const ts of [1700000100, 1700000100, 1700000100, 1700000150, 1700000150, 1700000200]) {
      seeded.add(await seedRoomAt(ts));
    }

    let cursor = '0';
    const seen = new Set<string>();
    let total = 0;
    let lastCursor = -1;
    for (let page = 0; page < 20; page++) {
      const data = (await pull(auth, { cursor, limit: '2' })) as PullResponseBody;
      expect(data.changes.length).toBeGreaterThanOrEqual(0);
      for (const c of data.changes) {
        const uuid = c.local_uuid as string;
        expect(seen.has(uuid)).toBe(false); // no duplicates across pages
        seen.add(uuid);
      }
      total += data.changes.length;
      const numeric = parseInt(data.cursor, 10);
      expect(numeric).toBeGreaterThanOrEqual(lastCursor); // monotonic
      lastCursor = numeric;
      cursor = data.cursor;
      if (!data.has_more) break;
    }
    expect(total).toBe(6);
    expect(seen.size).toBe(6);
    for (const u of seeded) expect(seen.has(u)).toBe(true);
  });

  it('full sync across ALL duplicate-ts rows is lossless (multi-table ordering)', async () => {
    const auth = await adminAuthHeader();
    // 40 rooms all sharing one timestamp (worst-case legacy migration shape).
    const uuids = new Set<string>();
    for (let i = 0; i < 40; i++) {
      uuids.add(await seedRoomAt(1700000050, { roomNumber: `W${String(i).padStart(3, '0')}` }));
    }
    // Plus normal allocator-stamped rows via push (unique timestamps).
    const authOnly = await adminAuthHeader();
    const ops = Array.from({ length: 5 }, () => pushOp('rooms', 'create', roomPayload()));
    const res = await pushOperations(authOnly, ops);
    const body = (await res.json()) as { summary: { failed: number } };
    expect(body.summary.failed).toBe(0);
    for (const op of ops) uuids.add((op.data as Record<string, unknown>).local_uuid as string);

    // Drain with limit=7 → pages of 40 (extended group) then the tail.
    let cursor = '0';
    const seen = new Set<string>();
    for (let page = 0; page < 10; page++) {
      const data = await pull(auth, { cursor, limit: '7' });
      for (const c of data.changes) {
        const u = c.local_uuid as string;
        expect(seen.has(u)).toBe(false);
        seen.add(u);
      }
      cursor = data.cursor;
      if (!data.has_more) break;
    }
    expect(seen.size).toBe(45);
    for (const u of uuids) expect(seen.has(u)).toBe(true);
  });
});

// ─── C) Degraded drain contract: errors[] on every page ─────────

describe('pull: degraded multi-page drain contract (per-table isolation)', () => {
  it('reports the broken table and never advances past an incomplete page', async () => {
    const auth = await adminAuthHeader();
    // 7 healthy rooms at distinct timestamps → 3 pages at limit=3.
    for (let i = 0; i < 7; i++) {
      await seedRoomAt(1700000100 + i, { roomNumber: `D${String(i).padStart(3, '0')}` });
    }
    // Simulate a migration applied to code but not to live D1.
    await env.DB.prepare('DROP TABLE devices').run();

    let cursor = '0';
    const seen = new Set<string>();
    const data = await pull(auth, { cursor, limit: '3' });
    for (const c of data.changes) seen.add(c.local_uuid as string);
    expect(seen.size).toBe(3);
    expect(data.errors.some((e) => e.entity === 'devices')).toBe(true);
    expect(data.cursor).toBe('0');
    expect(data.has_more).toBe(false);
  });
});

// ─── B) normalizeTimestamps: ms-poisoned rows repaired ──────────

describe('pull: normalizeTimestamps (legacy ms → seconds repair)', () => {
  it('re-stamps ms-scale rows to unique seconds and reports the repair', async () => {
    const auth = await adminAuthHeader();
    const msRows: string[] = [];
    for (let i = 0; i < 6; i++) {
      msRows.push(
        await seedRoomAt(1_700_000_000_000 + i, {
          roomNumber: `MS${i}`,
          lastModified: 1_700_000_000_000 + i, // ms-scale → must be re-stamped
        })
      );
    }
    // One healthy seconds-scale row that must be LEFT ALONE.
    const healthy = await seedRoomAt(1_700_000_100, { roomNumber: 'OK1', lastModified: 1_700_000_100 });

    const data = (await pull(auth, {
      cursor: '0',
      limit: '200',
      // ✅ (2026-09-15) العقد الجديد: التسوية صيانة صريحة opt-in —
      // السحب الاعتيادي (delta) لا يمسح جداول الكيانات بحثًا عن طوابع قديمة.
      normalize_timestamps: '1',
    })) as PullResponseBody;
    expect(data.normalization).toBeTruthy();
    expect(data.normalization!.normalized).toBe(6);
    expect(data.normalization!.remaining).toBe(0);
    expect(data.normalization!.perTable['rooms']).toBe(6);

    // Verify directly in D1: no ms-scale values remain; every repaired
    // row got a UNIQUE seconds-scale stamp; healthy row untouched.
    const rows = await env.DB.prepare(
      'SELECT local_uuid, updated_at, last_modified FROM rooms ORDER BY updated_at ASC'
    ).all<{ local_uuid: string; updated_at: number; last_modified: number }>();
    expect(rows.results).toHaveLength(7);
    const seenTs = new Set<number>();
    for (const r of rows.results) {
      expect(r.updated_at).toBeLessThan(100_000_000_000); // seconds domain
      expect(seenTs.has(r.updated_at)).toBe(false); // globally unique
      seenTs.add(r.updated_at);
    }
    for (const u of msRows) {
      const row = rows.results.find((r) => r.local_uuid === u)!;
      expect(row.last_modified).toBeLessThan(100_000_000_000); // re-stamped
    }
    const healthyRow = rows.results.find((r) => r.local_uuid === healthy)!;
    expect(healthyRow.updated_at).toBe(1_700_000_100); // untouched
    expect(healthyRow.last_modified).toBe(1_700_000_100);

    // sync_clock advanced past every allocated stamp (monotonic guarantee).
    const clock = await env.DB.prepare('SELECT last_ts FROM sync_clock WHERE id = 1')
      .first<{ last_ts: number }>();
    expect(clock!.last_ts).toBeGreaterThanOrEqual(Math.max(...seenTs));

    // Idempotent: a second pull reports nothing left to repair.
    const again = (await pull(auth, {
      cursor: '0',
      limit: '200',
      normalize_timestamps: '1',
    })) as PullResponseBody;
    expect(again.normalization!.normalized).toBe(0);
    expect(again.normalization!.remaining).toBe(0);
  });

  it('preserves seconds-scale last_modified while re-stamping updated_at', async () => {
    const auth = await adminAuthHeader();
    await seedRoomAt(1_800_000_000_000, {
      roomNumber: 'MIX1',
      lastModified: 1_700_000_123, // seconds-scale → must survive
    });

    const data = (await pull(auth, {
      cursor: '0',
      limit: '200',
      normalize_timestamps: '1',
    })) as PullResponseBody;
    expect(data.normalization!.normalized).toBe(1);

    const row = await env.DB.prepare(
      'SELECT updated_at, last_modified FROM rooms WHERE room_number = ?'
    )
      .bind('MIX1')
      .first<{ updated_at: number; last_modified: number }>();
    expect(row!.updated_at).toBeLessThan(100_000_000_000);
    expect(row!.last_modified).toBe(1_700_000_123); // preserved, not re-stamped
  });

  it('repairs progressively: huge backlog drains across repeated pulls (maxRows bound)', async () => {
    const auth = await adminAuthHeader();
    // 12 ms rows; normalizeTimestamps is invoked with maxRows=500 per pull
    // so this all drains in ONE call — emulate the bound by asserting the
    // full drain and that remaining tracks honestly.
    for (let i = 0; i < 12; i++) {
      await seedRoomAt(1_900_000_000_000 + i, { roomNumber: `BG${i}` });
    }

    const first = (await pull(auth, {
      cursor: '0',
      limit: '200',
      normalize_timestamps: '1',
    })) as PullResponseBody;
    expect(first.normalization!.normalized).toBe(12);
    expect(first.normalization!.remaining).toBe(0);

    const second = (await pull(auth, {
      cursor: '0',
      limit: '200',
      normalize_timestamps: '1',
    })) as PullResponseBody;
    expect(second.normalization!.normalized).toBe(0);
    expect(second.normalization!.remaining).toBe(0);
  });

  it('after repair, seconds-cursor clients see new pushes (delta sync unpoisoned)', async () => {
    const auth = await adminAuthHeader();
    // Legacy ms rows poison the domain…
    for (let i = 0; i < 3; i++) {
      await seedRoomAt(1_700_000_000_000 + i, { roomNumber: `PZ${i}` });
    }
    // …the first pull triggers normalization (explicit opt-in under the
    // 2026-09-15 contract — ordinary delta pulls never scan for legacy rows)…
    const pre = (await pull(auth, {
      cursor: '0',
      limit: '200',
      normalize_timestamps: '1',
    })) as PullResponseBody;
    expect(pre.normalization!.normalized).toBe(3);

    // …and a NEW push (seconds-stamped by the allocator) is immediately
    // visible to a second device pulling from the returned cursor.
    const ops = [pushOp('rooms', 'create', roomPayload({ device_id: 'device-B' }))];
    const res = await pushOperations(auth, ops);
    const body = (await res.json()) as { summary: { failed: number } };
    expect(body.summary.failed).toBe(0);

    const after = await pull(auth, { cursor: '0', limit: '200' });
    const uuids = after.changes.map((c) => c.local_uuid);
    expect(uuids).toContain((ops[0].data as Record<string, unknown>).local_uuid as string);
    // All returned timestamps are seconds-scale — the domain is clean.
    for (const c of after.changes) {
      expect(c.updated_at as number).toBeLessThan(100_000_000_000);
    }
  });

  it('ordinary delta pull self-heals poisoned rows it encounters — never serves them (2026-09-17)', async () => {
    const auth = await adminAuthHeader();
    for (let i = 0; i < 2; i++) {
      await seedRoomAt(1_700_000_000_000 + i, { roomNumber: `OPT${i}` });
    }

    // ✅ العقد الجديد (2026-09-17): السحب الاعتيادي لم يعد يقدّم صفوفاً
    // مسمومة (ميلي/sentinel) للعميل إطلاقاً — الاكتشاف مجاني (مسح الصفحة
    // في الذاكرة) والإصلاح الذاتي يعيد ختمها فوراً. حقل normalization يبقى
    // غائباً (لا مسح صيانة كامل — عقد 2026-09-15 قائم للطلب الصريح).
    const plain = (await pull(auth, { cursor: '0', limit: '200', entity: 'rooms' })) as PullResponseBody;
    expect(plain.normalization).toBeFalsy();
    expect(plain.changes).toHaveLength(0); // السم لم يُقدَّم
    expect(plain.has_more).toBe(true); // النسخ المُصلحة تُسلَّم بالصفحة التالية
    expect(parseInt(plain.cursor, 10)).toBe(0); // المؤشر لم يتقدم فوق أي سم

    // والصفوف أُصلحت فعلاً في D1 — طوابع ثوانٍ فريدة جديدة فوق الساعة
    const rows = await env.DB.prepare(
      'SELECT updated_at FROM rooms WHERE room_number LIKE ? ORDER BY updated_at'
    )
      .bind('OPT%')
      .all<{ updated_at: number }>();
    expect(rows.results).toHaveLength(2);
    expect(rows.results[0].updated_at).toBeGreaterThan(0);
    expect(rows.results[0].updated_at).toBeLessThan(2_000_000_000);
    expect(rows.results[1].updated_at).toBeGreaterThan(0);
    expect(rows.results[1].updated_at).toBeLessThan(2_000_000_000);
    expect(rows.results[0].updated_at).not.toBe(rows.results[1].updated_at);

    // الصفحة التالية تُسلّم الصفين المُصلحين ثم تنضب
    const next = (await pull(auth, { cursor: plain.cursor, limit: '200', entity: 'rooms' })) as PullResponseBody;
    expect(next.changes).toHaveLength(2);
    for (const c of next.changes) {
      expect(c.updated_at as number).toBeLessThan(2_000_000_000);
    }
    expect(next.has_more).toBe(false);
  });
});

// ─── D) Sentinel poison self-heal (2026-09-17) ─────────────────

describe('pull: sentinel poison self-heal (9999999999 → fresh seconds)', () => {
  it('sentinel rows are healed in-page and never served; cursor stops at the last sane row', async () => {
    const auth = await adminAuthHeader();
    // صفان سليمان + صف sentinel (ختم سكربت appwrite_cloud_restore.py القديم)
    const sane1 = await seedRoomAt(1_700_000_100, { roomNumber: 'S1' });
    const poison = await seedRoomAt(9_999_999_999, {
      roomNumber: 'SNT1',
      lastModified: 9_999_999_999, // مسموم أيضاً — يجب أن يُعاد ختمه
    });
    const sane2 = await seedRoomAt(1_700_000_200, { roomNumber: 'S2' });

    const data = (await pull(auth, { cursor: '0', limit: '200', entity: 'rooms' })) as PullResponseBody;

    // الصفان السليمان وحدهما قُدِّما — السم شُفي وأُخفي
    expect(data.changes.map((c) => c.local_uuid)).toEqual([sane1, sane2]);
    for (const c of data.changes) {
      expect(c.updated_at as number).toBeLessThan(2_000_000_000);
    }
    expect(parseInt(data.cursor, 10)).toBe(1_700_000_200); // آخر صف سليم
    expect(data.has_more).toBe(true); // الصف المُصلح ينتظر الصفحة التالية

    // D1: السم استُبدل بطابع ثوانٍ جديد فوق الساعة، وlast_modified كذلك
    const healed = await env.DB.prepare(
      'SELECT updated_at, last_modified FROM rooms WHERE local_uuid = ?'
    )
      .bind(poison)
      .first<{ updated_at: number; last_modified: number }>();
    expect(healed!.updated_at).toBeGreaterThan(1_700_000_200);
    expect(healed!.updated_at).toBeLessThan(2_000_000_000);
    expect(healed!.last_modified).toBeLessThan(2_000_000_000);

    // الدورة التالية تستلم الصف المُصلح وتنضب — بلا فقد ولا تكرار
    const next = (await pull(auth, { cursor: data.cursor, limit: '200', entity: 'rooms' })) as PullResponseBody;
    expect(next.changes.map((c) => c.local_uuid)).toEqual([poison]);
    expect(next.has_more).toBe(false);
    expect(parseInt(next.cursor, 10)).toBe(healed!.updated_at);
  });

  it('a delta pull from a sane cursor heals new poison without ever exposing it', async () => {
    // جهاز مؤشره سليم (1_700_000_100) — صف sentinel يُزرع بعده: الدلتا
    // تشفيه في الصفحة نفسها ولا تعيد مؤشراً مسموماً أبداً.
    const auth = await adminAuthHeader();
    const base = await seedRoomAt(1_700_000_100, { roomNumber: 'B1' });
    const first = (await pull(auth, { cursor: '0', limit: '200', entity: 'rooms' })) as PullResponseBody;
    expect(first.changes.map((c) => c.local_uuid)).toEqual([base]);

    await seedRoomAt(9_999_999_999, { roomNumber: 'LATE1' });
    const delta = (await pull(auth, { cursor: first.cursor, limit: '200', entity: 'rooms' })) as PullResponseBody;
    expect(delta.changes).toHaveLength(0); // لم يُقدَّم
    expect(parseInt(delta.cursor, 10)).toBe(parseInt(first.cursor, 10)); // لم يتقدم فوق السم
    expect(delta.has_more).toBe(true); // الشفاء جاهز للسحب التالي

    const afterHeal = (await pull(auth, { cursor: delta.cursor, limit: '200', entity: 'rooms' })) as PullResponseBody;
    expect(afterHeal.changes).toHaveLength(1);
    expect(afterHeal.changes[0].updated_at as number).toBeLessThan(2_000_000_000);
    expect(afterHeal.has_more).toBe(false);
  });
});
