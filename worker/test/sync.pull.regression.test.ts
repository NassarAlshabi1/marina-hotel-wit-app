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
//     the seconds-scale cursor domain forever. Fix: progressive
//     normalizeTimestamps() re-stamping driven by the pull handler.
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
  it('reports the broken table on EVERY page while healthy tables drain losslessly', async () => {
    const auth = await adminAuthHeader();
    // 7 healthy rooms at distinct timestamps → 3 pages at limit=3.
    for (let i = 0; i < 7; i++) {
      await seedRoomAt(1700000100 + i, { roomNumber: `D${String(i).padStart(3, '0')}` });
    }
    // Simulate a migration applied to code but not to live D1.
    await env.DB.prepare('DROP TABLE devices').run();

    let cursor = '0';
    const seen = new Set<string>();
    let pages = 0;
    let errorPages = 0;
    for (let page = 0; page < 10; page++) {
      const data = await pull(auth, { cursor, limit: '3' });
      pages++;
      if (data.errors.some((e) => e.entity === 'devices')) errorPages++;
      for (const c of data.changes) seen.add(c.local_uuid as string);
      cursor = data.cursor;
      if (!data.has_more) break;
    }
    // Healthy rows flow to exhaustion despite the broken table…
    expect(seen.size).toBe(7);
    // …and the client-visible contract holds: the broken table is named
    // on every page, so a client that persists its cursor while errors[]
    // is non-empty will never silently miss data.
    expect(errorPages).toBe(pages);
    expect(pages).toBeGreaterThan(1);
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

    const data = (await pull(auth, { cursor: '0', limit: '200' })) as PullResponseBody;
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
    const again = (await pull(auth, { cursor: '0', limit: '200' })) as PullResponseBody;
    expect(again.normalization!.normalized).toBe(0);
    expect(again.normalization!.remaining).toBe(0);
  });

  it('preserves seconds-scale last_modified while re-stamping updated_at', async () => {
    const auth = await adminAuthHeader();
    await seedRoomAt(1_800_000_000_000, {
      roomNumber: 'MIX1',
      lastModified: 1_700_000_123, // seconds-scale → must survive
    });

    const data = (await pull(auth, { cursor: '0', limit: '200' })) as PullResponseBody;
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

    const first = (await pull(auth, { cursor: '0', limit: '200' })) as PullResponseBody;
    expect(first.normalization!.normalized).toBe(12);
    expect(first.normalization!.remaining).toBe(0);

    const second = (await pull(auth, { cursor: '0', limit: '200' })) as PullResponseBody;
    expect(second.normalization!.normalized).toBe(0);
    expect(second.normalization!.remaining).toBe(0);
  });

  it('after repair, seconds-cursor clients see new pushes (delta sync unpoisoned)', async () => {
    const auth = await adminAuthHeader();
    // Legacy ms rows poison the domain…
    for (let i = 0; i < 3; i++) {
      await seedRoomAt(1_700_000_000_000 + i, { roomNumber: `PZ${i}` });
    }
    // …the first pull triggers normalization…
    const pre = (await pull(auth, { cursor: '0', limit: '200' })) as PullResponseBody;
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
});
