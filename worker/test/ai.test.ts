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
