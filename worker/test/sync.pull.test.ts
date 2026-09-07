// ═══════════════════════════════════════════════════════════════
//  sync.pull.test.ts — plan task 1.4 (+ 2.5 echo filter)
//  Cursor semantics, pagination, limit clamping, unknown entity,
//  echo filter (exclude_device), monotonic cursor guarantee.
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { resetDb, adminAuthHeader, pull, pushOp, pushOperations, roomPayload, type PushResponseBody } from './helpers';

beforeEach(async () => {
  await resetDb();
});


async function seedRooms(count: number, device = 'device-A'): Promise<string[]> {
  const auth = await adminAuthHeader();
  const uuids: string[] = [];
  const ops = Array.from({ length: count }, () => {
    const p = roomPayload({ device_id: device });
    uuids.push(p.local_uuid as string);
    return pushOp('rooms', 'create', p);
  });
  // batches of 100
  for (let i = 0; i < ops.length; i += 100) {
    const res = await pushOperations(auth, ops.slice(i, i + 100));
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.failed).toBe(0);
  }
  return uuids;
}

describe('pull: pagination + cursor', () => {
  it('drains to exhaustion: pages until has_more=false, no dupes, monotonic cursor', async () => {
    const auth = await adminAuthHeader();
    await seedRooms(30);

    let cursor = '0';
    let total = 0;
    const seen = new Set<string>();
    let lastCursor = -1;
    for (let page = 0; page < 10; page++) {
      const data = await pull(auth, { cursor, limit: '7' });
      expect(data.changes.length).toBeLessThanOrEqual(7);
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
    expect(total).toBe(30);
    expect(seen.size).toBe(30);
  });

  it('cursor never skips records: every record between pages is returned', async () => {
    const auth = await adminAuthHeader();
    await seedRooms(25);
    const first = await pull(auth, { limit: '10' });
    expect(first.changes).toHaveLength(10);
    // resume from the returned cursor
    const second = await pull(auth, { cursor: first.cursor, limit: '10' });
    expect(second.changes).toHaveLength(10);
    const uuids1 = new Set(first.changes.map((c) => c.local_uuid));
    const uuids2 = new Set(second.changes.map((c) => c.local_uuid));
    for (const u of uuids2) expect(uuids1.has(u)).toBe(false);
    const third = await pull(auth, { cursor: second.cursor, limit: '10' });
    expect(third.changes).toHaveLength(5);
  });

  it('clamps limit to [1, 200] and defaults to 200', async () => {
    const auth = await adminAuthHeader();
    await seedRooms(5);
    const zero = await pull(auth, { limit: '0' }); // → clamped to 1
    expect(zero.changes).toHaveLength(1);
    const negative = await pull(auth, { limit: '-50' }); // → clamped to 1
    expect(negative.changes).toHaveLength(1);
    const huge = await pull(auth, { limit: '9999' }); // → clamped to 200
    expect(huge.changes).toHaveLength(5);
    const def = await pull(auth);
    expect(def.changes).toHaveLength(5);
  });

  it('rejects unknown entity before touching SQL (400)', async () => {
    const auth = await adminAuthHeader();
    const res = await fetchWithAuth('/api/sync/pull?entity=not_an_entity', auth);
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain('Unknown entity');
    // …and must NOT leak SQL details
    expect(JSON.stringify(body)).not.toContain('SELECT');
  });

  it('returns an empty page (not an error) when caught up', async () => {
    const auth = await adminAuthHeader();
    const data = await pull(auth, { cursor: '99999999999' });
    expect(data.changes).toEqual([]);
    expect(data.has_more).toBe(false);
    expect(data.cursor).toBe('99999999999'); // cursor preserved, not rewound
  });

  it('every pulled record carries _entity and server-sync fields', async () => {
    const auth = await adminAuthHeader();
    await seedRooms(2);
    const data = await pull(auth);
    for (const c of data.changes) {
      expect(c._entity).toBe('rooms');
      expect(typeof c.updated_at).toBe('number');
      expect(c.version).toBe(1);
      expect(c.local_uuid).toBeTruthy();
    }
  });
});

describe('pull: echo filter (plan 2.5 — exclude_device)', () => {
  it('excludes rows written by the requesting device, keeps everything else', async () => {
    const auth = await adminAuthHeader();
    await seedRooms(3, 'device-A');
    await seedRooms(2, 'device-B');

    const all = await pull(auth);
    expect(all.changes).toHaveLength(5);

    const withoutA = await pull(auth, { exclude_device: 'device-A' });
    expect(withoutA.changes).toHaveLength(2);
    for (const c of withoutA.changes) {
      expect(c.device_id).toBe('device-B');
    }
  });

  it('empty or missing exclude_device behaves like no filter', async () => {
    const auth = await adminAuthHeader();
    await seedRooms(3, 'device-A');
    const plain = await pull(auth);
    const empty = await pull(auth, { exclude_device: '' });
    expect(plain.changes).toHaveLength(empty.changes.length);
  });

  it('server-stamped rows (device_id "") are never excluded', async () => {
    const auth = await adminAuthHeader();
    await seedRooms(1, 'device-A');
    // Row created via API createRecord has device_id='device-A'; simulate a
    // server-originated row (device_id='') directly in D1:
    await env.DB.prepare(
      "UPDATE rooms SET device_id = '' WHERE local_uuid = (SELECT local_uuid FROM rooms LIMIT 1)"
    ).run();
    const filtered = await pull(auth, { exclude_device: 'device-A' });
    expect(filtered.changes).toHaveLength(1);
  });
});

describe('pull: sync_log + stats + conflicts endpoints', () => {
  it('/api/sync/log returns recorded operations with pagination', async () => {
    const auth = await adminAuthHeader();
    await seedRooms(3);
    const res = await fetchWithAuth('/api/sync/log?limit=2&offset=0', auth);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { logs: unknown[]; limit: number; offset: number };
    expect(body.logs).toHaveLength(2);
    expect(body.limit).toBe(2);
  });

  it('/api/stats returns a count for every entity table incl. the 3 new ones', async () => {
    const auth = await adminAuthHeader();
    await seedRooms(2);
    const res = await fetchWithAuth('/api/stats', auth);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { tables: Record<string, number> };
    expect(body.tables.rooms).toBe(2);
    // D7 gap closure: new tables are exposed
    expect(body.tables.inventory_items).toBe(0);
    expect(body.tables.inventory_transactions).toBe(0);
    expect(body.tables.blacklist).toBe(0);
    // D8: hotel_day_ledger removed from the entity mapping
    expect(body.tables.hotel_day_ledger).toBeUndefined();
  });

  it('/api/sync/conflicts starts empty and stays queryable', async () => {
    const auth = await adminAuthHeader();
    const res = await fetchWithAuth('/api/sync/conflicts', auth);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { conflicts: unknown[] };
    expect(body.conflicts).toEqual([]);
  });
});

async function fetchWithAuth(path: string, auth: string): Promise<Response> {
  const { SELF } = await import('cloudflare:test');
  return SELF.fetch(`https://example.com${path}`, { headers: { Authorization: auth } });
}
