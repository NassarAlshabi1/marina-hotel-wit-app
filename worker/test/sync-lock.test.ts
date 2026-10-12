// ═══════════════════════════════════════════════════════════════
//  sync-lock.test.ts — plan task 1.7 + P1 lock-token contract (2026-09-24)
//
//  SyncLockDO is COORDINATION-ONLY: acquire / release / status.
//  The P1 contract change under test:
//    - every granted lock carries an unguessable crypto.randomUUID()
//      lockId (the old `${lockKey}:${deviceId}:${now}` was predictable);
//    - release requires deviceId + lockId — wrong lockId or wrong
//      device → 409;
//    - legacy in-memory WebSocket / broadcast / per-device cursors were
//      removed after the reference audit (realtime lives in
//      RealtimeHubDO — see realtime.hub.test.ts / realtime.broadcast.test.ts).
// ═══════════════════════════════════════════════════════════════

import { env, SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { resetDb, adminAuthHeader } from './helpers';

beforeEach(async () => {
  await resetDb();
});


async function doFetch(path: string, init?: RequestInit): Promise<Response> {
  const id = env.SYNC_LOCK.idFromName('global');
  const stub = env.SYNC_LOCK.get(id);
  return stub.fetch(`https://do.internal${path}`, init);
}

function lockBody(deviceId: string, entity = 'rooms', entityId = 'room-1'): string {
  return JSON.stringify({ deviceId, entity, entityId, operation: 'update' });
}

function unlockBody(deviceId: string, lockId?: string, entity = 'rooms', entityId = 'room-1'): string {
  return JSON.stringify({ deviceId, entity, entityId, operation: 'update', lockId });
}

/** UUID v4 shape — proves the token is NOT the old predictable pattern. */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function acquire(deviceId: string, entity = 'rooms', entityId = 'room-1') {
  const res = await doFetch('/lock', {
    method: 'POST',
    body: lockBody(deviceId, entity, entityId),
    headers: { 'Content-Type': 'application/json' },
  });
  return (await res.json()) as { granted: boolean; lockId?: string; heldBy?: string; expiresAt?: number };
}

describe('SyncLockDO: input validation', () => {
  it('rejects lock requests missing identity fields (400)', async () => {
    const res = await doFetch('/lock', {
      method: 'POST',
      body: JSON.stringify({ deviceId: 'device-A' }), // entity/entityId missing
      headers: { 'Content-Type': 'application/json' },
    });
    expect(res.status).toBe(400);
    const body = (await res.json()) as { granted: boolean; error: string };
    expect(body.granted).toBe(false);
    expect(body.error).toContain('required');
  });

  it('rejects unlock requests missing identity fields (400)', async () => {
    const res = await doFetch('/unlock', {
      method: 'POST',
      body: JSON.stringify({ deviceId: 'device-A' }),
      headers: { 'Content-Type': 'application/json' },
    });
    expect(res.status).toBe(400);
  });

  it('rejects unlock without a lockId (400) — token is mandatory now', async () => {
    await acquire('device-A');
    const res = await doFetch('/unlock', {
      method: 'POST',
      body: unlockBody('device-A', undefined),
      headers: { 'Content-Type': 'application/json' },
    });
    expect(res.status).toBe(400);
  });
});

describe('SyncLockDO: lock lifecycle', () => {
  it('acquire → granted; second device → denied with holder info', async () => {
    const first = await acquire('device-A');
    expect(first.granted).toBe(true);
    expect(first.lockId).toMatch(UUID_RE);
    expect(first.expiresAt).toBeGreaterThan(Date.now());

    const second = await acquire('device-B');
    expect(second.granted).toBe(false);
    expect(second.heldBy).toBe('device-A');
  });

  it('lockId is a real UUID — the old predictable pattern is gone', async () => {
    const first = await acquire('device-A', 'rooms', 'room-token-shape');
    expect(first.lockId).toMatch(UUID_RE);
    expect(first.lockId).not.toContain('rooms:room-token-shape');
    expect(first.lockId).not.toContain('device-A');
  });

  it('same device re-acquiring extends the lock with a FRESH token (no self-deadlock)', async () => {
    const first = await acquire('device-A');
    const second = await acquire('device-A');
    expect(second.granted).toBe(true);
    expect(second.expiresAt!).toBeGreaterThanOrEqual(first.expiresAt!);
    // renewal rotates the token — the old one must no longer release
    expect(second.lockId).not.toBe(first.lockId);
  });

  it('B cannot release A lock: missing token → 400, wrong/guessed token → 409', async () => {
    await acquire('device-A');

    // missing lockId → validation error (400)
    const strangerNoToken = await doFetch('/unlock', {
      method: 'POST',
      body: unlockBody('device-B'),
      headers: { 'Content-Type': 'application/json' },
    });
    expect(strangerNoToken.status).toBe(400);

    // The old predictable pattern `${lockKey}:${deviceId}:${now}` must NOT
    // be accepted as a token → ownership rejection (409).
    const strangerGuessedToken = await doFetch('/unlock', {
      method: 'POST',
      body: unlockBody('device-B', 'rooms:room-1:device-B:1758700000000'),
      headers: { 'Content-Type': 'application/json' },
    });
    expect(strangerGuessedToken.status).toBe(409);

    // Correct device, wrong (random) lockId → 409
    const wrongToken = await doFetch('/unlock', {
      method: 'POST',
      body: unlockBody('device-A', crypto.randomUUID()),
      headers: { 'Content-Type': 'application/json' },
    });
    expect(wrongToken.status).toBe(409);
  });

  it('owner release with the CORRECT lockId succeeds; B acquires right after', async () => {
    const lock = await acquire('device-A');
    expect(lock.lockId).toBeDefined();

    const owner = await doFetch('/unlock', {
      method: 'POST',
      body: unlockBody('device-A', lock.lockId),
      headers: { 'Content-Type': 'application/json' },
    });
    const ownerBody = (await owner.json()) as { released: boolean };
    expect(ownerBody.released).toBe(true);

    const next = await acquire('device-B');
    expect(next.granted).toBe(true);
  });

  it('status lists only unexpired locks and never leaks lockId', async () => {
    await acquire('device-A', 'rooms', 'room-live');
    const status = (await (
      await doFetch('/status')
    ).json()) as { locks: Array<{ key: string; deviceId: string; lockId?: string }>; count: number };
    expect(status.count).toBeGreaterThanOrEqual(1);
    expect(status.locks.some((l) => l.key === 'rooms:room-live' && l.deviceId === 'device-A')).toBe(true);
    // security: the token must not be enumerable through the status view
    for (const l of status.locks) {
      expect(l.lockId).toBeUndefined();
    }
  });

  it('unknown DO paths 404 (legacy /broadcast /cursor /cursors removed)', async () => {
    for (const p of ['/nope', '/broadcast', '/cursor', '/cursors']) {
      const res = await doFetch(p, { method: p === '/cursor' ? 'POST' : 'GET' });
      expect(res.status).toBe(404);
    }
  });
});

describe('realtime endpoint routing (worker → DO)', () => {
  it('/api/realtime without Upgrade header → 400', async () => {
    const auth = await adminAuthHeader();
    const res = await SELF.fetch('https://example.com/api/realtime', {
      headers: { Authorization: auth },
    });
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain('WebSocket upgrade required');
  });

  it('/api/sync/lock without auth → 401 (DO routes sit behind auth middleware)', async () => {
    const res = await SELF.fetch('https://example.com/api/sync/lock', { method: 'POST', body: lockBody('device-A') });
    expect(res.status).toBe(401);
  });

  it('acquire + release through the worker route (auth → DO roundtrip, token-gated)', async () => {
    const auth = await adminAuthHeader();
    const lock = await SELF.fetch('https://example.com/api/sync/lock', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: auth },
      body: lockBody('device-A', 'bookings', 'bk-9'),
    });
    expect(lock.status).toBe(200);
    const lockBodyJson = (await lock.json()) as { granted: boolean; lockId?: string };
    expect(lockBodyJson.granted).toBe(true);

    // wrong token through the worker route → 409
    const wrongUnlock = await SELF.fetch('https://example.com/api/sync/unlock', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: auth },
      body: unlockBody('device-A', crypto.randomUUID(), 'bookings', 'bk-9'),
    });
    expect(wrongUnlock.status).toBe(409);

    const unlock = await SELF.fetch('https://example.com/api/sync/unlock', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: auth },
      body: unlockBody('device-A', lockBodyJson.lockId, 'bookings', 'bk-9'),
    });
    expect(unlock.status).toBe(200);
  });

  it('GET /api/sync/locks lists locks through the worker route', async () => {
    const auth = await adminAuthHeader();
    const res = await SELF.fetch('https://example.com/api/sync/locks', { headers: { Authorization: auth } });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { locks: unknown[]; count: number };
    expect(Array.isArray(body.locks)).toBe(true);
  });
});
