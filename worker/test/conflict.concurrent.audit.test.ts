import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { Database } from '../src/database';
import { resetDb, roomPayload } from './helpers';

beforeEach(resetDb);

// Required invariants, deliberately not marked expected-failure: these must
// pass before concurrent conflict resolution can be described as safe.
describe('concurrent conflict resolution audit', () => {
  it('keeps a newer competing edit when requests are sequential', async () => {
    const db = new Database(env.DB);
    await db.createRecord('rooms', roomPayload({ local_uuid: 'conflict-target' }), 'A');
    const now = Math.floor(Date.now() / 1000);
    await db.updateRecord('rooms', 'conflict-target', { price: 999, version: 2 }, '{"A":1,"B":1}', 'B', now + 20);
    await db.updateRecord('rooms', 'conflict-target', { price: 111, version: 2 }, '{"A":2}', 'A', now + 10);
    const stored = await env.DB.prepare("SELECT * FROM rooms WHERE local_uuid = 'conflict-target'").first();
    expect(stored!.price).toBe(999);
  });

  it.each(['newer-edit', 'older-edit', 'delete'] as const)('rechecks %s committed after conflict evaluation but before the delayed write', async (intervening) => {
    const db = new Database(env.DB);
    await db.createRecord('rooms', roomPayload({ local_uuid: 'conflict-target' }), 'A');
    let paused!: () => void;
    let release!: () => void;
    const ready = new Promise<void>((resolve) => { paused = resolve; });
    const resume = new Promise<void>((resolve) => { release = resolve; });
    const delayedDb = new Proxy(env.DB, {
      get(target, property) {
        if (property === 'batch') return async (statements: D1PreparedStatement[]) => {
          paused(); await resume; return target.batch(statements);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    });
    const now = Math.floor(Date.now() / 1000);
    // This decision is made against version 1, before B's edit/delete.
    const pending = new Database(delayedDb).updateRecord('rooms', 'conflict-target',
      { price: 111, version: 2, deleted_at: null }, '{"A":2}', 'A', now + 10);
    try {
      await ready;
      if (intervening === 'delete') await db.deleteRecord('rooms', 'conflict-target', 'B');
      else await db.updateRecord('rooms', 'conflict-target',
        { price: 999, version: 2 }, '{"A":1,"B":1}', 'B', now + (intervening === 'older-edit' ? 5 : 20));
      const winner = await env.DB.prepare("SELECT * FROM rooms WHERE local_uuid = 'conflict-target'").first();
      const editTime = await env.DB.prepare("SELECT edited_at FROM sync_write_times WHERE entity = 'rooms' AND local_uuid = 'conflict-target'").first();
      release(); const result = await pending;
      const stored = await env.DB.prepare("SELECT * FROM rooms WHERE local_uuid = 'conflict-target'").first();
      if (intervening === 'older-edit') {
        expect(stored!.price).toBe(111);
        expect(stored!.version).toBe(3);
        expect(JSON.parse(String(stored!.vector_clock))).toEqual({ A: 2, B: 1 });
        expect(await env.DB.prepare("SELECT edited_at FROM sync_write_times WHERE entity = 'rooms' AND local_uuid = 'conflict-target'").first())
          .toEqual({ edited_at: now + 10 });
      } else {
        // A rejected CAS must leave both the winning row AND its metadata intact.
        expect(stored).toEqual(winner);
        expect(await env.DB.prepare("SELECT edited_at FROM sync_write_times WHERE entity = 'rooms' AND local_uuid = 'conflict-target'").first()).toEqual(editTime);
        if (intervening === 'delete') {
          expect(stored!.deleted_at).not.toBeNull();
          expect(result.opStatus).toBe('deleted');
        } else expect(stored!.price).toBe(999);
      }
    } finally { release(); await pending; }
  });
  it('bounds contention retries without corrupting the winning row or edit metadata', async () => {
    const db = new Database(env.DB);
    await db.createRecord('rooms', roomPayload({ local_uuid: 'contended' }), 'A');
    const now = Math.floor(Date.now() / 1000);
    let attempts = 0;
    const busyDb = new Proxy(env.DB, {
      get(target, property) {
        if (property === 'batch') return async (statements: D1PreparedStatement[]) => {
          attempts++;
          await db.updateRecord('rooms', 'contended', { price: 900 + attempts },
            JSON.stringify({ A: 1, B: attempts }), 'B', now + attempts);
          return target.batch(statements);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    });
    await expect(new Database(busyDb).updateRecord('rooms', 'contended',
      { price: 111, version: 2 }, '{"A":2}', 'A', now + 50)).rejects.toThrow('Concurrent update contention');
    expect(attempts).toBe(5);
    const row = await env.DB.prepare("SELECT * FROM rooms WHERE local_uuid = 'contended'").first();
    expect(row!.price).toBe(905);
    expect(row!.version).toBe(6);
    expect(await env.DB.prepare("SELECT edited_at FROM sync_write_times WHERE entity = 'rooms' AND local_uuid = 'contended'").first())
      .toEqual({ edited_at: now + 5 });
  });

  it('increments a delayed delete from the current version and delivers it to the original author', async () => {
    const db = new Database(env.DB);
    await db.createRecord('rooms', roomPayload({ local_uuid: 'delete-race' }), 'A');
    let intercepted = false;
    const delayedDb = new Proxy(env.DB, {
      get(target, property) {
        if (property === 'batch') return async (statements: D1PreparedStatement[]) => {
          if (!intercepted) {
            intercepted = true;
            await db.updateRecord('rooms', 'delete-race', { price: 999 }, '{"A":2}', 'A');
          }
          return target.batch(statements);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    });
    await new Database(delayedDb).deleteRecord('rooms', 'delete-race', 'B');
    const pulled = await db.pullChanges('rooms', 0, 250, 'A');
    expect(pulled.changes).toHaveLength(1);
    expect(pulled.changes[0].deleted_at).not.toBeNull();
    expect(pulled.changes[0].device_id).toBe('B');
    expect(pulled.changes[0].version).toBe(3);
    expect(pulled.changes[0].price).toBe(999);
  });

});
