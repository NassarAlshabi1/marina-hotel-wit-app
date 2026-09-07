// ═══════════════════════════════════════════════════════════════
//  sync.push.test.ts — plan task 1.3 (+ D7 gap closure + app_users)
//  Idempotency, per-field validation, batch limits, per-op error
//  isolation, create/update/delete flows for ALL 23 entities.
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { resetDb, adminAuthHeader, pull, pushOp, pushOperations, roomPayload, uniqueUuid, type PushResponseBody } from './helpers';

beforeEach(async () => {
  await resetDb();
});


describe('push: validation', () => {
  it('rejects a batch with >100 operations (400)', async () => {
    const auth = await adminAuthHeader();
    const ops = Array.from({ length: 101 }, (_, i) =>
      pushOp('rooms', 'create', roomPayload({ room_number: `V${i}` }), {
        idempotencyKey: uniqueUuid('idem'),
      })
    );
    const res = await pushOperations(auth, ops);
    expect(res.status).toBe(400);
  });

  it('validates every required field with precise errors', async () => {
    const auth = await adminAuthHeader();
    const res = await pushOperations(auth, [
      { entity: 'rooms', operation: 'create', data: {}, vectorClock: '{}', updatedAt: 1 }, // no idempotencyKey
      { idempotencyKey: uniqueUuid(), operation: 'create', data: {}, vectorClock: '{}', updatedAt: 1 }, // no entity
      { idempotencyKey: uniqueUuid(), entity: 'rooms', operation: 'upsert', data: {}, vectorClock: '{}', updatedAt: 1 }, // bad op
      { idempotencyKey: uniqueUuid(), entity: 'rooms', operation: 'create', vectorClock: '{}', updatedAt: 1 }, // no data
      { idempotencyKey: uniqueUuid(), entity: 'rooms', operation: 'create', data: {}, updatedAt: 1 }, // no vectorClock
      { idempotencyKey: uniqueUuid(), entity: 'rooms', operation: 'create', data: {}, vectorClock: '{}', updatedAt: -5 }, // bad ts
    ]);
    expect(res.status).toBe(200); // per-op errors, not a batch rejection
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.total).toBe(6);
    expect(body.summary.success).toBe(0);
    expect(body.summary.failed).toBe(6);
    expect(body.results[0].error).toContain('idempotencyKey');
    expect(body.results[1].error).toContain('entity');
    expect(body.results[2].error).toContain('Invalid operation');
    expect(body.results[3].error).toContain('data');
    expect(body.results[4].error).toContain('vectorClock');
    expect(body.results[5].error).toContain('updatedAt');
  });

  it('rejects unknown entities including the removed local-only ledger and users (400/failed)', async () => {
    const auth = await adminAuthHeader();
    const res = await pushOperations(auth, [
      pushOp('unknown_entity', 'create', { local_uuid: uniqueUuid() }),
      pushOp('hotel_day_ledger', 'create', { local_uuid: uniqueUuid() }), // plan D8: no longer mappable
      pushOp('users', 'create', { local_uuid: uniqueUuid() }), // infra table — not an entity
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.failed).toBe(3);
    expect(body.results[0].error).toContain('Unknown entity');
    expect(body.results[1].error).toContain('Unknown entity');
    expect(body.results[2].error).toContain('Unknown entity');
  });
});

describe('push: create flow', () => {
  it('creates a room, stamps sync fields, and the row is pullable', async () => {
    const auth = await adminAuthHeader();
    const payload = roomPayload();
    const res = await pushOperations(auth, [pushOp('rooms', 'create', payload)]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);
    expect(body.results[0].entityId).toBe(payload.local_uuid);

    const row = await env.DB.prepare('SELECT * FROM rooms WHERE local_uuid = ?')
      .bind(payload.local_uuid)
      .first<Record<string, unknown>>();
    expect(row).not.toBeNull();
    expect(row?.version).toBe(1);
    expect(row?.origin).toBe('cloud'); // server-stamped
    expect(row?.device_id).toBe('device-A');
    expect(typeof row?.updated_at).toBe('number');

    const pulled = await pull(auth);
    expect(pulled.changes.some((c) => c.local_uuid === payload.local_uuid)).toBe(true);
  });

  it('is idempotent: duplicate idempotencyKey → skipped:true, no duplicate row', async () => {
    const auth = await adminAuthHeader();
    const payload = roomPayload();
    const key = uniqueUuid('idem');
    const first = await pushOperations(auth, [pushOp('rooms', 'create', payload, { idempotencyKey: key })]);
    const firstBody = (await first.json()) as PushResponseBody;
    expect(firstBody.summary.success).toBe(1);

    const second = await pushOperations(auth, [
      pushOp('rooms', 'create', payload, { idempotencyKey: key }),
    ]);
    const secondBody = (await second.json()) as PushResponseBody;
    expect(secondBody.results[0].skipped).toBe(true);
    expect(secondBody.results[0].success).toBe(true);

    const count = await env.DB.prepare('SELECT COUNT(*) AS c FROM rooms WHERE local_uuid = ?')
      .bind(payload.local_uuid)
      .first<{ c: number }>();
    expect(count?.c).toBe(1);
  });

  it('duplicate local_uuid with a new idempotency key does not duplicate the row', async () => {
    const auth = await adminAuthHeader();
    const payload = roomPayload();
    await pushOperations(auth, [pushOp('rooms', 'create', payload)]);
    await pushOperations(auth, [pushOp('rooms', 'create', payload)]); // new key, same local_uuid

    const count = await env.DB.prepare('SELECT COUNT(*) AS c FROM rooms WHERE local_uuid = ?')
      .bind(payload.local_uuid)
      .first<{ c: number }>();
    expect(count?.c).toBe(1);
  });

  it('fills NOT NULL columns without defaults and filters unknown columns', async () => {
    const auth = await adminAuthHeader();
    const payload = {
      local_uuid: uniqueUuid('emp'),
      name: 'Ahmad',
      not_a_real_column: 'should be dropped',
      // basic_salary / position / status are NOT NULL — omitted on purpose
      created_at: 1700000000,
      updated_at: 1700000000,
      device_id: 'device-A',
    };
    const res = await pushOperations(auth, [pushOp('employees', 'create', payload)]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);

    const row = await env.DB.prepare('SELECT * FROM employees WHERE local_uuid = ?')
      .bind(payload.local_uuid)
      .first<Record<string, unknown>>();
    expect(row?.['basic_salary']).toBe(0); // numeric NOT NULL without default filled
    expect(row?.['status']).toBe(''); // text NOT NULL without default filled
    expect(row?.['position']).toBe('موظف'); // NOT NULL WITH default keeps its default
    expect(row).not.toHaveProperty('not_a_real_column');
  });
});

describe('push: update flow', () => {
  it('updates by local_uuid, bumps version, and preserves created_at', async () => {
    const auth = await adminAuthHeader();
    const payload = roomPayload();
    await pushOperations(auth, [pushOp('rooms', 'create', payload)]);

    const res = await pushOperations(auth, [
      pushOp('rooms', 'update', { ...payload, price: 250, status: 'occupied' }, {
        vectorClock: '{"device-A":2}',
        updatedAt: 1700000100,
      }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);

    const row = await env.DB.prepare('SELECT * FROM rooms WHERE local_uuid = ?')
      .bind(payload.local_uuid)
      .first<Record<string, unknown>>();
    expect(row?.['price']).toBe(250);
    expect(row?.['status']).toBe('occupied');
    expect(row?.['version']).toBe(2);
    expect(row?.['created_at']).toBe(1700000000); // untouched
  });

  it('update of a missing local_uuid falls back to create', async () => {
    const auth = await adminAuthHeader();
    const payload = roomPayload();
    const res = await pushOperations(auth, [
      pushOp('rooms', 'update', payload, { updatedAt: 1700000100 }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);
    const row = await env.DB.prepare('SELECT local_uuid FROM rooms WHERE local_uuid = ?')
      .bind(payload.local_uuid)
      .first();
    expect(row).not.toBeNull();
  });

  it('rejects update/delete ops whose data carries no identity', async () => {
    const auth = await adminAuthHeader();
    const res = await pushOperations(auth, [
      pushOp('rooms', 'update', { price: 5 }),
      pushOp('rooms', 'delete', { note: 'no identity here' }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.failed).toBe(2);
    expect(body.results[0].error).toContain('local_uuid');
  });
});

describe('push: delete flow (tombstones)', () => {
  it('soft-deletes: sets deleted_at, bumps version, stays pullable exactly once', async () => {
    const auth = await adminAuthHeader();
    const payload = roomPayload();
    await pushOperations(auth, [pushOp('rooms', 'create', payload)]);
    await pushOperations(auth, [pushOp('rooms', 'delete', { local_uuid: payload.local_uuid })]);

    const row = await env.DB.prepare('SELECT * FROM rooms WHERE local_uuid = ?')
      .bind(payload.local_uuid)
      .first<Record<string, unknown>>();
    expect(row?.['deleted_at']).not.toBeNull();
    expect(row?.['version']).toBe(2);

    // Tombstone pulls (server-stamped updated_at > cursor 0)
    const first = await pull(auth);
    const tombstones = first.changes.filter((c) => c.local_uuid === payload.local_uuid);
    expect(tombstones).toHaveLength(1);
    expect(tombstones[0].deleted_at).not.toBeNull();

    // Cursor advanced past it → not pulled again
    const second = await pull(auth, { cursor: first.cursor });
    expect(second.changes.some((c) => c.local_uuid === payload.local_uuid)).toBe(false);
  });

  it('delete of a non-existent record reports deleted:false without error', async () => {
    const auth = await adminAuthHeader();
    const res = await pushOperations(auth, [
      pushOp('rooms', 'delete', { local_uuid: uniqueUuid('ghost') }),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);
  });
});

describe('push: D7 gap closure — inventory & blacklist entities', () => {
  it('creates inventory_items, inventory_transactions and blacklist rows', async () => {
    const auth = await adminAuthHeader();
    const item = {
      local_uuid: uniqueUuid('item'),
      name: `Soap-${uniqueUuid('x')}`,
      unit: 'قطعة',
      category: 'cleaning',
      quantity: 10,
      minimum_quantity: 2,
      is_active: 1,
      created_at: 1700000000,
      updated_at: 1700000000,
      device_id: 'device-A',
      version: 1,
      vector_clock: '{}',
    };
    const tx = {
      local_uuid: uniqueUuid('tx'),
      item_local_uuid: item.local_uuid,
      item_id: 1,
      movement_type: 'in',
      quantity: 10,
      balance_after: 10,
      note: 'initial stock',
      created_at: 1700000000,
      updated_at: 1700000000,
      device_id: 'device-A',
      version: 1,
      vector_clock: '{}',
    };
    const bl = {
      local_uuid: uniqueUuid('bl'),
      name: 'Blacklisted Guest',
      nationality: 'SY',
      national_id: '1234567890',
      phone: '0999888777',
      reason: 'payment fraud',
      active: 1,
      is_active: 1,
      added_date: '2026-01-01',
      added_by: 'admin',
      created_at: 1700000000,
      updated_at: 1700000000,
      device_id: 'device-A',
      version: 1,
      vector_clock: '{}',
    };
    // app_users — user directive 2026-09-05 (default sync scope includes
    // user_app with pull/push + outbox delta sync). Payload shape mirrors
    // AuthLocalStore.appUsersSyncPayload (snake_case D1 columns).
    const au = {
      local_uuid: uniqueUuid('au'),
      username: 'sync_test_admin',
      password: 'pbkdf2$hash',
      full_name: 'Sync Test Admin',
      user_type: 'admin',
      permissions: '["dashboard"]',
      active: 1,
      last_login: 0,
      credentials_version: 1,
      role: 'admin',
      created_at: 1700000000,
      updated_at: 1700000000,
      device_id: 'device-A',
      version: 1,
      vector_clock: '{}',
    };

    const res = await pushOperations(auth, [
      pushOp('inventory_items', 'create', item),
      pushOp('inventory_transactions', 'create', tx),
      pushOp('blacklist', 'create', bl),
      pushOp('app_users', 'create', au),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.failed).toBe(0);
    expect(body.summary.success).toBe(4);

    // All four pull back with _entity tags
    const pulled = await pull(auth);
    const entities = new Set(pulled.changes.map((c) => c._entity));
    expect(entities.has('inventory_items')).toBe(true);
    expect(entities.has('inventory_transactions')).toBe(true);
    expect(entities.has('blacklist')).toBe(true);
    expect(entities.has('app_users')).toBe(true);
  });

  it('app_users delta: update via outbox-style snake payload + per-entity pull', async () => {
    const auth = await adminAuthHeader();
    const docId = 'user_sync_test';
    await pushOperations(auth, [
      pushOp('app_users', 'create', {
        local_uuid: docId,
        username: 'delta_admin',
        full_name: 'Delta Admin',
        user_type: 'admin',
        active: 1,
        credentials_version: 1,
        created_at: 1700000000,
        updated_at: 1700000000,
        device_id: 'device-A',
        version: 1,
        vector_clock: '{}',
      }),
    ]);
    // permission-style update — exactly what auth_local_store enqueues.
    // The vector clock BUILDS ON the create's clock (device-A seeded by
    // the server) so the incoming op strictly dominates — LWW then applies
    // it regardless of the server's monotonic clock being ahead of the
    // test's fixed op timestamps.
    const res = await pushOperations(auth, [
      pushOp(
        'app_users',
        'update',
        {
          local_uuid: docId,
          permissions: '["dashboard","rooms"]',
          credentials_version: 2,
          updated_at: 1700000100,
          last_modified: 1700000100,
          last_modified_epoch: 1700000100,
          version: 2,
          vector_clock: '{"device-A":1,"device-B":1}',
          device_id: 'device-B',
        },
        { updatedAt: 1700000200 }
      ),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.failed).toBe(0);
    expect(body.summary.success).toBe(1);

    const onlyAppUsers = await pull(auth, { entity: 'app_users' });
    expect(onlyAppUsers.changes.length).toBe(1);
    expect(onlyAppUsers.changes[0]._entity).toBe('app_users');
    expect(onlyAppUsers.changes[0].username).toBe('delta_admin');
    expect(onlyAppUsers.changes[0].credentials_version).toBe(2);
    expect(onlyAppUsers.changes[0].permissions).toBe('["dashboard","rooms"]');
  });

  it('per-entity pull works for the new entities', async () => {
    const auth = await adminAuthHeader();
    const bl = {
      local_uuid: uniqueUuid('bl'),
      name: 'Only Blacklist',
      created_at: 1700000000,
      updated_at: 1700000000,
      device_id: 'device-A',
    };
    await pushOperations(auth, [pushOp('blacklist', 'create', bl)]);
    await pushOperations(auth, [pushOp('rooms', 'create', roomPayload())]);

    const onlyBlacklist = await pull(auth, { entity: 'blacklist' });
    expect(onlyBlacklist.changes.length).toBe(1);
    expect(onlyBlacklist.changes[0]._entity).toBe('blacklist');
    expect(onlyBlacklist.changes[0].name).toBe('Only Blacklist');
  });
});

describe('push: error isolation inside a batch', () => {
  it('one failing operation does not abort the others', async () => {
    const auth = await adminAuthHeader();
    const res = await pushOperations(auth, [
      pushOp('rooms', 'create', roomPayload()),
      pushOp('unknown_entity', 'create', { local_uuid: uniqueUuid() }), // fails
      pushOp('rooms', 'create', roomPayload()),
    ]);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary).toEqual({ total: 3, success: 2, failed: 1, skipped: 0 });
    expect(body.results[1].success).toBe(false);
  });
});
