// ═══════════════════════════════════════════════════════════════
//  sync.push.identity_links.test.ts — هوية موحّدة للأبناء الماليين
//
//  تثبيت عقد 2026-11-23: الأبناء (payments / debts / expenses) يحملون
//  هوية الأب العالمية (booking_uuid_cache / employee_uuid)، والخادم
//  يترجم الرابط الرقمي منها إلى معرّف الأب الخادمي — لا يُخزَّن رقم
//  جهاز المرسل، فلا تُقرأ الدفعة/الدين/المصروف على أب آخر بجهاز ثانٍ.
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  adminAuthHeader,
  pushOp,
  pushOperations,
  resetDb,
  uniqueUuid,
  type PushResponseBody,
} from './helpers';

beforeEach(async () => {
  await resetDb();
});

async function pushOne(
  auth: string,
  entity: string,
  data: Record<string, unknown>
): Promise<PushResponseBody> {
  const res = await pushOperations(auth, [pushOp(entity, 'create', data)]);
  return (await res.json()) as PushResponseBody;
}

async function createBooking(auth: string): Promise<{ uuid: string; serverId: number }> {
  const payload = {
    local_uuid: uniqueUuid('booking'),
    room_number: `I${Math.floor(Math.random() * 1_000_000)}`,
    guest_name: 'ضيف هوية',
    guest_phone: '0500000001',
    guest_nationality: 'يمني',
    checkin_date: '2026-11-20T14:00:00.000Z',
    checkout_date: '2026-11-23T12:00:00.000Z',
    status: 'active',
    created_at: 1700000000,
    updated_at: 1700000000,
    last_modified: 1700000000,
    version: 1,
    origin: 'local',
    vector_clock: '{}',
    device_id: 'device-A',
  };
  const body = await pushOne(auth, 'bookings', payload);
  expect(body.summary.success).toBe(1);
  const row = await env.DB.prepare(
    'SELECT id FROM bookings WHERE local_uuid = ?'
  )
    .bind(payload.local_uuid)
    .first<{ id: number }>();
  return { uuid: payload.local_uuid as string, serverId: row!.id };
}

async function createEmployee(auth: string): Promise<{ uuid: string; serverId: number }> {
  const payload = {
    local_uuid: uniqueUuid('employee'),
    name: 'موظف هوية',
    basic_salary: 500,
    status: 'active',
    created_at: 1700000000,
    updated_at: 1700000000,
    last_modified: 1700000000,
    version: 1,
    origin: 'local',
    vector_clock: '{}',
    device_id: 'device-A',
  };
  const body = await pushOne(auth, 'employees', payload);
  expect(body.summary.success).toBe(1);
  const row = await env.DB.prepare(
    'SELECT id FROM employees WHERE local_uuid = ?'
  )
    .bind(payload.local_uuid)
    .first<{ id: number }>();
  return { uuid: payload.local_uuid as string, serverId: row!.id };
}

describe('identity links: payments/debts/expenses resolve their parent globally', () => {
  it('links a payment to the server booking id taken from booking_uuid_cache', async () => {
    const auth = await adminAuthHeader();
    const booking = await createBooking(auth);

    const payment = {
      local_uuid: uniqueUuid('pay'),
      amount: 150,
      payment_date: '2026-11-21',
      payment_method: 'cash',
      revenue_type: 'room',
      // رقم جهاز آخر: يجب ألا يُحفظ كما هو
      booking_local_id: 999,
      booking_uuid_cache: booking.uuid,
      created_at: 1700000000,
      updated_at: 1700000000,
      last_modified: 1700000000,
      version: 1,
      vector_clock: '{}',
      device_id: 'device-A',
    };
    const body = await pushOne(auth, 'payments', payment);
    expect(body.summary.success).toBe(1);

    const row = await env.DB.prepare(
      'SELECT booking_local_id, server_booking_id, booking_uuid_cache FROM payments WHERE local_uuid = ?'
    )
      .bind(payment.local_uuid)
      .first<{
        booking_local_id: number | null;
        server_booking_id: number | null;
        booking_uuid_cache: string | null;
      }>();

    expect(row?.booking_local_id).toBe(booking.serverId);
    expect(row?.server_booking_id).toBe(booking.serverId);
    expect(row?.booking_uuid_cache).toBe(booking.uuid);
  });

  it('links a debt to the server booking id taken from booking_uuid_cache', async () => {
    const auth = await adminAuthHeader();
    const booking = await createBooking(auth);

    const debt = {
      local_uuid: uniqueUuid('debt'),
      guest_name: 'مدين هوية',
      checkin_date: '2026-11-20T14:00:00.000Z',
      checkout_date: '2026-11-22T12:00:00.000Z',
      total_amount: 300,
      paid_amount: 0,
      remaining_amount: 300,
      payment_date: '2026-11-22',
      booking_local_id: 999,
      booking_uuid_cache: booking.uuid,
      guest_phone: '0500000002',
      description: 'دين إقامة',
      status: 'open',
      due_date: '2026-11-25',
      created_at: 1700000000,
      updated_at: 1700000000,
      last_modified: 1700000000,
      version: 1,
      vector_clock: '{}',
      device_id: 'device-A',
    };
    const body = await pushOne(auth, 'debts', debt);
    expect(body.summary.success).toBe(1);

    const row = await env.DB.prepare(
      'SELECT booking_local_id, booking_uuid_cache, guest_phone, description, status, due_date FROM debts WHERE local_uuid = ?'
    )
      .bind(debt.local_uuid)
      .first<Record<string, unknown>>();

    expect(row?.booking_local_id).toBe(booking.serverId);
    expect(row?.booking_uuid_cache).toBe(booking.uuid);
    // الحقول الأربعة كانت تُسقَط عند الرفع (adapter لا يُرسلها)
    expect(row?.guest_phone).toBe('0500000002');
    expect(row?.description).toBe('دين إقامة');
    expect(row?.status).toBe('open');
    expect(row?.due_date).toBe('2026-11-25');
  });

  it('links an expense to the server employee id taken from employee_uuid', async () => {
    const auth = await adminAuthHeader();
    const employee = await createEmployee(auth);

    const expense = {
      local_uuid: uniqueUuid('expense'),
      expense_type: 'salary',
      description: 'مصروف مرتب',
      amount: 500,
      date: '2026-11-22',
      related_id: 999,
      employee_uuid: employee.uuid,
      created_at: 1700000000,
      updated_at: 1700000000,
      last_modified: 1700000000,
      version: 1,
      vector_clock: '{}',
      device_id: 'device-A',
    };
    const body = await pushOne(auth, 'expenses', expense);
    expect(body.summary.success).toBe(1);

    const row = await env.DB.prepare(
      'SELECT related_id, employee_uuid FROM expenses WHERE local_uuid = ?'
    )
      .bind(expense.local_uuid)
      .first<{ related_id: number | null; employee_uuid: string | null }>();

    expect(row?.related_id).toBe(employee.serverId);
    expect(row?.employee_uuid).toBe(employee.uuid);
  });

  it('keeps a booking-less payment intact (no invented link)', async () => {
    const auth = await adminAuthHeader();
    const payment = {
      local_uuid: uniqueUuid('pay'),
      amount: 75,
      payment_date: '2026-11-22',
      payment_method: 'cash',
      revenue_type: 'other',
      created_at: 1700000000,
      updated_at: 1700000000,
      last_modified: 1700000000,
      version: 1,
      vector_clock: '{}',
      device_id: 'device-A',
    };
    const body = await pushOne(auth, 'payments', payment);
    expect(body.summary.success).toBe(1);

    const row = await env.DB.prepare(
      'SELECT amount, booking_local_id, booking_uuid_cache FROM payments WHERE local_uuid = ?'
    )
      .bind(payment.local_uuid)
      .first<Record<string, unknown>>();
    expect(row?.amount).toBe(75);
    expect(row?.booking_local_id).toBeNull();
    expect(row?.booking_uuid_cache).toBeNull();
  });
});
