import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { Database } from '../src/database';
import { expenseKind, legacyExpenseKind } from '../src/expense-kind';
import { adminAuthHeader, pushOp, pushOperations, resetDb } from './helpers';
import migration from '../migrations/0015_expense_kind.sql?raw';

beforeEach(resetDb);
const payload = (extra: Record<string, unknown> = {}) => ({
  local_uuid: 'kind-expense', expense_type: 'خصم من الراتب', description: 'قسط سلفة شهر أكتوبر',
  amount: 100, date: '2026-10-01', is_auto_generated: 1, ...extra,
});
describe('expense_kind stable wire contract', () => {
  it.each([
    ['سلفة', 0, '', 'salary_advance'], ['رواتب', 0, '', 'salary_withdrawal'],
    ['خصم من الراتب', 1, 'قسط سلفة', 'salary_installment'],
    ['خصم من الراتب', 1, 'edited historical note', 'unclassified'],
    ['خصم من الراتب', 0, 'قسط سلفة', 'salary_deduction'],
    ['خصم', 1, '', 'salary_deduction'], ['مشتريات', 0, '', 'normal'],
  ])('classifies legacy %s conservatively', (type, auto, description, expected) => {
    expect(legacyExpenseKind({ expense_type: type, is_auto_generated: auto, description })).toBe(expected);
  });
  it('preserves installment after a legacy client edits free text or omits/nulls kind', async () => {
    const db = new Database(env.DB);
    const created = await db.createRecord('expenses', payload(), 'A');
    expect(created.expense_kind).toBe('salary_installment');
    const updated = await db.updateRecord('expenses', 'kind-expense',
      { description: 'تصحيح وصف بلا كلمات تصنيف', expense_kind: null }, '{"A":2}', 'A');
    expect(updated.expense_kind).toBe('salary_installment');
    const page = await db.pullChanges('expenses', created.updated_at);
    expect(page.changes[0].expense_kind).toBe('salary_installment');
    expect(page.changes[0].amount).toBe(100);
  });
  it('honors valid explicit kinds independently of descriptions', async () => {
    const row = await new Database(env.DB).createRecord('expenses', payload({
      expense_kind: 'salary_deduction', description: 'قسط سلفة',
    }), 'A');
    expect(row.expense_kind).toBe('salary_deduction');
  });
  it('rejects invalid push kinds without storing the record', async () => {
    const res = await pushOperations(await adminAuthHeader(), [pushOp('expenses', 'create', payload({ expense_kind: 'free text' }))]);
    const body = await res.json() as { results: { status: string }[] };
    expect(body.results[0].status).toBe('validation_error');
    expect(await env.DB.prepare('SELECT * FROM expenses').all()).toMatchObject({ results: [] });
    expect(() => expenseKind(42, {})).toThrow('Invalid expense_kind');
  });
  it('migrates an old table additively, preserving money and cursor without guessing backfill', async () => {
    await env.DB.prepare('DROP TABLE expenses').run();
    await env.DB.prepare('CREATE TABLE expenses(id INTEGER PRIMARY KEY, amount REAL, updated_at INTEGER)').run();
    await env.DB.prepare('INSERT INTO expenses VALUES (7, 125.5, 999)').run();
    await env.DB.prepare(migration.replace(/--[^\n]*/g, '').trim()).run();
    expect(await env.DB.prepare('SELECT * FROM expenses').first()).toEqual({ id: 7, amount: 125.5, updated_at: 999, expense_kind: null });
  });
  it('does not silently drop kind if D1 migration is missing', async () => {
    await env.DB.prepare('ALTER TABLE expenses DROP COLUMN expense_kind').run();
    await expect(new Database(env.DB).createRecord('expenses', payload(), 'A')).rejects.toThrow('0015');
    expect((await env.DB.prepare('SELECT * FROM expenses').all()).results).toEqual([]);
  });
});
