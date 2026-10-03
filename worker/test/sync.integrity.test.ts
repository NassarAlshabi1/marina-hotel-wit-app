import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { Database } from '../src/database';
import expenseMigration from '../migrations/0013_salary_withdrawal_expense_uuid.sql?raw';
import writeTimesMigration from '../migrations/0014_sync_write_times.sql?raw';
import { adminAuthHeader, pushOp, pushOperations, resetDb, roomPayload, schemaStatements, type PushResponseBody } from './helpers';

beforeEach(resetDb);

async function push(entity: string, operation: 'create' | 'update', data: Record<string, unknown>) {
  const auth = await adminAuthHeader();
  const response = await pushOperations(auth, [pushOp(entity, operation, data, {
    vectorClock: '{"device-A":9}', updatedAt: Math.floor(Date.now() / 1000) + 1,
  })]);
  return (await response.json()) as PushResponseBody;
}

async function parents() {
  expect((await push('employees', 'create', {
    local_uuid: 'employee-1', name: 'Employee', basic_salary: 1000,
  })).summary.failed).toBe(0);
  for (const local_uuid of ['expense-a', 'expense-b']) {
    expect((await push('expenses', 'create', {
      local_uuid, employee_uuid: 'employee-1', related_id: 5,
      expense_type: 'سلفة', amount: 100, date: '2026-10-03',
    })).summary.failed).toBe(0);
  }
}

function withdrawal(local_uuid: string, expense_uuid: string) {
  return { local_uuid, expense_uuid, employee_uuid: 'employee-1', employee_id: 5,
    amount: 100, withdraw_date: '2026-10-03', reason: 'exp_5' };
}

describe('financial integrity regression guards', () => {
  it('keeps distinct expense UUID mirrors despite identical local numeric references', async () => {
    await parents();
    expect((await push('salary_withdrawals', 'create', withdrawal('mirror-a', 'expense-a'))).summary.failed).toBe(0);
    expect((await push('salary_withdrawals', 'create', withdrawal('mirror-b', 'expense-b'))).summary.failed).toBe(0);
    expect((await push('salary_withdrawals', 'update', {
      ...withdrawal('mirror-a', 'expense-a'), amount: 150,
    })).summary.failed).toBe(0);
    const rows = await env.DB.prepare('SELECT local_uuid, expense_uuid, amount FROM salary_withdrawals ORDER BY local_uuid').all();
    expect(rows.results).toEqual([
      { local_uuid: 'mirror-a', expense_uuid: 'expense-a', amount: 150 },
      { local_uuid: 'mirror-b', expense_uuid: 'expense-b', amount: 100 },
    ]);
    expect((await push('salary_withdrawals', 'create', withdrawal('duplicate', 'expense-a'))).summary.failed).toBe(1);
    expect((await push('salary_withdrawals', 'update', withdrawal('mirror-a', 'expense-b'))).summary.failed).toBe(1);
  });

  it('retains a source UUID on a partial legacy update and rejects a missing expense parent', async () => {
    await parents();
    await push('salary_withdrawals', 'create', withdrawal('mirror-a', 'expense-a'));
    expect((await push('salary_withdrawals', 'update', {
      local_uuid: 'mirror-a', expense_uuid: null, amount: 110,
    })).summary.failed).toBe(0);
    expect(await env.DB.prepare('SELECT expense_uuid FROM salary_withdrawals WHERE local_uuid = ?')
      .bind('mirror-a').first()).toEqual({ expense_uuid: 'expense-a' });
    expect((await push('salary_withdrawals', 'create', withdrawal('orphan', 'unknown'))).summary.failed).toBe(1);
  });

  it('fails closed rather than silently dropping source UUID on a pre-0013 schema', async () => {
    await parents();
    await env.DB.prepare('DROP INDEX idx_salary_withdrawals_active_expense').run();
    await env.DB.prepare('ALTER TABLE salary_withdrawals DROP COLUMN expense_uuid').run();
    const result = await push('salary_withdrawals', 'create', withdrawal('mirror-a', 'expense-a'));
    expect(result.summary.failed).toBe(1);
    expect(result.results[0]?.error).toContain('0013');
  });

  it('rejects a night without either parent bridge; legacy updates cannot overwrite the canonical FK', async () => {
    expect((await push('booking_nights', 'create', {
      local_uuid: 'orphan-night', booking_local_id: 5, hotel_day_key: '2026-10-03',
    })).summary.failed).toBe(1);
    await push('bookings', 'create', { local_uuid: 'booking-1', room_number: '101' });
    await push('booking_nights', 'create', {
      local_uuid: 'night-1', booking_uuid_cache: 'booking-1', booking_local_id: 500,
      hotel_day_key: '2026-10-03', nightly_rate: 50,
    });
    const before = await env.DB.prepare('SELECT booking_local_id FROM booking_nights WHERE local_uuid = ?').bind('night-1').first();
    expect((await push('booking_nights', 'update', {
      local_uuid: 'night-1', booking_local_id: 9999, nightly_rate: 75,
    })).summary.failed).toBe(0);
    expect(await env.DB.prepare('SELECT booking_local_id FROM booking_nights WHERE local_uuid = ?').bind('night-1').first()).toEqual(before);
    expect(await env.DB.prepare('SELECT nightly_rate FROM booking_nights WHERE local_uuid = ?').bind('night-1').first()).toEqual({ nightly_rate: 75 });
  });

  it('keeps unresolved employee reassignment retryable instead of returning false success', async () => {
    await parents();
    const result = await push('expenses', 'update', {
      local_uuid: 'expense-a', employee_uuid: 'employee-not-yet-pushed', amount: 500,
    });
    expect(result.summary.failed).toBe(1);
    expect(await env.DB.prepare('SELECT employee_uuid, amount FROM expenses WHERE local_uuid = ?')
      .bind('expense-a').first()).toEqual({ employee_uuid: 'employee-1', amount: 100 });
  });

  it('delete disposition wins even when an edit references a parent that no longer exists', async () => {
    await parents();
    await push('salary_withdrawals', 'create', withdrawal('mirror-a', 'expense-a'));
    const db = new Database(env.DB);
    await db.deleteRecord('salary_withdrawals', 'mirror-a', 'device-A');
    const result = await push('salary_withdrawals', 'update', {
      local_uuid: 'mirror-a', employee_uuid: 'missing', expense_uuid: 'missing',
    });
    expect(result.results[0]?.status).toBe('deleted');
  });

  it('does not acknowledge an orphan withdrawal and accepts the same request once its parent arrives', async () => {
    const auth = await adminAuthHeader();
    const operation = pushOp('salary_withdrawals', 'create', {
      local_uuid: 'orphan-retry', employee_uuid: 'late-employee', employee_id: 999,
      amount: 250, withdraw_date: '2026-10-03',
    }, { idempotencyKey: 'orphan-request-stable' });
    for (let retry = 0; retry < 7; retry++) {
      const response = await pushOperations(auth, [operation]);
      const result = await response.json() as PushResponseBody;
      expect(result.results[0]?.success).toBe(false);
      expect(result.results[0]?.skipped).not.toBe(true);
    }
    expect(await env.DB.prepare("SELECT key FROM idempotency_log WHERE key = 'orphan-request-stable'").first()).toBeNull();
    expect(await env.DB.prepare("SELECT id FROM salary_withdrawals WHERE local_uuid = 'orphan-retry'").first()).toBeNull();
    await push('employees', 'create', {local_uuid: 'late-employee', name: 'Late', basic_salary: 1000});
    const retried = await pushOperations(auth, [operation]);
    expect((await retried.json() as PushResponseBody).summary.failed).toBe(0);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM salary_withdrawals WHERE local_uuid = 'orphan-retry'").first()).toEqual({n: 1});
  });

  it('uses wall-clock edit time, not the logical cursor, after a large clock advance', async () => {
    const now = Math.floor(Date.now() / 1000);
    await env.DB.prepare('UPDATE sync_clock SET last_ts = ? WHERE id = 1').bind(now + 3600).run();
    const db = new Database(env.DB);
    const payload = roomPayload({ local_uuid: 'logical-clock-room' });
    const created = await db.createRecord('rooms', payload, 'device-A', '{"device-A":1}');
    expect(created.updated_at).toBeGreaterThan(now + 3500);
    const updated = await db.updateRecord('rooms', created.local_uuid,
      { price: 250, version: 2 }, '{"device-B":1}', 'device-B', now);
    expect(updated.price).toBe(250);
    const stale = await db.updateRecord('rooms', created.local_uuid,
      { price: 1, version: 999 }, '{"device-C":1}', 'device-C', now - 200);
    expect(stale.price).toBe(250);
    const stamp = await env.DB.prepare('SELECT edited_at FROM sync_write_times WHERE entity = ? AND local_uuid = ?')
      .bind('rooms', created.local_uuid).first<{ edited_at: number }>();
    expect(stamp?.edited_at).toBe(now);
  });

  it('rolls back entity writes if conflict timestamp storage is unavailable', async () => {
    await env.DB.prepare('DROP TABLE sync_write_times').run();
    const result = await push('rooms', 'create', roomPayload({ local_uuid: 'must-not-persist' }));
    expect(result.summary.failed).toBe(1);
    expect(await env.DB.prepare('SELECT id FROM rooms WHERE local_uuid = ?').bind('must-not-persist').first()).toBeNull();
  });
});


describe('incremental financial migrations', () => {
  it('0013 adds a nullable source without inferring legacy numeric references', async () => {
    await parents();
    await push('salary_withdrawals', 'create', withdrawal('legacy', 'expense-a'));
    await env.DB.prepare('DROP INDEX idx_salary_withdrawals_active_expense').run();
    await env.DB.prepare('ALTER TABLE salary_withdrawals DROP COLUMN expense_uuid').run();
    for (const sql of schemaStatements(expenseMigration)) await env.DB.prepare(sql).run();
    expect(await env.DB.prepare('SELECT amount, reason, expense_uuid FROM salary_withdrawals WHERE local_uuid = ?')
      .bind('legacy').first()).toEqual({ amount: 100, reason: 'exp_5', expense_uuid: null });
  });

  it('0014 creates independent timestamp storage without touching entity rows and is idempotent', async () => {
    await push('rooms', 'create', roomPayload({ local_uuid: 'preserved' }));
    const before = await env.DB.prepare('SELECT * FROM rooms WHERE local_uuid = ?').bind('preserved').first();
    await env.DB.prepare('DROP TABLE sync_write_times').run();
    for (const sql of schemaStatements(writeTimesMigration)) await env.DB.prepare(sql).run();
    await env.DB.prepare('INSERT INTO sync_write_times VALUES (?, ?, ?)').bind('rooms', 'preserved', 12345).run();
    for (const sql of schemaStatements(writeTimesMigration)) await env.DB.prepare(sql).run();
    expect(await env.DB.prepare('SELECT edited_at FROM sync_write_times').first()).toEqual({ edited_at: 12345 });
    expect(await env.DB.prepare('SELECT * FROM rooms WHERE local_uuid = ?').bind('preserved').first()).toEqual(before);
  });
});
