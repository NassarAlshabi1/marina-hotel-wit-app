import { env, SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { financialHotelDay } from '../src/financial';
import { adminAuthHeader, pushOp, pushOperations, resetDb, pull, schemaStatements, type PushResponseBody } from './helpers';
import migration from '../migrations/0015_financial_reversals.sql?raw';

beforeEach(resetDb);
const history = '2026-09-01';
async function push(entity: string, operation: 'create' | 'update' | 'delete' | 'reverse', data: Record<string, unknown>, key?: string) {
  const response = await pushOperations(await adminAuthHeader(), [pushOp(entity, operation, data, key ? {idempotencyKey: key} : {})]);
  return await response.json() as PushResponseBody;
}
async function seed(linked = true) {
  if (linked) {
    expect((await push('employees', 'create', {local_uuid: 'employee', name: 'A', basic_salary: 1000})).summary.failed).toBe(0);
  }
  expect((await push('expenses', 'create', {local_uuid: 'expense', expense_type: linked ? 'سلفة' : 'تشغيلية', description: 'Original', amount: 100,
    date: history, hotel_day_key: history, ...(linked ? {employee_uuid: 'employee', related_id: 987} : {})})).summary.failed).toBe(0);
  if (linked) expect((await push('salary_withdrawals', 'create', {local_uuid: 'mirror', expense_uuid: 'expense', employee_uuid: 'employee', employee_id: 987,
    amount: 100, withdraw_date: history, hotel_day_key: history, withdrawal_type: 'سلفة'})).summary.failed).toBe(0);
}
async function reverse(entity = 'expenses', uuid = 'expense', key?: string) {
  return push(entity, 'reverse', {local_uuid: uuid, reason: 'Duplicate entry correction', amount: -999, reversal_actor: 'forged'}, key);
}
async function close(day = history, auth?: string) {
  return SELF.fetch('https://example.com/api/admin/financial/close-period', {
    method: 'POST', headers: {Authorization: auth ?? await adminAuthHeader(), 'Content-Type': 'application/json'},
    body: JSON.stringify({closed_through: day, reason: 'Reviewed and reconciled'}),
  });
}

describe('append-only financial corrections', () => {
  it('preserves originals, corrects both balances once and returns an atomic receipt', async () => {
    await seed();
    const cursor = await env.DB.prepare('SELECT last_ts FROM sync_clock WHERE id = 1').first<{last_ts: number}>();
    const before = await env.DB.prepare('SELECT * FROM expenses WHERE local_uuid = ?').bind('expense').first();
    const result = await reverse('expenses', 'expense', 'first-request');
    expect(result.summary.failed).toBe(0);
    expect(result.results[0]?.records).toHaveLength(4);
    expect(await env.DB.prepare('SELECT * FROM expenses WHERE local_uuid = ?').bind('expense').first()).toEqual(before);
    const expense = await env.DB.prepare('SELECT * FROM expenses WHERE reversal_of_uuid = ?').bind('expense').first();
    const mirror = await env.DB.prepare('SELECT * FROM salary_withdrawals WHERE reversal_of_uuid = ?').bind('mirror').first();
    expect(expense?.amount).toBe(-100);
    expect(expense?.hotel_day_key).toBe(financialHotelDay());
    expect(expense?.reversal_actor).not.toBe('forged');
    expect(mirror?.expense_uuid).toBe(expense?.local_uuid);
    expect(mirror?.amount).toBe(-100);
    expect(await env.DB.prepare('SELECT SUM(amount) AS total FROM expenses').first()).toEqual({total: 0});
    expect(await env.DB.prepare('SELECT SUM(amount) AS total FROM salary_withdrawals').first()).toEqual({total: 0});
    expect((await reverse('expenses', 'expense', 'first-request')).results[0]?.records).toHaveLength(4);
    expect((await reverse('expenses', 'expense', 'another-device')).results[0]?.entityId).toBe(expense?.local_uuid);
    expect((await reverse('salary_withdrawals', 'mirror')).results[0]?.entityId).toBe(expense?.local_uuid);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM financial_events').first()).toEqual({n: 1});
    const page = await pull(await adminAuthHeader(), {exclude_device: 'device-A', cursor: String(cursor!.last_ts), limit: '1'});
    expect(page.changes).toHaveLength(2);
    expect(page.changes[0]?.updated_at).toBe(page.changes[1]?.updated_at);
    expect(page.changes.some(row => row.local_uuid === expense?.local_uuid)).toBe(true);
    expect(page.changes.some(row => row.local_uuid === mirror?.local_uuid)).toBe(true);
  });

  it('serializes two devices correcting the same source without duplicate money', async () => {
    await seed();
    const results = await Promise.all([reverse('expenses', 'expense', 'device-1'), reverse('expenses', 'expense', 'device-2')]);
    expect(results.every(result => result.summary.failed === 0)).toBe(true);
    expect(results[0]?.results[0]?.entityId).toBe(results[1]?.results[0]?.entityId);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM expenses').first()).toEqual({n: 2});
  });

  it('rolls back the expense leg, clock and audit when its salary leg fails', async () => {
    await seed();
    const clock = await env.DB.prepare('SELECT last_ts FROM sync_clock WHERE id = 1').first();
    await env.DB.prepare("CREATE TRIGGER fail_reversal BEFORE INSERT ON salary_withdrawals WHEN NEW.amount < 0 BEGIN SELECT RAISE(ABORT, 'injected failure'); END").run();
    expect((await reverse()).summary.failed).toBe(1);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM expenses').first()).toEqual({n: 1});
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM financial_events').first()).toEqual({n: 0});
    expect(await env.DB.prepare('SELECT last_ts FROM sync_clock WHERE id = 1').first()).toEqual(clock);
  });

  it('rejects old client edits/deletes and forged negative creates', async () => {
    await seed(false);
    for (const operation of ['update', 'delete'] as const) {
      const result = await push('expenses', operation, {local_uuid: 'expense', amount: 900, deleted_at: 999});
      expect(result.results[0]?.status).toBe('validation_error');
    }
    expect((await push('expenses', 'create', {local_uuid: 'forged', amount: -100, date: history, reversal_of_uuid: 'expense'})).summary.failed).toBe(1);
    await expect(env.DB.prepare("UPDATE expenses SET amount = 0 WHERE local_uuid = 'expense'").run()).rejects.toThrow('FINANCIAL_IMMUTABLE');
    await expect(env.DB.prepare("DELETE FROM expenses WHERE local_uuid = 'expense'").run()).rejects.toThrow('FINANCIAL_IMMUTABLE');
    const raw = await SELF.fetch('https://example.com/api/sync/migrate', {
      method: 'POST', headers: {Authorization: await adminAuthHeader(), 'Content-Type': 'text/plain'},
      body: "INSERT OR REPLACE INTO expenses (local_uuid, amount) VALUES ('expense', 0)",
    });
    expect(raw.status).toBe(400);
  });

  it('keeps closed historical totals intact while reversing in the current hotel day', async () => {
    await seed();
    expect((await close()).status).toBe(200);
    expect((await reverse()).summary.failed).toBe(0);
    expect(await env.DB.prepare('SELECT SUM(amount) AS total FROM expenses WHERE hotel_day_key <= ?').bind(history).first()).toEqual({total: 100});
    expect((await push('expenses', 'create', {local_uuid: 'backdated', expense_type: 'تشغيلية', amount: 10, date: history})).results[0]?.status).toBe('validation_error');
    await expect(env.DB.prepare("INSERT INTO expenses(local_uuid, expense_type, description, amount, date, created_at, updated_at) VALUES ('raw-backdate', 'x', '', 10, ?, 1, 1)").bind(history).run()).rejects.toThrow('FINANCIAL_PERIOD_CLOSED');
    expect((await close('2026-08-31')).status).toBe(400);
    expect((await close(financialHotelDay())).status).toBe(400);
    await expect(env.DB.prepare('DELETE FROM financial_events').run()).rejects.toThrow('FINANCIAL_AUDIT_IMMUTABLE');
  });

  it('restricts period closure to administrators', async () => {
    const auth = await adminAuthHeader();
    const register = await SELF.fetch('https://example.com/api/auth/register', {
      method: 'POST', headers: {Authorization: auth, 'Content-Type': 'application/json'},
      body: JSON.stringify({username: 'staff', password: 'secure-password', role: 'staff'}),
    });
    expect(register.status).toBe(201);
    const user = await register.json() as {token: string};
    expect((await close(history, `Bearer ${user.token}`)).status).toBe(403);
  });

  it('requires a reason, refuses reversal-of-reversal and missing canonical mirror', async () => {
    await seed(false);
    expect((await push('expenses', 'reverse', {local_uuid: 'expense', reason: ' '})).results[0]?.status).toBe('validation_error');
    const result = await reverse();
    expect((await reverse('expenses', result.results[0]!.entityId!)).results[0]?.status).toBe('validation_error');
    await push('employees', 'create', {local_uuid: 'employee', name: 'A', basic_salary: 1000});
    await push('expenses', 'create', {local_uuid: 'unlinked', expense_type: 'سلفة', employee_uuid: 'employee', related_id: 1, amount: 100, date: history});
    expect((await reverse('expenses', 'unlinked')).results[0]?.status).toBe('internal_error');
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM expenses WHERE reversal_of_uuid = 'unlinked'").first()).toEqual({n: 0});
  });

  it('will not close a period containing an incomplete employee expense', async () => {
    await push('employees', 'create', {local_uuid: 'employee', name: 'A', basic_salary: 1000});
    await push('expenses', 'create', {local_uuid: 'unlinked', expense_type: 'employee', employee_uuid: 'employee', related_id: 1, amount: 100, date: history});
    expect((await close()).status).toBe(400);
    expect(await env.DB.prepare('SELECT closed_through FROM financial_period_lock').first()).toEqual({closed_through: ''});
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM financial_events').first()).toEqual({n: 0});
    expect((await reverse('expenses', 'unlinked')).summary.failed).toBe(1);
  });

  it('fails closed for expenses tied to an unsupported historical cash ledger', async () => {
    await push('expenses', 'create', {local_uuid: 'cash-linked', expense_type: 'تشغيلية', amount: 100, date: history, cash_transaction_id: 8});
    expect((await reverse('expenses', 'cash-linked')).results[0]?.status).toBe('validation_error');
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM expenses').first()).toEqual({n: 1});
  });

  it('supports genuine standalone withdrawals without creating an expense', async () => {
    await push('employees', 'create', {local_uuid: 'employee', name: 'A', basic_salary: 1000});
    await push('salary_withdrawals', 'create', {local_uuid: 'direct', employee_uuid: 'employee', employee_id: 1, amount: 50, withdraw_date: history, reason: 'direct_withdrawal_cash'});
    expect((await reverse('salary_withdrawals', 'direct')).summary.failed).toBe(0);
    expect(await env.DB.prepare('SELECT SUM(amount) AS total FROM salary_withdrawals').first()).toEqual({total: 0});
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM expenses').first()).toEqual({n: 0});
  });

  it('uses Aden 14:01 cutoff independently of client dates', () => {
    expect(financialHotelDay(Date.parse('2026-10-03T11:00:59Z'))).toBe('2026-10-02');
    expect(financialHotelDay(Date.parse('2026-10-03T11:01:00Z'))).toBe('2026-10-03');
  });

  it('upgrades a real pre-0015 table without changing historical money', async () => {
    await seed();
    const original = await env.DB.prepare('SELECT amount, date, deleted_at FROM expenses').all();
    const triggers = await env.DB.prepare("SELECT name FROM sqlite_master WHERE type = 'trigger'").all<{name: string}>();
    for (const trigger of triggers.results) await env.DB.prepare(`DROP TRIGGER ${trigger.name}`).run();
    for (const table of ['expenses', 'salary_withdrawals']) {
      await env.DB.prepare(`DROP INDEX idx_${table}_reversal`).run();
      for (const column of ['reversal_of_uuid', 'reversal_reason', 'reversal_actor']) await env.DB.prepare(`ALTER TABLE ${table} DROP COLUMN ${column}`).run();
    }
    await env.DB.prepare('DROP TABLE financial_events').run();
    await env.DB.prepare('DROP TABLE financial_period_lock').run();
    for (const sql of schemaStatements(migration)) await env.DB.prepare(sql).run();
    expect((await env.DB.prepare('SELECT amount, date, deleted_at FROM expenses').all()).results).toEqual(original.results);
    expect(await env.DB.prepare('SELECT reversal_of_uuid FROM expenses').first()).toEqual({reversal_of_uuid: null});
    expect((await reverse()).summary.failed).toBe(0);
  });
});
