import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { Database } from '../src/database';
import { expenseKind, legacyExpenseKind } from '../src/expense-kind';
import { adminAuthHeader, pushOp, pushOperations, resetDb } from './helpers';

// Parity unification: ports branch3 worker/test/expense-kind.test.ts.
// B2 already creates `salary_withdrawals.expense_uuid` in 0011
// (portable_financial_relationships) so the migration under test is
// `0015_expense_kind.sql` (the additive kind column) — same as B3.

beforeEach(resetDb);
const payload = (extra: Record<string, unknown> = {}) => ({
  local_uuid: 'kind-expense', expense_type: 'خصم من الراتب', description: 'قسط سلفة شهر أكتوبر',
  amount: 100, date: '2026-10-01', is_auto_generated: 1, ...extra,
});
describe('expense_kind stable wire contract (B2 parity port)', () => {
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
  it('translates legacy clear_employee_link=1 into employee_link_cleared=1 + null employee_uuid', async () => {
    const db = new Database(env.DB);
    await db.createRecord('employees', {
      local_uuid: 'emp-1', name: 'ali', basic_salary: 1000, position: 'موظف',
      hire_date: '2026-01-01', status: 'active',
    }, 'A');
    const exp = await db.createRecord('expenses', payload({
      employee_uuid: 'emp-1', expense_kind: 'salary_withdrawal',
    }), 'A');
    expect(exp.employee_link_cleared).toBe(0);
    const cleared = await db.updateRecord('expenses', 'kind-expense',
      { clear_employee_link: 1, description: 'unlinked' }, '{"A":2}', 'A');
    expect(cleared.employee_link_cleared).toBe(1);
    expect(cleared.employee_uuid).toBeNull();
  });
  it('migrates an old table additively, preserving money and cursor without guessing backfill', async () => {
    await env.DB.prepare('DROP TABLE expenses').run();
    await env.DB.prepare('CREATE TABLE expenses(id INTEGER PRIMARY KEY, amount REAL, updated_at INTEGER)').run();
    await env.DB.prepare('INSERT INTO expenses VALUES (7, 125.5, 999)').run();
    const migration = `ALTER TABLE expenses ADD COLUMN expense_kind TEXT
      CHECK (expense_kind IS NULL OR expense_kind IN (
        'normal','salary_advance','salary_installment','salary_withdrawal',
        'salary_deduction','unclassified'
      ))`;
    await env.DB.prepare(migration).run();
    expect(await env.DB.prepare('SELECT * FROM expenses').first()).toEqual({ id: 7, amount: 125.5, updated_at: 999, expense_kind: null });
  });
});
