// ═══════════════════════════════════════════════════════════════
//  realtime.broadcast.test.ts — plan phase 3 (server half)
//  After a successful push, the worker broadcasts a `change` event
//  per distinct touched entity to the SyncLockDO WebSocket hub.
//  Contract: skipped (idempotent replay) ops do NOT re-broadcast;
//  per-entity dedupe within a batch; pusher's deviceId is carried
//  so clients can filter their own echo.
//
//  NOTE: vi.waitFor is unreliable under vitest-pool-workers (timer
//  integration) — polling with plain sleeps is used instead.
// ═══════════════════════════════════════════════════════════════

import { SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  resetDb,
  adminAuthHeader,
  pushOp,
  pushOperations,
  roomPayload,
  uniqueUuid,
  type PushResponseBody,
} from './helpers';

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
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Open a realtime WebSocket through the real worker route.
 *  NOTE: client-side sockets under vitest-pool-workers do NOT emit a
 *  'close' event after .close() — never await close in these tests. */
async function connectRealtime(deviceId: string): Promise<{
  socket: WebSocket;
  received: BroadcastMessage[];
}> {
  const auth = await adminAuthHeader();
  const res = await SELF.fetch(
    `https://example.com/api/realtime?deviceId=${encodeURIComponent(deviceId)}&entity=*`,
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
  // Welcome presence arrives synchronously on accept — wait for it so the
  // session is fully registered in the DO before the push fires.
  await sleep(300);
  expect(received.some((m) => m.type === 'presence')).toBe(true);
  return { socket, received };
}

const changeEvents = (received: BroadcastMessage[]) =>
  received.filter((m) => m.type === 'change');

async function pushRooms(
  payload: Record<string, unknown>,
  deviceId: string
): Promise<PushResponseBody> {
  const auth = await adminAuthHeader();
  const res = await pushOperations(auth, [pushOp('rooms', 'create', payload, { deviceId })]);
  expect(res.status).toBe(200);
  return (await res.json()) as PushResponseBody;
}

describe('push → realtime broadcast', () => {
  it('connected listener receives a change event after a successful push', { timeout: 30000 }, async () => {
    const { socket, received } = await connectRealtime('listener-device');

    const body = await pushRooms(roomPayload(), 'pusher-device');
    expect(body.summary.success).toBe(1);

    await sleep(1000);

    const change = changeEvents(received).find((m) => m.entity === 'rooms')!;
    expect(change.deviceId).toBe('pusher-device');
    expect(change.operation).toBe('create');
    expect(change.entityId).toBeTruthy();

    socket.close();
  });

  it('two entities in one batch produce one change event each (per-entity dedupe)', { timeout: 30000 }, async () => {
    const { socket, received } = await connectRealtime('listener-device');

    const auth = await adminAuthHeader();
    const res = await pushOperations(auth, [
      pushOp('rooms', 'create', roomPayload(), { deviceId: 'pusher-device' }),
      pushOp(
        'blacklist',
        'create',
        {
          local_uuid: uniqueUuid('bl'),
          name: `Guest ${Math.floor(Math.random() * 100000)}`,
          reason: 'test',
          created_at: 1700000000,
          updated_at: 1700000000,
          last_modified: 1700000000,
          version: 1,
          origin: 'local',
          vector_clock: '{}',
          device_id: 'pusher-device',
        },
        { deviceId: 'pusher-device' }
      ),
    ]);
    expect(res.status).toBe(200);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(2);

    await sleep(1000);

    // Exactly ONE change event per entity (deduped within the batch)
    expect(changeEvents(received).filter((m) => m.entity === 'rooms').length).toBe(1);
    expect(changeEvents(received).filter((m) => m.entity === 'blacklist').length).toBe(1);

    socket.close();
  });

  it('idempotent replay (skipped ops) does not re-broadcast', { timeout: 30000 }, async () => {
    const { socket, received } = await connectRealtime('listener-device');

    const auth = await adminAuthHeader();
    const idemKey = uniqueUuid('idem');
    const payload = roomPayload();

    const first = await pushOperations(auth, [
      pushOp('rooms', 'create', payload, { idempotencyKey: idemKey, deviceId: 'pusher-device' }),
    ]);
    expect(((await first.json()) as PushResponseBody).summary.success).toBe(1);

    await sleep(1000);
    const countAfterFirstPush = changeEvents(received).length;
    expect(countAfterFirstPush).toBeGreaterThan(0);

    // Exact replay — all ops skipped → no new change events
    const replay = await pushOperations(auth, [
      pushOp('rooms', 'create', payload, { idempotencyKey: idemKey, deviceId: 'pusher-device' }),
    ]);
    const replayBody = (await replay.json()) as PushResponseBody;
    expect(replayBody.summary.skipped).toBe(1);

    // Grace period for any (wrong) async broadcast to surface
    await sleep(500);
    expect(changeEvents(received).length).toBe(countAfterFirstPush);

    socket.close();
  });

  it('failed ops produce no broadcast', { timeout: 30000 }, async () => {
    const { socket, received } = await connectRealtime('listener-device');

    const auth = await adminAuthHeader();
    // Unknown entity → per-op validation failure WITHOUT execution
    const res = await pushOperations(auth, [
      pushOp('no_such_entity', 'create', { local_uuid: uniqueUuid() }, { deviceId: 'pusher-device' }),
    ]);
    expect(res.status).toBe(200);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.failed).toBe(1);

    await sleep(500);
    expect(changeEvents(received).length).toBe(0);

    socket.close();
  });
});
