// ═══════════════════════════════════════════════════════════════
//  sync.employee-delete-guard.test.ts — 2026-09-21
//  «لفصل موظف استخدم «إنهاء الخدمة» من التطبيق (تغيّر الحالة فقط) —
//  أما الحذف فيتيّم تاريخه المالي على بقية الأجهزة»
//
//  حارس push يرفض (validation_error دائم) أي tombstone لموظف يشير
//  إليه تاريخ مالي — الجذر: حذف ستة موظفين خادمياً في 2026-09 علّق
//  299 سحباً حياً على الأجهزة الجديدة (tombstone الأب يُسلَّم no-op
//  فلا يُبنى ظل server_id فتؤجَّل أبناؤه للأبد).
//
//  عقد الربط: employee_uuid أولاً (dash-insensitive) ثم المسك الرقمي
//  سقوطاً للصفوف عديمة uuid — نفس عقد ai.ts. tombstones تُحتسب
//  (التاريخ المحذوف قابل للإحياء). موظف بلا تاريخ يُحذف بحرية.
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  resetDb,
  adminAuthHeader,
  pushOp,
  pushOperations,
  uniqueUuid,
  type PushResponseBody,
  type PushResultItem,
} from './helpers';

interface GuardResult extends PushResultItem {
  status?: 'validation_error' | 'conflict' | 'internal_error';
}

beforeEach(async () => {
  await resetDb();
});

// ─── Payload builders ─────────────────────────────────────────

function employeePayload(overrides: Record<string, unknown> = {}) {
  return {
    local_uuid: uniqueUuid('emp'),
    name: 'عمار الدبادي',
    basic_salary: 500,
    position: 'موظف',
    phone: '',
    hire_date: '2026-01-01',
    status: 'active',
    created_at: 1700000000,
    updated_at: 1700000000,
    last_modified: 1700000000,
    version: 1,
    origin: 'local',
    vector_clock: '{}',
    device_id: 'device-A',
    ...overrides,
  };
}

function withdrawalPayload(overrides: Record<string, unknown> = {}) {
  return {
    local_uuid: uniqueUuid('wd'),
    // رقمي جهاز المصدر — دلالة محلية لا تحل عبر الأجهزة (عقد 0006)
    employee_id: 999,
    employee_uuid: null,
    amount: 100,
    withdraw_date: '2026-09-10',
    created_at: 1700000001,
    updated_at: 1700000001,
    last_modified: 1700000001,
    version: 1,
    origin: 'local',
    vector_clock: '{}',
    device_id: 'device-A',
    ...overrides,
  };
}

function cyclePayload(overrides: Record<string, unknown> = {}) {
  return {
    local_uuid: uniqueUuid('cyc'),
    employee_id: 999,
    employee_uuid: null,
    cycle_key: '2026-09',
    status: 'draft',
    created_at: 1700000001,
    updated_at: 1700000001,
    last_modified: 1700000001,
    version: 1,
    origin: 'local',
    vector_clock: '{}',
    device_id: 'device-A',
    ...overrides,
  };
}

function paymentPayload(overrides: Record<string, unknown> = {}) {
  return {
    local_uuid: uniqueUuid('pay'),
    cycle_id: 1,
    employee_uuid: null,
    amount: 100,
    payment_date_iso: '2026-09-10',
    created_at: 1700000001,
    updated_at: 1700000001,
    last_modified: 1700000001,
    version: 1,
    origin: 'local',
    vector_clock: '{}',
    device_id: 'device-A',
    ...overrides,
  };
}

function carryOverPayload(overrides: Record<string, unknown> = {}) {
  return {
    local_uuid: uniqueUuid('cko'),
    employee_id: 999,
    amount: 50,
    previous_cycle_start: '2026-08-01',
    previous_cycle_end: '2026-08-31',
    new_cycle_start: '2026-09-01',
    new_cycle_end: '2026-09-30',
    reason: 'ترحيل اختبار',
    carried_at: 1700000001,
    created_at: 1700000001,
    updated_at: 1700000001,
    last_modified: 1700000001,
    version: 1,
    origin: 'local',
    vector_clock: '{}',
    device_id: 'device-A',
    ...overrides,
  };
}

function expensePayload(overrides: Record<string, unknown> = {}) {
  return {
    local_uuid: uniqueUuid('exp'),
    expense_type: 'سحب راتب',
    related_id: null,
    employee_uuid: null,
    description: 'سحب راتب اختبار',
    amount: 100,
    date: '2026-09-10',
    created_at: 1700000001,
    updated_at: 1700000001,
    last_modified: 1700000001,
    version: 1,
    origin: 'local',
    vector_clock: '{}',
    device_id: 'device-A',
    ...overrides,
  };
}

// ─── Helpers ──────────────────────────────────────────────────

async function push(operations: unknown[]): Promise<PushResponseBody> {
  const res = await pushOperations(await adminAuthHeader(), operations);
  expect(res.status).toBe(200);
  return (await res.json()) as PushResponseBody;
}

async function createEmployee(): Promise<string> {
  const emp = employeePayload();
  const body = await push([pushOp('employees', 'create', emp)]);
  expect(body.summary.failed).toBe(0);
  return emp.local_uuid as string;
}

async function d1EmployeeId(localUuid: string): Promise<number> {
  const row = await env.DB.prepare(
    'SELECT id FROM employees WHERE local_uuid = ?'
  )
    .bind(localUuid)
    .first<{ id: number }>();
  expect(row).not.toBeNull();
  return row!.id;
}

async function attemptDeleteEmployee(
  localUuid: string
): Promise<GuardResult> {
  const body = await push([
    pushOp('employees', 'delete', { local_uuid: localUuid }),
  ]);
  return body.results[0] as GuardResult;
}

async function expectEmployeeLive(localUuid: string): Promise<void> {
  const row = await env.DB.prepare(
    'SELECT deleted_at FROM employees WHERE local_uuid = ?'
  )
    .bind(localUuid)
    .first<{ deleted_at: number | null }>();
  expect(row).not.toBeNull();
  expect(row!.deleted_at).toBeNull();
}

// ─── Tests ────────────────────────────────────────────────────

describe('حارس حذف الموظفين — «الحذف يتيّم التاريخ المالي»', () => {
  it('يرفض حذف موظف له سحوبات مرتبطة عبر employee_uuid (رفض دائم)', async () => {
    const empUuid = await createEmployee();
    await push([
      pushOp('salary_withdrawals', 'create', withdrawalPayload({
        employee_uuid: empUuid,
      })),
    ]);

    const result = await attemptDeleteEmployee(empUuid);
    expect(result.success).toBe(false);
    expect(result.status).toBe('validation_error');
    expect(result.error).toContain('إنهاء الخدمة');
    await expectEmployeeLive(empUuid);
  });

  it('يرفض الحذف عبر الشكل غير الشرطي للـ uuid (dashless)', async () => {
    const empUuid = await createEmployee();
    await push([
      pushOp('salary_withdrawals', 'create', withdrawalPayload({
        employee_uuid: empUuid.replace(/-/g, ''),
      })),
    ]);

    const result = await attemptDeleteEmployee(empUuid);
    expect(result.success).toBe(false);
    expect(result.status).toBe('validation_error');
    await expectEmployeeLive(empUuid);
  });

  it('يرفض الحذف عبر المسك الرقمي القديم (employee_id = e.id بلا uuid)', async () => {
    const empUuid = await createEmployee();
    const empId = await d1EmployeeId(empUuid);
    await push([
      pushOp('salary_withdrawals', 'create', withdrawalPayload({
        employee_id: empId,
        employee_uuid: null,
      })),
    ]);

    const result = await attemptDeleteEmployee(empUuid);
    expect(result.success).toBe(false);
    expect(result.status).toBe('validation_error');
    await expectEmployeeLive(empUuid);
  });

  it('يرفض الحذف عند مصروف مرتبط عبر employee_uuid', async () => {
    const empUuid = await createEmployee();
    await push([
      pushOp('expenses', 'create', expensePayload({
        employee_uuid: empUuid,
        expense_type: 'سلفة',
      })),
    ]);

    const result = await attemptDeleteEmployee(empUuid);
    expect(result.success).toBe(false);
    expect(result.status).toBe('validation_error');
    await expectEmployeeLive(empUuid);
  });

  it('يرفض الحذف عند مصروف راتب قديم بمسك related_id رقمي', async () => {
    const empUuid = await createEmployee();
    const empId = await d1EmployeeId(empUuid);
    await push([
      pushOp('expenses', 'create', expensePayload({
        related_id: empId,
        employee_uuid: null,
        expense_type: 'سحب من الراتب',
      })),
    ]);

    const result = await attemptDeleteEmployee(empUuid);
    expect(result.success).toBe(false);
    await expectEmployeeLive(empUuid);
  });

  it('لا يحجب مصروف حجز عابر تطابق related_id رقميه معه (لا إيجابيات كاذبة)', async () => {
    const empUuid = await createEmployee();
    const empId = await d1EmployeeId(empUuid);
    // مصروف «حجز» غير مرتبط بالموظف — related_id متعدد الدلالة
    await push([
      pushOp('expenses', 'create', expensePayload({
        related_id: empId,
        employee_uuid: null,
        expense_type: 'حجز',
      })),
    ]);

    const result = await attemptDeleteEmployee(empUuid);
    expect(result.success).toBe(true);
  });

  it('يرفض الحذف عند دورات رواتب / مدفوعات / ترحيلات مرتبطة', async () => {
    // دورة عبر uuid
    const withCycle = await createEmployee();
    await push([
      pushOp('salary_cycles', 'create', cyclePayload({
        employee_uuid: withCycle,
      })),
    ]);
    expect((await attemptDeleteEmployee(withCycle)).success).toBe(false);
    await expectEmployeeLive(withCycle);

    // دورة عبر مسك رقمي قديم
    const withLegacyCycle = await createEmployee();
    const legacyId = await d1EmployeeId(withLegacyCycle);
    await push([
      pushOp('salary_cycles', 'create', cyclePayload({
        employee_id: legacyId,
        employee_uuid: null,
      })),
    ]);
    expect((await attemptDeleteEmployee(withLegacyCycle)).success).toBe(false);

    // مدفعة عبر employee_uuid (مرجعها الوحيد — مُستنبطة من الدورة)
    const withPayment = await createEmployee();
    await push([
      pushOp('salary_payments', 'create', paymentPayload({
        employee_uuid: withPayment,
      })),
    ]);
    expect((await attemptDeleteEmployee(withPayment)).success).toBe(false);

    // ترحيل عبر المسك الرقمي (لا تحمل employee_uuid أصلاً)
    const withCarryOver = await createEmployee();
    const carryId = await d1EmployeeId(withCarryOver);
    await push([
      pushOp('salary_carry_over_logs', 'create', carryOverPayload({
        employee_id: carryId,
      })),
    ]);
    expect((await attemptDeleteEmployee(withCarryOver)).success).toBe(false);
  });

  it('التاريخ المحذوف ناعماً (tombstone) يبقى حاجباً — قابل للإحياء', async () => {
    const empUuid = await createEmployee();
    const wd = withdrawalPayload({ employee_uuid: empUuid });
    await push([pushOp('salary_withdrawals', 'create', wd)]);

    // احذف السحب نفسه (tombstone) ثم حاول حذف الموظف
    const delWd = await push([
      pushOp('salary_withdrawals', 'delete', { local_uuid: wd.local_uuid }),
    ]);
    expect(delWd.summary.failed).toBe(0);

    const result = await attemptDeleteEmployee(empUuid);
    expect(result.success).toBe(false);
    expect(result.status).toBe('validation_error');
    await expectEmployeeLive(empUuid);
  });

  it('موظف بلا أي تاريخ مالي يُحذف بحرية (tombstone عادي)', async () => {
    const empUuid = await createEmployee();

    const result = await attemptDeleteEmployee(empUuid);
    expect(result.success).toBe(true);

    const row = await env.DB.prepare(
      'SELECT deleted_at FROM employees WHERE local_uuid = ?'
    )
      .bind(empUuid)
      .first<{ deleted_at: number | null }>();
    expect(row!.deleted_at).not.toBeNull();
  });

  it('الرفض لا يستهلك مفتاح idempotency — إعادة المحاولة بنفس المفتاح تُقيَّم من جديد', async () => {
    const empUuid = await createEmployee();
    await push([
      pushOp('salary_withdrawals', 'create', withdrawalPayload({
        employee_uuid: empUuid,
      })),
    ]);

    const op = pushOp('employees', 'delete', { local_uuid: empUuid });
    const first = await push([op]);
    expect(first.results[0]!.success).toBe(false);

    // نفس المفتاح — لا skipped:true (لم يُحفظ إيديمبوتنسي للرفض)
    const second = await push([op]);
    expect(second.results[0]!.success).toBe(false);
    expect(second.results[0]!.skipped).toBeUndefined();
    await expectEmployeeLive(empUuid);
  });
});
