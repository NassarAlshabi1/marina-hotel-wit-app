// ═══════════════════════════════════════════════════════════════
//  conflict.test.ts — plan task 1.5 + 2.4
//  Vector-clock classification (equal / local_newer / remote_newer /
//  concurrent), LWW by op timestamp, version tie-break on equal
//  timestamps (slow-clock device), sync_conflicts audit trail.
//
//  All op timestamps are derived from the SERVER row's updated_at
//  (the sync_clock allocator) — never hard-coded — so the LWW
//  relations hold regardless of the real wall clock.
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  adminAuthHeader,
  pushOp,
  pushOperations,
  roomPayload,
  resetDb,
  type PushResponseBody,
} from './helpers';

beforeEach(async () => {
  await resetDb();
});

async function serverRow(localUuid: string): Promise<Record<string, unknown>> {
  const row = await env.DB.prepare('SELECT * FROM rooms WHERE local_uuid = ?')
    .bind(localUuid)
    .first<Record<string, unknown>>();
  expect(row).not.toBeNull();
  return row!;
}

async function createRoom(auth: string, overrides: Record<string, unknown> = {}) {
  const payload = roomPayload(overrides);
  const res = await pushOperations(auth, [pushOp('rooms', 'create', payload)]);
  const body = (await res.json()) as PushResponseBody;
  expect(body.summary.success).toBe(1);
  return payload;
}

describe('conflict: vector clock classification', () => {
  it('equal clocks + later op timestamp → apply (plain forward update)', async () => {
    const auth = await adminAuthHeader();
    const p = await createRoom(auth, { version: 1 });
    const server = await serverRow(p.local_uuid as string);

    const res = await pushOperations(auth, [
      pushOp('rooms', 'update', { ...p, price: 300 }, {
        vectorClock: '{}',
        updatedAt: (server.updated_at as number) + 10, // later than server
      }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);
    const row = await serverRow(p.local_uuid as string);
    expect(row.price).toBe(300);
    expect(row.version).toBe(2);
  });

  it('concurrent clocks + later timestamp → conflict recorded, incoming applies', async () => {
    const auth = await adminAuthHeader();
    const p = await createRoom(auth, { vector_clock: '{"device-A":3}' });
    const server = await serverRow(p.local_uuid as string);

    // Server row VC {A:3}; incoming VC {B:2} → concurrent.
    // Incoming op timestamp LATER than server's → incoming applies.
    const later = await pushOperations(auth, [
      pushOp('rooms', 'update', { ...p, price: 400 }, {
        vectorClock: '{"device-B":2}',
        updatedAt: (server.updated_at as number) + 10,
      }),
    ]);
    const laterBody = (await later.json()) as PushResponseBody;
    expect(laterBody.summary.success).toBe(1);
    const row = await serverRow(p.local_uuid as string);
    expect(row.price).toBe(400);
    // Clocks merged — both devices visible
    const merged = JSON.parse(row.vector_clock as string) as Record<string, number>;
    expect(merged['device-A']).toBe(3);
    expect(merged['device-B']).toBe(2);

    // Conflict row written to the audit trail
    const conflicts = await env.DB.prepare(
      'SELECT entity, entity_id, resolution FROM sync_conflicts WHERE entity_id = ?'
    )
      .bind(p.local_uuid)
      .all<{ entity: string; entity_id: string; resolution: string }>();
    expect(conflicts.results.length).toBeGreaterThanOrEqual(1);
    expect(conflicts.results[0]?.resolution).toBe('last_write_wins');
  });

  it('concurrent + earlier timestamp → server copy wins, incoming rejected', async () => {
    const auth = await adminAuthHeader();
    const p = await createRoom(auth, { vector_clock: '{"device-A":1}' });
    const server = await serverRow(p.local_uuid as string);

    const res = await pushOperations(auth, [
      pushOp('rooms', 'update', { ...p, price: 111 }, {
        vectorClock: '{"device-B":1}',
        updatedAt: (server.updated_at as number) - 100, // strictly earlier
      }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    // Rejected op still returns success:true with the surviving record —
    // the sync contract returns the surviving record either way.
    expect(body.summary.success).toBe(1);

    const row = await serverRow(p.local_uuid as string);
    expect(row.price).toBe(100.5); // unchanged — server copy survived
    expect(row.updated_at).toBe(server.updated_at);
  });
});

describe('conflict: equal-timestamp version tie-break (plan 2.4)', () => {
  it('slow-clock device with equal timestamp but HIGHER version wins the tie', async () => {
    const auth = await adminAuthHeader();
    // Server row: version 2 after one applied update
    const p = await createRoom(auth, { vector_clock: '{"device-A":1}' });
    const s1 = await serverRow(p.local_uuid as string);
    await pushOperations(auth, [
      pushOp('rooms', 'update', { ...p, note: 'bump' }, {
        vectorClock: '{"device-A":2}',
        updatedAt: (s1.updated_at as number) + 10,
      }),
    ]);
    const server = await serverRow(p.local_uuid as string);
    expect(server.version).toBe(2);

    // Device B has a slow clock: its wall-clock EQUALS the server's
    // updated_at exactly, but it carries version 3 (a genuine later edit).
    const res = await pushOperations(auth, [
      pushOp('rooms', 'update', { ...p, price: 777, version: 3 }, {
        vectorClock: '{"device-B":1}',
        updatedAt: server.updated_at, // tie
      }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);

    const row = await serverRow(p.local_uuid as string);
    expect(row.price).toBe(777); // incoming applied — version broke the tie
    expect(row.version).toBe(3); // server-stamped version = old + 1
  });

  it('equal timestamp + equal-or-lower version → server copy wins (old behavior preserved)', async () => {
    const auth = await adminAuthHeader();
    const p = await createRoom(auth);
    const server = await serverRow(p.local_uuid as string);

    for (const incomingVersion of [server.version as number, (server.version as number) - 1]) {
      const res = await pushOperations(auth, [
        pushOp('rooms', 'update', { ...p, price: 999, version: incomingVersion }, {
          vectorClock: '{"device-B":5}',
          updatedAt: server.updated_at, // tie
        }),
      ]);
      const body = (await res.json()) as PushResponseBody;
      expect(body.summary.success).toBe(1);
      const row = await serverRow(p.local_uuid as string);
      expect(row.price).toBe(100.5); // rejected every time
    }
  });

  it('missing version on a tie → rejected (old clients keep server copy)', async () => {
    const auth = await adminAuthHeader();
    const p = await createRoom(auth);
    const server = await serverRow(p.local_uuid as string);
    const data = { ...p, price: 555 } as Record<string, unknown>;
    delete data.version; // legacy client sends no version
    await pushOperations(auth, [
      pushOp('rooms', 'update', data, {
        vectorClock: '{"device-B":9}',
        updatedAt: server.updated_at,
      }),
    ]);
    const row = await serverRow(p.local_uuid as string);
    expect(row.price).toBe(100.5);
  });

  it('strictly-earlier timestamp loses even with a higher version (time still dominates)', async () => {
    const auth = await adminAuthHeader();
    const p = await createRoom(auth);
    const server = await serverRow(p.local_uuid as string);
    await pushOperations(auth, [
      pushOp('rooms', 'update', { ...p, price: 123, version: 99 }, {
        vectorClock: '{"device-B":9}',
        updatedAt: (server.updated_at as number) - 1000, // earlier — time dominates version
      }),
    ]);
    const row = await serverRow(p.local_uuid as string);
    expect(row.price).toBe(100.5);
  });
});

describe('conflict: server-dominates stale-clock edits (P0 regression guard)', () => {
  it('local_newer + earlier timestamp → rejected, fields do not regress', async () => {
    const auth = await adminAuthHeader();
    const p = await createRoom(auth, { vector_clock: '{"device-A":2}' });
    const s1 = await serverRow(p.local_uuid as string);
    // Bump server row forward (VC {A:3} now dominates the client's {A:2})
    await pushOperations(auth, [
      pushOp('rooms', 'update', { ...p, price: 500 }, {
        vectorClock: '{"device-A":3}',
        updatedAt: (s1.updated_at as number) + 10,
      }),
    ]);

    // Client edits against stale data: VC {A:2} (dominated) + older ts
    const res = await pushOperations(auth, [
      pushOp('rooms', 'update', { ...p, price: 10, status: 'hack' }, {
        vectorClock: '{"device-A":2}',
        updatedAt: (s1.updated_at as number) - 100,
      }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);

    const row = await serverRow(p.local_uuid as string);
    expect(row.price).toBe(500); // server value preserved
    expect(row.status).toBe('available');
  });
});

describe('conflict: update of tombstoned record', () => {
  it('updating a soft-deleted record with a later edit applies (documented behavior)', async () => {
    const auth = await adminAuthHeader();
    const p = await createRoom(auth);
    await pushOperations(auth, [pushOp('rooms', 'delete', { local_uuid: p.local_uuid })]);
    const tomb = await serverRow(p.local_uuid as string);

    const res = await pushOperations(auth, [
      pushOp('rooms', 'update', { ...p, price: 210 }, {
        vectorClock: '{"device-B":3}',
        updatedAt: (tomb.updated_at as number) + 10,
      }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);
    const row = await serverRow(p.local_uuid as string);
    expect(row.price).toBe(210);
  });
});
