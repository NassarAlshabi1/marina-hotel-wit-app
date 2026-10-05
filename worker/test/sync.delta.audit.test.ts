import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { Database } from '../src/database';
import { handleAiRequest } from '../src/ai';
import { adminAuthHeader, pull, resetDb, roomPayload } from './helpers';

beforeEach(resetDb);

describe('delta cross-client audit: preserve every committed change', () => {
  it('does not skip a writer that reserved an earlier cursor but committed later', async () => {
    let allocated!: () => void;
    let release!: () => void;
    const reserved = new Promise<void>((resolve) => { allocated = resolve; });
    const allowed = new Promise<void>((resolve) => { release = resolve; });
    // Pause the real write batch before it commits. This also reproduces the
    // old bug: previously the allocator had already committed by this point.
    const pausedDb = new Proxy(env.DB, {
      get(target, property) {
        if (property === 'batch') return async (statements: D1PreparedStatement[]) => {
          allocated();
          await allowed;
          return target.batch(statements);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    });
    const writerA = new Database(pausedDb);
    const writerB = new Database(env.DB);
    const late = writerA.createRecord('rooms', roomPayload({ local_uuid: 'late-a', room_number: 'AUDIT-A' }), 'device-A');
    try {
      await reserved;
      const early = await writerB.createRecord('rooms', roomPayload({ local_uuid: 'early-b', room_number: 'AUDIT-B' }), 'device-B');
      const first = await writerB.pullChanges('rooms', 0, 250);
      expect(first.changes.map((row) => row.local_uuid)).toContain('early-b');
      expect(first.changes.map((row) => row.local_uuid)).not.toContain('late-a');
      expect(first.cursor).toBe(early.updated_at);
      release();
      const committed = await late;
      // The final commit must replace the earlier reservation.
      expect(committed.updated_at).toBeGreaterThan(early.updated_at);
      expect(await env.DB.prepare('SELECT local_uuid FROM rooms WHERE local_uuid = ?')
        .bind('late-a').first()).not.toBeNull();
      const next = await writerB.pullChanges('rooms', first.cursor, 250);
      expect(next.changes.map((row) => row.local_uuid)).toContain('late-a');
    } finally {
      release();
      await late;
    }
  });

  it('does not miss an earlier table when a later table advances the global cursor', async () => {
    const writer = new Database(env.DB);
    let injected = false;
    // Delay/inject only between real SQL reads: there is no shared read snapshot
    // across the entity loop. All business writes use the real Database methods.
    const wrapStatement = (stmt: D1PreparedStatement, sql: string): D1PreparedStatement =>
      new Proxy(stmt, {
        get(target, property) {
          if (property === 'bind') return (...args: unknown[]) => wrapStatement(target.bind(...args), sql);
          if (property === 'all' && sql.startsWith('SELECT * FROM rooms WHERE')) {
            return async () => {
              const result = await target.all();
              if (!injected) {
                injected = true;
                await writer.createRecord('rooms', roomPayload({ local_uuid: 'between-reads-room', room_number: 'AUDIT-C' }), 'device-A');
                await writer.createRecord('employees', { local_uuid: 'between-reads-employee', name: 'Fixture', basic_salary: 1000, status: 'active' }, 'device-B');
              }
              return result;
            };
          }
          const value = Reflect.get(target, property, target);
          return typeof value === 'function' ? value.bind(target) : value;
        },
      });
    const observedDb = new Proxy(env.DB, {
      get(target, property) {
        if (property === 'prepare') return (sql: string) => wrapStatement(target.prepare(sql), sql);
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    });
    const first = await new Database(observedDb).pullChanges(null, 0, 250);
    expect(injected).toBe(true);
    // Both intervening writes must stay above this page's fixed boundary.
    expect(first.changes.map((row) => row.local_uuid)).not.toContain('between-reads-employee');
    const next = await writer.pullChanges(null, first.cursor, 250);
    expect([...first.changes, ...next.changes].map((row) => row.local_uuid)).toEqual(expect.arrayContaining(['between-reads-room', 'between-reads-employee']));
  });

  it('honors include_remaining=true as serialized by the Android Boolean query', async () => {
    const response = await pull(await adminAuthHeader(), { cursor: '0', include_remaining: 'true' });
    expect(response.errors).toEqual([]);
    expect(response.remaining).not.toBeNull();
  });

  it('honors normalize_timestamps=true as serialized by the Android Boolean query', async () => {
    const response = await pull(await adminAuthHeader(), { cursor: '0', normalize_timestamps: 'true' });
    expect(response.errors).toEqual([]);
    expect(response.normalization).not.toBeNull();
  });
  it.each(['update', 'delete'] as const)('publishes a delayed %s above an intervening pull', async (operation) => {
    const db = new Database(env.DB);
    await db.createRecord('rooms', roomPayload({ local_uuid: 'target' }), 'device-A');
    let paused!: () => void;
    let release!: () => void;
    const ready = new Promise<void>((r) => { paused = r; });
    const resume = new Promise<void>((r) => { release = r; });
    const observedDb = new Proxy(env.DB, {
      get(target, property) {
        if (property === 'batch') return async (statements: D1PreparedStatement[]) => {
          paused(); await resume; return target.batch(statements);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    });
    const delayed = new Database(observedDb);
    const write = operation === 'update'
      ? delayed.updateRecord('rooms', 'target', { price: 777 }, '{"device-A":99}', 'device-A')
      : delayed.deleteRecord('rooms', 'target', 'device-A');
    try {
      await ready;
      await db.createRecord('rooms', roomPayload({ local_uuid: 'intervening' }), 'device-B');
      const first = await db.pullChanges('rooms', 0, 250);
      release(); await write;
      const next = await db.pullChanges('rooms', first.cursor, 250);
      const target = next.changes.find((row) => row.local_uuid === 'target');
      expect(target).toBeDefined();
      if (operation === 'update') expect(target!.price).toBe(777);
      else expect(target!.deleted_at).not.toBeNull();
    } finally { release(); await write; }
  });

  it('rolls back both the business row and its clock on a failed write batch', async () => {
    const before = await env.DB.prepare('SELECT last_ts FROM sync_clock WHERE id = 1').first();
    await env.DB.prepare('DROP TABLE sync_write_times').run();
    await expect(new Database(env.DB).createRecord('rooms', roomPayload({ local_uuid: 'rollback' }), 'device-A')).rejects.toThrow();
    expect(await env.DB.prepare("SELECT * FROM rooms WHERE local_uuid = 'rollback'").first()).toBeNull();
    expect(await env.DB.prepare('SELECT last_ts FROM sync_clock WHERE id = 1').first()).toEqual(before);
  });

  it('acknowledges poison repair and returns the repaired row on the next page', async () => {
    await new Database(env.DB).createRecord('rooms', roomPayload({ local_uuid: 'poison' }), 'device-A');
    await env.DB.prepare("UPDATE rooms SET updated_at = 9999999999 WHERE local_uuid = 'poison'").run();
    const auth = await adminAuthHeader();
    const first = await pull(auth, { cursor: '0', entity: 'rooms' });
    expect(first.errors).toEqual([]);
    expect(first.changes).toEqual([]);
    expect(first.cursor).toBe('0');
    expect(first.has_more).toBe(true);
    expect(first.repair_pending).toBe(true);
    const next = await pull(auth, { cursor: first.cursor, entity: 'rooms' });
    expect(next.changes.map((row) => row.local_uuid)).toContain('poison');
    expect(next.repair_pending).toBe(false);
  });

  it('does not acknowledge normalization completion when a table failed', async () => {
    await env.DB.prepare('DROP TABLE rooms').run();
    expect((await new Database(env.DB).normalizeTimestamps()).complete).toBe(false);
  });

  it('publishes confirmed AI expenses using unique committed second-based cursors', async () => {
    const db = new Database(env.DB);
    const first = await db.pullChanges(null, 0);
    const response = await handleAiRequest(new Request('https://example.com/api/ai', {
      method: 'POST', body: JSON.stringify({ confirm: true, plan: {
        kind: 'add_expense', expenseType: 'other', description: 'Audit fixture', amountPerDay: 100,
        dateFrom: '2026-10-01', dateTo: '2026-10-02', explanation: 'fixture',
      } }),
    }), { DB: env.DB, AI: { run: async () => { throw new Error('No AI network calls expected'); } } }, 'admin');
    expect(response.status).toBe(200);
    const next = await db.pullChanges('expenses', first.cursor);
    expect(next.changes).toHaveLength(2);
    expect(new Set(next.changes.map((row) => row.updated_at)).size).toBe(2);
    for (const row of next.changes) {
      expect(row.updated_at).toBeGreaterThan(first.cursor);
      expect(row.updated_at).toBeLessThan(2000000000);
      expect(row.amount).toBe(100);
    }
  });

});
