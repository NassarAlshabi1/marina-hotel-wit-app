// Regression coverage for the employee relationship on employee expenses.
import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  adminAuthHeader,
  pull,
  pushOp,
  pushOperations,
  resetDb,
  uniqueUuid,
  type PushResponseBody,
} from './helpers';

beforeEach(async () => {
  await resetDb();
});

async function push(auth: string, operations: unknown[]): Promise<PushResponseBody> {
  const response = await pushOperations(auth, operations);
  expect(response.status).toBe(200);
  return (await response.json()) as PushResponseBody;
}

async function createEmployee(auth: string) {
  const employee = {
    local_uuid: uniqueUuid('employee'),
    name: 'Employee Link Test',
    basic_salary: 100_000,
    position: 'Staff',
    hire_date: '2026-01-01',
    status: 'active',
    created_at: 1_700_000_000,
    updated_at: 1_700_000_000,
    last_modified: 1_700_000_000,
  };
  const result = await push(auth, [pushOp('employees', 'create', employee)]);
  expect(result.summary.failed).toBe(0);
  const stored = await env.DB.prepare(
    'SELECT id, local_uuid FROM employees WHERE local_uuid = ?',
  )
    .bind(employee.local_uuid)
    .first<{ id: number; local_uuid: string }>();
  expect(stored).not.toBeNull();
  return { employee, stored: stored! };
}

describe('push: employee expense relationship safety', () => {
  it('stores UUID-backed links with canonical IDs and only clears on explicit unlink', async () => {
    const auth = await adminAuthHeader();
    const { employee, stored: parent } = await createEmployee(auth);
    const expense = {
      local_uuid: uniqueUuid('salary-expense'),
      expense_type: 'سلفة',
      related_id: 7_777, // device-local and deliberately wrong
      employee_uuid: employee.local_uuid,
      description: 'Employee advance',
      amount: 5_000,
      date: '2026-10-03',
      created_at: 1_700_000_001,
      updated_at: 1_700_000_001,
      last_modified: 1_700_000_001,
    };
    const created = await push(auth, [pushOp('expenses', 'create', expense)]);
    expect(created.summary.failed).toBe(0);

    let stored = await env.DB.prepare(
      'SELECT related_id, employee_uuid, employee_link_cleared FROM expenses WHERE local_uuid = ?',
    )
      .bind(expense.local_uuid)
      .first<{ related_id: number | null; employee_uuid: string | null; employee_link_cleared: number }>();
    expect(stored?.related_id).toBe(parent.id);
    expect(stored?.employee_uuid).toBe(employee.local_uuid);
    expect(stored?.employee_link_cleared).toBe(0);

    const ordinaryNullUpdate = await push(auth, [
      pushOp(
        'expenses',
        'update',
        {
          local_uuid: expense.local_uuid,
          expense_type: 'سلفة',
          related_id: null,
          employee_uuid: null,
          description: 'Business fields changed, relation omitted',
          amount: 5_500,
          date: '2026-10-03',
        },
        { vectorClock: '{"device-A":2}', updatedAt: 2_000_000_100 },
      ),
    ]);
    expect(ordinaryNullUpdate.summary.failed).toBe(0);
    stored = await env.DB.prepare(
      'SELECT related_id, employee_uuid, employee_link_cleared FROM expenses WHERE local_uuid = ?',
    )
      .bind(expense.local_uuid)
      .first<{ related_id: number | null; employee_uuid: string | null; employee_link_cleared: number }>();
    expect(stored?.related_id).toBe(parent.id);
    expect(stored?.employee_uuid).toBe(employee.local_uuid);
    expect(stored?.employee_link_cleared).toBe(0);

    const explicitUnlink = await push(auth, [
      pushOp(
        'expenses',
        'update',
        {
          local_uuid: expense.local_uuid,
          expense_type: 'سلفة',
          related_id: null,
          employee_uuid: null,
          clear_employee_link: true,
          description: 'Explicitly unlinked',
          amount: 5_500,
          date: '2026-10-03',
        },
        { vectorClock: '{"device-A":3}', updatedAt: 2_000_000_200 },
      ),
    ]);
    expect(explicitUnlink.summary.failed).toBe(0);
    stored = await env.DB.prepare(
      'SELECT related_id, employee_uuid, employee_link_cleared FROM expenses WHERE local_uuid = ?',
    )
      .bind(expense.local_uuid)
      .first<{ related_id: number | null; employee_uuid: string | null; employee_link_cleared: number }>();
    expect(stored?.related_id).toBeNull();
    expect(stored?.employee_uuid).toBeNull();
    expect(stored?.employee_link_cleared).toBe(1);

    const pulled = await pull(auth, { entity: 'expenses', device_id: 'device-B' });
    const returned = pulled.changes.find((item) => item.local_uuid === expense.local_uuid);
    expect(returned?.employee_link_cleared).toBe(1);
    expect(returned?.employee_uuid).toBeNull();
    expect(returned?.related_id).toBeNull();
  });

  it('never persists a raw related_id when a salary expense UUID is unresolved', async () => {
    const auth = await adminAuthHeader();
    const expense = {
      local_uuid: uniqueUuid('orphan-salary-expense'),
      expense_type: 'سلفة',
      related_id: 9_999,
      employee_uuid: uniqueUuid('employee-not-yet-pushed'),
      description: 'Pending employee',
      amount: 3_000,
      date: '2026-10-03',
    };
    const result = await push(auth, [pushOp('expenses', 'create', expense)]);
    expect(result.summary.failed).toBe(0);

    const stored = await env.DB.prepare(
      'SELECT related_id, employee_uuid FROM expenses WHERE local_uuid = ?',
    )
      .bind(expense.local_uuid)
      .first<{ related_id: number | null; employee_uuid: string | null }>();
    expect(stored?.related_id).toBeNull();
    expect(stored?.employee_uuid).toBe(expense.employee_uuid);
  });
});
