// ═══════════════════════════════════════════════════════════════
//  sync.withdrawals.employee_uuid.test.ts — 2026-09-10
//  «107 سجل محجوب: أب غير محلول» — عقد employee_uuid
//
//  الجذر: حمولات salary_withdrawals كانت تحمل employee_id رقمياً
//  فقط (id محلي على جهاز المصدر) — لا يحل عبر الأجهزة لأن:
//  1. server_id على D1 عمود هجرة فقط (createRecord يجبره null)
//  2. echo-filter يمنع عودة صف الأب لجهاز مصدره
//
//  العقد هنا: employee_uuid يمر عبر create/update ويُعاد في pull،
//  ويُحفظ حتى مع تحديثات لاحقة لا تحمل المفتاح (update لا يمسحه).
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  resetDb,
  adminAuthHeader,
  pull,
  pushOperations,
  uniqueUuid,
  type PullResponseBody,
  type PushResponseBody,
} from './helpers';

beforeEach(async () => {
  await resetDb();
});

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
    employee_id: 5,
    employee_uuid: '218da267-a3b3-4c40-ab96-a25101a8f161',
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

async function push(
  operations: unknown[]
): Promise<PushResponseBody> {
  const res = await pushOperations(await adminAuthHeader(), operations);
  expect(res.status).toBe(200);
  return (await res.json()) as PushResponseBody;
}

describe('salary_withdrawals employee_uuid — عقد المرجع المستقر للأب', () => {
  it('create يحفظ employee_uuid وpull يعيده للأجهزة الأخرى', async () => {
    const wd = withdrawalPayload();
    const result = await push([
      {
        idempotencyKey: uniqueUuid('idem'),
        entity: 'salary_withdrawals',
        operation: 'create',
        data: wd,
        vectorClock: '{}',
        updatedAt: 1700000001,
        deviceId: 'device-A',
      },
    ]);
    expect(result.summary.failed).toBe(0);

    const page = await pull(await adminAuthHeader(), {
      entity: 'salary_withdrawals',
      device_id: 'device-B',
    });
    const row = page.changes.find(
      (c) => c.local_uuid === wd.local_uuid
    );
    expect(row).toBeDefined();
    expect(row!['employee_uuid']).toBe(
      '218da267-a3b3-4c40-ab96-a25101a8f161'
    );
    // الرقمي يبقى كما هو (دلالة جهاز المصدر محفوظة)
    expect(row!['employee_id']).toBe(5);
  });

  it('update بلا employee_uuid لا يمسح المرجع الموجود', async () => {
    const wd = withdrawalPayload();
    await push([
      {
        idempotencyKey: uniqueUuid('idem'),
        entity: 'salary_withdrawals',
        operation: 'create',
        data: wd,
        vectorClock: '{}',
        updatedAt: 1700000001,
        deviceId: 'device-A',
      },
    ]);

    // تحديث لاحق رقيق (soft-delete) يحمل employee_id فقط
    // ⚠️ updatedAt المستقبلية ضرورية: server clock أحدث من 1.7e9
    // وLWW يرفض (بصواب) أي طابع أقدم من allocated للإنشاء
    await push([
      {
        idempotencyKey: uniqueUuid('idem'),
        entity: 'salary_withdrawals',
        operation: 'update',
        data: {
          local_uuid: wd.local_uuid,
          employee_id: 5,
          deleted_at: 2000000100,
          last_modified: 2000000100,
        },
        vectorClock: '{}',
        updatedAt: 2000000100,
        deviceId: 'device-A',
      },
    ]);

    const page = await pull(await adminAuthHeader(), {
      entity: 'salary_withdrawals',
      device_id: 'device-B',
    });
    const row = page.changes.find(
      (c) => c.local_uuid === wd.local_uuid
    );
    expect(row).toBeDefined();
    expect(row!['employee_uuid']).toBe(
      '218da267-a3b3-4c40-ab96-a25101a8f161'
    );
    expect(row!['deleted_at']).toBe(2000000100);
  });

  it('create بلا employee_uuid (سجل قديم) يُقبل — العمود يبقى null', async () => {
    const wd = withdrawalPayload({ employee_uuid: undefined });
    const result = await push([
      {
        idempotencyKey: uniqueUuid('idem'),
        entity: 'salary_withdrawals',
        operation: 'create',
        data: wd,
        vectorClock: '{}',
        updatedAt: 1700000001,
        deviceId: 'device-A',
      },
    ]);
    expect(result.summary.failed).toBe(0);

    const stored = await env.DB.prepare(
      'SELECT employee_uuid FROM salary_withdrawals WHERE local_uuid = ?'
    )
      .bind(wd.local_uuid)
      .first<{ employee_uuid: string | null }>();
    expect(stored?.employee_uuid).toBeNull();
  });
});
