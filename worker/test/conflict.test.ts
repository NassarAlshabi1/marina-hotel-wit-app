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

describe('conflict: delete-vs-update contract (F1 2026-09-22)', () => {
  it('delete → edit → push: edit rejected with status:"deleted", row stays deleted, conflict recorded', async () => {
    const auth = await adminAuthHeader();
    const p = await createRoom(auth);
    const del = await pushOperations(auth, [
      pushOp('rooms', 'delete', { local_uuid: p.local_uuid }),
    ]);
    expect(((await del.json()) as PushResponseBody).summary.success).toBe(1);
    const tomb = await serverRow(p.local_uuid as string);

    // Scenario: another device pushes an edit made before the deletion
    // arrived. The contract: DELETION WINS — deterministically, visibly.
    const editOp = pushOp('rooms', 'update', { ...p, price: 210 }, {
      vectorClock: '{"device-B":3}',
      updatedAt: (tomb.updated_at as number) + 10,
    });
    const res = await pushOperations(auth, [editOp]);
    const body = (await res.json()) as PushResponseBody;
    // success:true (the loss is FINAL — the client must not retry) but
    // flagged status:"deleted" so the client reconciles consciously.
    expect(body.summary.success).toBe(1);
    expect(body.results[0]?.status).toBe('deleted');

    // No zombie row: content unchanged, tombstone intact, no re-stamp.
    const row = await serverRow(p.local_uuid as string);
    expect(row.price).toBe(100.5);
    expect(row.deleted_at).not.toBeNull();
    expect(row.updated_at).toBe(tomb.updated_at);

    // The loss is visible in the audit trail — exactly once, tagged.
    const conflicts = await env.DB.prepare(
      "SELECT resolution FROM sync_conflicts WHERE entity_id = ? AND resolution = 'edit_on_deleted'"
    )
      .bind(p.local_uuid)
      .all<{ resolution: string }>();
    expect(conflicts.results.length).toBe(1);

    // Idempotent replay with the same key short-circuits (no re-processing,
    // no duplicate conflict row).
    const replay = await pushOperations(auth, [editOp]);
    const replayBody = (await replay.json()) as PushResponseBody;
    expect(replayBody.summary.success).toBe(1);
    expect(replayBody.results[0]?.skipped).toBe(true);
    const conflictsAfterReplay = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM sync_conflicts WHERE entity_id = ? AND resolution = 'edit_on_deleted'"
    )
      .bind(p.local_uuid)
      .first<{ c: number }>();
    expect(conflictsAfterReplay?.c).toBe(1);
  });
});

describe('conflict: clock-skew-tolerant LWW (F2 2026-09-22)', () => {
  it('slow-clock within skew window: earlier timestamp + higher version → applied', async () => {
    const auth = await adminAuthHeader();
    const p = await createRoom(auth);
    const server = await serverRow(p.local_uuid as string);

    // Device B's clock trails the server by 30s (inside the ±90s window):
    // the raw timestamp would lose, but its higher version proves the edit
    // is genuinely newer — the version must decide, not the skewed clock.
    const res = await pushOperations(auth, [
      pushOp('rooms', 'update', { ...p, price: 888, version: 9 }, {
        vectorClock: '{"device-B":1}',
        updatedAt: (server.updated_at as number) - 30,
      }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);
    const row = await serverRow(p.local_uuid as string);
    expect(row.price).toBe(888);
  });

  it('slow-clock within window but equal version → server copy survives', async () => {
    const auth = await adminAuthHeader();
    const p = await createRoom(auth);
    const server = await serverRow(p.local_uuid as string);

    const res = await pushOperations(auth, [
      pushOp('rooms', 'update', { ...p, price: 444 }, {
        vectorClock: '{"device-B":1}',
        updatedAt: (server.updated_at as number) - 30, // inside window
        // version stays 1 (payload default) — no proof of a later edit
      }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);
    const row = await serverRow(p.local_uuid as string);
    expect(row.price).toBe(100.5); // rejected — version did not win
  });

  it('fast-clock clamp: op stamped beyond serverNow+allowance is clamped — cannot beat a future-stamped row', async () => {
    const auth = await adminAuthHeader();
    const p = await createRoom(auth);
    // Simulate a future-stamped row from the old un-clamped era (+1h).
    const nowSec = Math.floor(Date.now() / 1000);
    await env.DB.prepare('UPDATE rooms SET updated_at = ? WHERE local_uuid = ?')
      .bind(nowSec + 3600, p.local_uuid)
      .run();

    // The fast clock races further into the future (+1h+10s). Without the
    // clamp min(clientTs, serverNow+90) this would win and stamp the
    // future again — the clamp bounds the arms race and it loses.
    const res = await pushOperations(auth, [
      pushOp('rooms', 'update', { ...p, price: 555 }, {
        vectorClock: '{"device-B":1}',
        updatedAt: nowSec + 3600 + 10,
      }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);
    const row = await serverRow(p.local_uuid as string);
    expect(row.price).toBe(100.5); // clamped timestamp lost
    expect(row.updated_at).toBe(nowSec + 3600); // future stamp untouched
  });
});
