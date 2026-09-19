// ═══════════════════════════════════════════════════════════════
//  ai.test.ts — hermetic coverage for the natural-language endpoint
//
//  The Workers AI binding is mocked in-process (handleAiRequest takes
//  env as a parameter), so tests exercise the allow-listed SQL, the
//  two-step write confirmation, the role guard and every validation
//  branch without any network access or Cloudflare credentials.
// ═══════════════════════════════════════════════════════════════

import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { handleAiRequest, type AiBinding } from '../src/ai';
import { resetDb, uniqueUuid } from './helpers';

beforeEach(async () => {
  await resetDb();
});

function mockAi(plan: unknown): AiBinding {
  return {
    async run(_model: string, _input: unknown) {
      // Real Workers AI returns { response: "<string>" } for text models.
      return { response: JSON.stringify(plan) };
    },
  };
}

function garbageAi(): AiBinding {
  return {
    async run() {
      return { response: 'عذراً لا أستطيع إرجاع JSON' };
    },
  };
}

function aiRequest(body: unknown): Request {
  return new Request('https://example.com/api/ai/query', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

const seedRoom = (uuid: string, number: string, status: string, deleted = false) =>
  env.DB.prepare(
    `INSERT INTO rooms (local_uuid, room_number, type, price, status, created_at, updated_at, last_modified, deleted_at)
     VALUES (?,?,?,?,?,?,?,0,?)`,
  ).bind(uuid, number, 'double', 80, status, 1700000000, 1700000000, deleted ? 1700000001 : null).run();

const seedBooking = (uuid: string, room: string, guest: string, status: string, deleted = false) =>
  env.DB.prepare(
    `INSERT INTO bookings (local_uuid, room_number, guest_name, guest_phone, guest_nationality, checkin_date, checkout_date, status, created_at, updated_at, last_modified, deleted_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,0,?)`,
  ).bind(uuid, room, guest, '777000', 'يمني', '2026-09-15', '2026-09-18', status, 1700000000, 1700000000, deleted ? 1700000001 : null).run();

async function seedEmployee(name: string, basicSalary: number): Promise<number> {
  const result = await env.DB.prepare(
    `INSERT INTO employees (name, basic_salary, status, local_uuid, created_at, updated_at, last_modified)
     VALUES (?,?,?,?,?,?,0)`,
  ).bind(name, basicSalary, 'active', uniqueUuid('emp'), 1700000000, 1700000000).run();
  return result.meta.last_row_id as number;
}

const seedWithdrawal = (employeeId: number, amount: number, date: string) =>
  env.DB.prepare(
    `INSERT INTO salary_withdrawals (employee_id, amount, withdraw_date, local_uuid, created_at, updated_at, last_modified)
     VALUES (?,?,?,?,?,?,0)`,
  ).bind(employeeId, amount, date, uniqueUuid('wd'), 1700000000, 1700000000).run();

const seedExpense = (uuid: string, type: string, amount: number, date: string, deleted = false) =>
  env.DB.prepare(
    `INSERT INTO expenses (expense_type, description, amount, date, local_uuid, created_at, updated_at, last_modified, deleted_at)
     VALUES (?,?,?,?,?,?,?,0,?)`,
  ).bind(type, 'بند', amount, date, uuid, 1700000000, 1700000000, deleted ? 1700000001 : null).run();

async function expenseCount(): Promise<number> {
  const row = await env.DB.prepare('SELECT COUNT(*) AS c FROM expenses').first<{ c: number }>();
  return row?.c ?? 0;
}

describe('ai: query flow (read-only)', () => {
  it('rooms_available returns only vacant, non-deleted rooms', async () => {
    await seedRoom(uniqueUuid('r1'), '101', 'available');
    await seedRoom(uniqueUuid('r2'), '102', 'available');
    await seedRoom(uniqueUuid('r3'), '103', 'occupied');
    await seedRoom(uniqueUuid('r4'), '104', 'available', true);

    const res = await handleAiRequest(
      aiRequest({ prompt: 'كم غرفة شاغرة؟' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', queryType: 'rooms_available', explanation: 'الغرف الشاغرة' }) },
      'employee',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { rows: Array<{ room_number: string }>; requires_confirmation: boolean; answer: string };
    expect(body.rows.map((r) => r.room_number)).toEqual(['101', '102']);
    expect(body.requires_confirmation).toBe(false);
    expect(body.answer).toBe('الغرف الشاغرة');
    expect(await expenseCount()).toBe(0);
  });

  it('guest_search matches by partial name and ignores deleted bookings', async () => {
    await seedBooking(uniqueUuid('b1'), '201', 'أحمد سالم', 'active');
    await seedBooking(uniqueUuid('b2'), '202', 'سالم ناصر', 'active');
    await seedBooking(uniqueUuid('b3'), '203', 'أحمد صالح', 'active', true);

    const res = await handleAiRequest(
      aiRequest({ prompt: 'ابحث عن النزيل أحمد' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', queryType: 'guest_search', guestName: 'أحمد', explanation: 'نتائج البحث' }) },
      'employee',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { rows: Array<{ guest_name: string }> };
    expect(body.rows).toHaveLength(1);
    expect(body.rows[0]?.guest_name).toBe('أحمد سالم');
  });

  it('employee_salary derives remaining salary from withdrawals', async () => {
    const employeeId = await seedEmployee('عمر حسن', 100000);
    await seedWithdrawal(employeeId, 30000, '2026-09-10');
    await seedWithdrawal(employeeId, 20000, '2026-09-15');

    const res = await handleAiRequest(
      aiRequest({ prompt: 'كم تبقى راتب عمر حسن؟' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', queryType: 'employee_salary', employeeName: 'عمر', explanation: 'الراتب' }) },
      'manager',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { rows: Array<{ name: string; total_withdrawn: number; estimated_remaining: number }> };
    expect(body.rows).toHaveLength(1);
    expect(body.rows[0]?.total_withdrawn).toBe(50000);
    expect(body.rows[0]?.estimated_remaining).toBe(50000);
  });

  it('expenses_total aggregates by type inside the requested window only', async () => {
    await seedExpense(uniqueUuid('e1'), 'وقود', 500, '2026-09-05');
    await seedExpense(uniqueUuid('e2'), 'وقود', 300, '2026-09-20');
    await seedExpense(uniqueUuid('e3'), 'صيانة', 1000, '2026-09-12');
    await seedExpense(uniqueUuid('e4'), 'خارج النطاق', 999, '2026-08-31');
    await seedExpense(uniqueUuid('e5'), 'محذوف', 777, '2026-09-13', true);

    const res = await handleAiRequest(
      aiRequest({ prompt: 'مصروفات سبتمبر' }),
      {
        DB: env.DB,
        AI: mockAi({ kind: 'query', queryType: 'expenses_total', dateFrom: '2026-09-01', dateTo: '2026-09-30', explanation: 'المصروفات' }),
      },
      'employee',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { rows: Array<{ expense_type: string; entries: number; total: number }> };
    const byType = new Map(body.rows.map((r) => [r.expense_type, r]));
    expect(byType.get('وقود')).toMatchObject({ entries: 2, total: 800 });
    expect(byType.get('صيانة')).toMatchObject({ entries: 1, total: 1000 });
    expect(byType.has('خارج النطاق')).toBe(false);
    expect(byType.has('محذوف')).toBe(false);
  });
});

describe('ai: add_expense (two-step write)', () => {
  const expensePlan = {
    kind: 'add_expense',
    expenseType: 'صيانة',
    description: 'إيجار المولد',
    amountPerDay: 40000,
    dateFrom: '2026-09-19',
    dateTo: '2026-09-21',
    explanation: 'إضافة مصروف يومي',
  };

  it('first pass asks for confirmation and writes nothing', async () => {
    const res = await handleAiRequest(
      aiRequest({ prompt: 'أضف مصروف 40 ألف لكل يوم من 19 إلى 21 سبتمبر' }),
      { DB: env.DB, AI: mockAi(expensePlan) },
      'admin',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { requires_confirmation: boolean; answer: string };
    expect(body.requires_confirmation).toBe(true);
    expect(body.answer).toContain('40000');
    expect(await expenseCount()).toBe(0);
  });

  it('confirmed plan inserts one row per day with ai origin', async () => {
    const res = await handleAiRequest(
      aiRequest({ plan: expensePlan, confirm: true }),
      { DB: env.DB, AI: mockAi(expensePlan) },
      'manager',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { answer: string };
    expect(body.answer).toContain('3');
    const rows = await env.DB.prepare(
      'SELECT expense_type, description, amount, date, hotel_day_key, is_auto_generated, origin, device_id FROM expenses ORDER BY date',
    ).all<{ expense_type: string; description: string; amount: number; date: string; hotel_day_key: string; is_auto_generated: number; origin: string; device_id: string }>();
    expect(rows.results).toHaveLength(3);
    expect(rows.results.map((r) => r.date)).toEqual(['2026-09-19', '2026-09-20', '2026-09-21']);
    for (const row of rows.results) {
      expect(row.expense_type).toBe('صيانة');
      expect(row.description).toBe('إيجار المولد');
      expect(row.amount).toBe(40000);
      expect(row.hotel_day_key).toBe(row.date);
      expect(row.is_auto_generated).toBe(0);
      expect(row.origin).toBe('ai');
      expect(row.device_id).toBe('worker');
    }
  });

  it('rejects roles below manager with 403 and no write', async () => {
    const res = await handleAiRequest(
      aiRequest({ plan: expensePlan, confirm: true }),
      { DB: env.DB, AI: mockAi(expensePlan) },
      'employee',
    );
    expect(res.status).toBe(403);
    expect(await expenseCount()).toBe(0);
  });
});

describe('ai: validation and failure modes', () => {
  it('empty prompt yields 400 without touching the model', async () => {
    const res = await handleAiRequest(aiRequest({ prompt: '   ' }), { DB: env.DB, AI: mockAi({}) }, 'admin');
    expect(res.status).toBe(400);
  });

  it('unsupported intent returns the explanation, not an error status', async () => {
    const res = await handleAiRequest(
      aiRequest({ prompt: 'احذف كل البيانات' }),
      { DB: env.DB, AI: mockAi({ kind: 'unsupported', explanation: 'لا يمكن تنفيذ هذا الطلب لأسباب أمنية' }) },
      'admin',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { answer: string; requires_confirmation: boolean };
    expect(body.requires_confirmation).toBe(false);
    expect(body.answer).toContain('لا يمكن');
  });

  it('query with unrecognized type asks for clarification', async () => {
    const res = await handleAiRequest(
      aiRequest({ prompt: 'شيء غير مفهوم' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', explanation: 'غير واضح' }) },
      'admin',
    );
    const body = (await res.json()) as { answer: string };
    expect(body.answer).toContain('لم أتعرف');
  });

  it('employee queries demand an employee name', async () => {
    const res = await handleAiRequest(
      aiRequest({ prompt: 'رواتب الموظفين' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', queryType: 'employee_withdrawals', explanation: 'x' }) },
      'admin',
    );
    const body = (await res.json()) as { answer: string };
    expect(body.answer).toContain('اسم الموظف');
  });

  it('add_expense with a non-positive amount is rejected before any write', async () => {
    const res = await handleAiRequest(
      aiRequest({ prompt: 'أضف مصروفاً بدون مبلغ' }),
      {
        DB: env.DB,
        AI: mockAi({ kind: 'add_expense', expenseType: 'وقود', description: 'بلا مبلغ', amountPerDay: 0, dateFrom: '2026-09-19', dateTo: '2026-09-19', explanation: 'e' }),
      },
      'admin',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { requires_confirmation: boolean; answer: string };
    expect(body.requires_confirmation).toBe(false);
    expect(body.answer).toContain('المبلغ');
    expect(await expenseCount()).toBe(0);
  });

  it('add_expense with an inverted date range is rejected', async () => {
    const res = await handleAiRequest(
      aiRequest({ prompt: 'أضف مصروفاً بتواريخ معكوسة' }),
      {
        DB: env.DB,
        AI: mockAi({ kind: 'add_expense', expenseType: 'وقود', description: 'معكوس', amountPerDay: 100, dateFrom: '2026-09-21', dateTo: '2026-09-19', explanation: 'e' }),
      },
      'admin',
    );
    const body = (await res.json()) as { requires_confirmation: boolean; answer: string };
    expect(body.requires_confirmation).toBe(false);
    expect(body.answer).toContain('التاريخ');
    expect(await expenseCount()).toBe(0);
  });

  it('malformed model output yields 502, never a crash', async () => {
    const res = await handleAiRequest(aiRequest({ prompt: 'أي شيء' }), { DB: env.DB, AI: garbageAi() }, 'admin');
    expect(res.status).toBe(502);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain('تحليل');
  });
});

// ═══════════════════════════════════════════════════════════════
//  Analytics (occupancy / bookings) + bilingual status regression
//  Production D1 holds the Arabic status forms ('شاغرة'/'محجوزة') —
//  every filter must accept both languages.
// ═══════════════════════════════════════════════════════════════

const today = new Date().toISOString().slice(0, 10);
const dayAt = (offset: number) => {
  const d = new Date(`${today}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + offset);
  return d.toISOString().slice(0, 10);
};

const seedStay = (uuid: string, room: string, guest: string, status: string, opts: { checkin: string; checkout?: string | null; nights: number; due: number; paid: number }) =>
  env.DB.prepare(
    `INSERT INTO bookings (local_uuid, room_number, guest_name, guest_phone, guest_nationality, checkin_date, checkout_date, status, calculated_nights, total_due_cached, total_paid_cached, remaining_balance_cached, created_at, updated_at, last_modified)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,0)`,
  ).bind(uuid, room, guest, '777000', 'يمني', opts.checkin, opts.checkout ?? null, status, opts.nights, opts.due, opts.paid, Math.max(opts.due - opts.paid, 0), 1700000000, 1700000000).run();

const seedPayment = (uuid: string, amount: number, paymentDate: string) =>
  env.DB.prepare(
    `INSERT INTO payments (local_uuid, amount, payment_date, payment_method, revenue_type, created_at, updated_at, last_modified)
     VALUES (?,?,?,?,?,?,?,0)`,
  ).bind(uuid, amount, paymentDate, 'نقدي', 'إيراد', 1700000000, 1700000000).run();

describe('ai: bilingual statuses (production regression)', () => {
  it('rooms_available matches both Arabic and English vacant statuses', async () => {
    await seedRoom(uniqueUuid('r1'), '101', 'شاغرة');
    await seedRoom(uniqueUuid('r2'), '102', 'available');
    await seedRoom(uniqueUuid('r3'), '103', 'محجوزة');
    await seedRoom(uniqueUuid('r4'), '104', 'occupied');

    const res = await handleAiRequest(
      aiRequest({ prompt: 'الغرف الشاغرة' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', queryType: 'rooms_available', explanation: 'x' }) },
      'employee',
    );
    const body = (await res.json()) as { rows: Array<{ room_number: string }> };
    expect(body.rows.map((r) => r.room_number)).toEqual(['101', '102']);
  });

  it('current_guests matches the Arabic active booking status', async () => {
    await seedStay(uniqueUuid('b1'), '201', 'سالم', 'محجوزة', { checkin: dayAt(-2), checkout: dayAt(3), nights: 5, due: 50000, paid: 20000 });
    await seedStay(uniqueUuid('b2'), '202', 'مكتمل ضيف', 'مكتمل', { checkin: dayAt(-10), checkout: dayAt(-5), nights: 5, due: 50000, paid: 50000 });

    const res = await handleAiRequest(
      aiRequest({ prompt: 'من النزلاء الموجودين؟' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', queryType: 'current_guests', explanation: 'x' }) },
      'employee',
    );
    const body = (await res.json()) as { rows: Array<{ guest_name: string }> };
    expect(body.rows).toHaveLength(1);
    expect(body.rows[0]?.guest_name).toBe('سالم');
  });
});

describe('ai: occupancy and booking analytics', () => {
  it('occupancy_summary reports totals, percentage and arrivals today', async () => {
    await seedRoom(uniqueUuid('r1'), '101', 'شاغرة');
    await seedRoom(uniqueUuid('r2'), '102', 'شاغرة');
    await seedRoom(uniqueUuid('r3'), '103', 'محجوزة');
    await seedRoom(uniqueUuid('r4'), '104', 'محجوزة');
    await seedRoom(uniqueUuid('r5'), '105', 'محجوزة', true); // deleted — excluded
    await seedStay(uniqueUuid('b1'), '103', 'نزيل قديم', 'محجوزة', { checkin: dayAt(-3), checkout: dayAt(2), nights: 5, due: 100, paid: 0 });
    await seedStay(uniqueUuid('b2'), '104', 'واصل اليوم', 'محجوزة', { checkin: today, checkout: dayAt(2), nights: 2, due: 100, paid: 0 });
    await seedStay(uniqueUuid('b3'), '105', 'ملغي', 'ملغي', { checkin: today, checkout: dayAt(2), nights: 2, due: 100, paid: 0 });

    const res = await handleAiRequest(
      aiRequest({ prompt: 'ما نسبة الإشغال الحالية؟' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', queryType: 'occupancy_summary', explanation: 'x' }) },
      'employee',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { rows: Array<{ total_rooms: number; occupied_rooms: number; available_rooms: number; occupancy_pct: number; active_bookings: number; arrivals_today: number }>; answer: string };
    expect(body.rows).toHaveLength(1);
    const summary = body.rows[0]!;
    expect(summary.total_rooms).toBe(4);
    expect(summary.occupied_rooms).toBe(2);
    expect(summary.available_rooms).toBe(2);
    expect(summary.occupancy_pct).toBe(50);
    expect(summary.active_bookings).toBe(2);
    expect(summary.arrivals_today).toBe(1);
    expect(body.answer).toContain('50%');
  });

  it('occupancy_trend merges daily occupancy with revenue and expenses', async () => {
    await seedRoom(uniqueUuid('r1'), '101', 'شاغرة');
    await seedRoom(uniqueUuid('r2'), '102', 'شاغرة');
    await seedStay(uniqueUuid('b1'), '101', 'نزيل', 'محجوزة', { checkin: dayAt(-2), checkout: today, nights: 2, due: 30000, paid: 0 });
    await seedPayment(uniqueUuid('p1'), 15000, `${dayAt(-1)}T10:00:00`);
    await seedExpense(uniqueUuid('e1'), 'ديزل', 5000, dayAt(-1));

    const res = await handleAiRequest(
      aiRequest({ prompt: 'اتجاه الإشغال' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', queryType: 'occupancy_trend', dateFrom: dayAt(-2), dateTo: today, explanation: 'x' }) },
      'employee',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { rows: Array<{ date: string; occupied_rooms: number; occupancy_pct: number; bookings: number; revenue: number; expenses: number }>; answer: string };
    expect(body.rows).toHaveLength(3);
    const byDate = new Map(body.rows.map((r) => [r.date, r]));
    // Checkout is today → the stay covers dayAt(-2) and dayAt(-1); today is free
    expect(byDate.get(dayAt(-2))?.occupied_rooms).toBe(1);
    expect(byDate.get(dayAt(-1))?.occupied_rooms).toBe(1);
    expect(byDate.get(today)?.occupied_rooms).toBe(0);
    expect(byDate.get(dayAt(-2))?.occupancy_pct).toBe(50);
    expect(byDate.get(dayAt(-1))?.revenue).toBe(15000);
    expect(byDate.get(dayAt(-1))?.expenses).toBe(5000);
    expect(body.answer).toContain('اتجاه الإشغال');
  });

  it('booking_analysis reports per-day arrivals, expected revenue and departures', async () => {
    await seedStay(uniqueUuid('b1'), '101', 'نزيل 1', 'محجوزة', { checkin: dayAt(-2), checkout: dayAt(-1), nights: 1, due: 10000, paid: 10000 });
    await seedStay(uniqueUuid('b2'), '102', 'نزيل 2', 'محجوزة', { checkin: dayAt(-1), checkout: dayAt(1), nights: 2, due: 20000, paid: 0 });
    await seedStay(uniqueUuid('b3'), '103', 'قديم', 'مكتمل', { checkin: dayAt(-20), checkout: dayAt(-2), nights: 18, due: 5000, paid: 5000 });

    const res = await handleAiRequest(
      aiRequest({ prompt: 'حلل الحجوزات' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', queryType: 'booking_analysis', dateFrom: dayAt(-3), dateTo: today, explanation: 'x' }) },
      'manager',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { rows: Array<{ date: string; bookings: number; rooms_booked: number }>; answer: string };
    expect(body.rows).toHaveLength(2);
    const byDate = new Map(body.rows.map((r) => [r.date, r]));
    expect(byDate.get(dayAt(-2))?.bookings).toBe(1);
    expect(byDate.get(dayAt(-1))?.bookings).toBe(1);
    // b3 checked in outside the window → excluded from arrivals
    // departures inside window: b1 (checkout dayAt(-1)); b3 checked out dayAt(-2) → also inside
    expect(body.answer).toContain('2 حجزاً');
    expect(body.answer).toContain('مغادرات 2');
  });

  it('overdue_bookings flags active stays past checkout and ignores completed ones', async () => {
    await seedStay(uniqueUuid('b1'), '301', 'متأخر صالح', 'محجوزة', { checkin: dayAt(-10), checkout: dayAt(-3), nights: 7, due: 70000, paid: 20000 });
    await seedStay(uniqueUuid('b2'), '302', 'غادر فعلاً', 'مكتمل', { checkin: dayAt(-15), checkout: dayAt(-8), nights: 7, due: 70000, paid: 70000 });
    await seedStay(uniqueUuid('b3'), '303', 'ما زال مقيم', 'محجوزة', { checkin: dayAt(-1), checkout: dayAt(2), nights: 3, due: 30000, paid: 0 });

    const res = await handleAiRequest(
      aiRequest({ prompt: 'هل توجد حجوزات متأخرة؟' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', queryType: 'overdue_bookings', explanation: 'x' }) },
      'employee',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { rows: Array<{ guest_name: string; overdue_days: number; overdue_status: string; remaining_balance: number }>; answer: string };
    expect(body.rows).toHaveLength(1);
    expect(body.rows[0]?.guest_name).toBe('متأخر صالح');
    expect(body.rows[0]?.overdue_days).toBe(3);
    expect(body.rows[0]?.remaining_balance).toBe(50000);
    expect(body.rows[0]?.overdue_status).toContain('متأخر');
    expect(body.answer).toContain('1');
  });

  it('stay_statistics averages nights and totals the money columns', async () => {
    await seedStay(uniqueUuid('b1'), '401', 'أ', 'محجوزة', { checkin: dayAt(-10), nights: 10, due: 100000, paid: 60000 });
    await seedStay(uniqueUuid('b2'), '402', 'ب', 'محجوزة', { checkin: dayAt(-20), nights: 20, due: 200000, paid: 200000 });
    await seedStay(uniqueUuid('b3'), '403', 'منته', 'مكتمل', { checkin: dayAt(-40), checkout: dayAt(-30), nights: 30, due: 999999, paid: 999999 });

    const res = await handleAiRequest(
      aiRequest({ prompt: 'ما متوسط مدة الإقامة؟' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', queryType: 'stay_statistics', explanation: 'x' }) },
      'employee',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { rows: Array<{ bookings: number; avg_nights: number; longest_stay_nights: number; expected_revenue: number; collected_revenue: number; remaining_balance: number }> };
    const stats = body.rows[0]!;
    expect(stats.bookings).toBe(2);
    expect(stats.avg_nights).toBe(15);
    expect(stats.longest_stay_nights).toBe(20);
    expect(stats.expected_revenue).toBe(300000);
    expect(stats.collected_revenue).toBe(260000);
    expect(stats.remaining_balance).toBe(40000);
  });

  it('occupancy_trend defaults to the last 30 days when no window given', async () => {
    const res = await handleAiRequest(
      aiRequest({ prompt: 'اتجاه الإشغال' }),
      { DB: env.DB, AI: mockAi({ kind: 'query', queryType: 'occupancy_trend', explanation: 'x' }) },
      'employee',
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { rows: Array<{ date: string }> };
    expect(body.rows).toHaveLength(30);
    expect(body.rows[0]?.date).toBe(dayAt(-29));
    expect(body.rows[29]?.date).toBe(today);
  });
});
