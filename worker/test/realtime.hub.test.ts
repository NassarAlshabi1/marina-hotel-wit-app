// ═══════════════════════════════════════════════════════════════
//  realtime.hub.test.ts — RealtimeHubDO (Hibernation API) contract
//
//  Covers the dedicated realtime hub split out of SyncLockDO (2026-09-17):
//    1. Connect → welcome presence + /api/realtime/status enumerates
//       the hibernated session (deviceId + entity from attachment).
//    2. Entity-tagged fan-out — an `ent:<entity>` subscriber receives
//       only its entity; the wildcard (`*`) subscriber receives all.
//       (This is the regression guard for the sanitizeTag('*') bug:
//       the wildcard tag must survive sanitization verbatim.)
//    3. Close → session leaves the hub (status count drops).
//    4. Security — client-sent frames are never relayed to others.
//
//  Route-level push→broadcast E2E lives in realtime.broadcast.test.ts
//  (unchanged — it must pass against the new hub without edits).
//
//  NOTE: client-side sockets under vitest-pool-workers do NOT emit a
//  'close' event after .close() — never await close in these tests.
// ═══════════════════════════════════════════════════════════════

import { SELF, env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { adminAuthHeader, resetDb } from './helpers';

beforeEach(async () => {
  await resetDb();
});

interface BroadcastMessage {
  type: string;
  entity: string;
  entityId?: string;
  operation?: string;
  deviceId?: string;
  timestamp: number;
  data?: { action?: string; message?: string; activeConnections?: number };
}

interface HubStatus {
  connections: number;
  byEntity: Record<string, number>;
  deviceIds: string[];
  hibernation: boolean;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Open a realtime WebSocket through the real worker route. */
async function connectRealtime(
  deviceId: string,
  entity: string
): Promise<{ socket: WebSocket; received: BroadcastMessage[] }> {
  const auth = await adminAuthHeader();
  const res = await SELF.fetch(
    `https://example.com/api/realtime?deviceId=${encodeURIComponent(deviceId)}&entity=${encodeURIComponent(entity)}`,
    { headers: { Authorization: auth, Upgrade: 'websocket' } }
  );
  expect(res.status).toBe(101);
  const socket = res.webSocket!;
  const received: BroadcastMessage[] = [];
  socket.accept();
  socket.addEventListener('message', (event) => {
    try {
      received.push(JSON.parse(String(event.data)) as BroadcastMessage);
    } catch {
      // ignore malformed frames — not part of the contract under test
    }
  });
  // Welcome presence arrives on accept — wait so the hibernated session
  // is fully registered before assertions fire.
  await sleep(300);
  expect(received.some((m) => m.type === 'presence')).toBe(true);
  return { socket, received };
}

/** Route-level hub status (auth-protected). */
async function hubStatus(): Promise<HubStatus> {
  const auth = await adminAuthHeader();
  const res = await SELF.fetch('https://example.com/api/realtime/status', {
    headers: { Authorization: auth },
  });
  expect(res.status).toBe(200);
  return (await res.json()) as HubStatus;
}

/** Direct DO-level broadcast — bypasses push (no business data written). */
async function doBroadcast(entity: string, entityId: string): Promise<void> {
  const hubId = env.REALTIME_HUB.idFromName('global');
  const stub = env.REALTIME_HUB.get(hubId);
  await stub.fetch(
    new Request('https://do.internal/broadcast', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        type: 'change',
        entity,
        entityId,
        operation: 'update',
        deviceId: 'pusher-device',
        timestamp: Date.now(),
      }),
    })
  );
}

describe('RealtimeHubDO (hibernation hub)', () => {
  it('welcome presence on connect; status enumerates the hibernated session', { timeout: 30000 }, async () => {
    const { socket, received } = await connectRealtime('hub-dev-1', '*');

    const welcome = received.find(
      (m) => m.type === 'presence' && m.data?.message === 'Connected'
    );
    expect(welcome).toBeTruthy();
    expect(welcome!.deviceId).toBe('server');

    const status = await hubStatus();
    expect(status.hibernation).toBe(true);
    expect(status.connections).toBeGreaterThanOrEqual(1);
    expect(status.deviceIds).toContain('hub-dev-1');
    expect(status.byEntity['*']).toBeGreaterThanOrEqual(1);

    socket.close();
  });

  it('wildcard subscriber receives every entity broadcast', { timeout: 30000 }, async () => {
    const { socket, received } = await connectRealtime('wildcard-dev', '*');

    await doBroadcast('rooms', 'room-1');
    await doBroadcast('blacklist', 'bl-9');
    await sleep(800);

    const entities = received.filter((m) => m.type === 'change').map((m) => m.entity);
    expect(entities).toContain('rooms');
    expect(entities).toContain('blacklist');

    socket.close();
  });

  it('entity-tagged subscriber receives ONLY its entity (not others, not wildcard-only events)', { timeout: 30000 }, async () => {
    const { socket, received } = await connectRealtime('rooms-only-dev', 'rooms');

    await doBroadcast('rooms', 'room-2'); // must arrive
    await doBroadcast('blacklist', 'bl-1'); // must NOT arrive
    await sleep(800);

    const changes = received.filter((m) => m.type === 'change');
    expect(changes.map((m) => m.entity)).toEqual(['rooms']);

    socket.close();
  });

  it('close removes the session from hub status', { timeout: 30000 }, async () => {
    const before = await hubStatus();

    const { socket } = await connectRealtime('ephemeral-dev', '*');
    const during = await hubStatus();
    expect(during.connections).toBe(before.connections + 1);

    socket.close();
    await sleep(800);

    const after = await hubStatus();
    expect(after.connections).toBe(before.connections);
    expect(after.deviceIds).not.toContain('ephemeral-dev');
  });

  it('does not relay client-injected change messages', { timeout: 30000 }, async () => {
    const attacker = await connectRealtime('attacker-dev', '*');
    const victim = await connectRealtime('victim-dev', '*');

    attacker.socket.send(
      JSON.stringify({
        type: 'change',
        entity: 'rooms',
        entityId: 'forged-room',
        operation: 'update',
        deviceId: 'attacker-dev',
      })
    );
    await sleep(800);

    const forged = victim.received.filter(
      (m) => m.type === 'change' && m.entityId === 'forged-room'
    );
    expect(forged).toHaveLength(0);

    attacker.socket.close();
    victim.socket.close();
  });
});
