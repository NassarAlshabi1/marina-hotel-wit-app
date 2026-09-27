// ═══════════════════════════════════════════════════════════════
//  finance.test.ts — اختبارات نقاط /api/finance/*
//
//  يغطي: بوابة المصادقة، نموذج الـ13 أسبوعاً على بيانات مزروعة،
//  لوحة المؤشرات (16 صفاً)، بوابة الأدوار لل snapshots، دورة
//  الاعتماد ثم مقارنة «الفعلي مقابل المتوقع».
// ═══════════════════════════════════════════════════════════════

import { beforeEach, describe, expect, it } from 'vitest';
import { env, SELF } from 'cloudflare:test';
import { adminAuthHeader, resetDb, uniqueUuid } from './helpers';

let admin = '';

beforeEach(async () => {
  await resetDb();
  admin = await adminAuthHeader();
});

// ─── أدوات الزرع المباشر في D1 ──────────────────────────────────

let counter = 0;
function nextUuid(prefix: string): string {
  counter += 1;
  return uniqueUuid(prefix) + counter;
}

function dayKey(d: Date): string {
  return d.toISOString().substring(0, 10);
}

async function seedRoom(n = 1): Promise<void> {
  for (let i = 0; i < n; i++) {
    await env.DB.prepare(
      `INSERT INTO rooms (local_uuid, room_number, type, price, status, created_at, updated_at)
       VALUES (?1, ?2, 'double', 15000, 'available', 1, 1)`
    )
      .bind(nextUuid('room'), `R${100 + i}-${counter}-${i}`)
      .run();
  }
}

async function seedBooking(o: {
  checkin: string;
  checkout: string;
  status?: string;
  due?: number;
  paid?: number;
}): Promise<number> {
  const res = await env.DB.prepare(
    `INSERT INTO bookings (local_uuid, room_number, guest_name, guest_phone,
        guest_nationality, checkin_date, checkout_date, status,
        calculated_nights, total_due_cached, total_paid_cached, created_at, updated_at)
     VALUES (?1, 'R100', 'ضيف اختبار', '777000000', 'يمني',
        ?2, ?3, ?4, 3, ?5, ?6, 1, 1)`
  )
    .bind(
      nextUuid('bk'),
      o.checkin,
      o.checkout,
      o.status ?? 'مقيم',
      o.due ?? 120000,
      o.paid ?? 0
    )
    .run();
  return Number(res.meta.last_row_id);
}

async function seedPayment(o: {
  bookingId?: number | null;
  amount: number;
  date: string;
  method?: string;
  revenueType?: string;
}): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO payments (local_uuid, booking_local_id, amount, payment_date,
        payment_method, revenue_type, created_at, updated_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1, 1)`
  )
    .bind(
      nextUuid('pay'),
      o.bookingId ?? null,
      o.amount,
      o.date,
      o.method ?? 'نقدي',
      o.revenueType ?? 'room'
    )
    .run();
}

async function seedExpense(o: {
  type: string;
  amount: number;
  date: string;
}): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO expenses (local_uuid, expense_type, description, amount, date, created_at, updated_at)
     VALUES (?1, ?2, 'اختبار', ?3, ?4, 1, 1)`
  )
    .bind(nextUuid('exp'), o.type, o.amount, o.date)
    .run();
}

async function seedEmployee(o: { salary: number; status: string }): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO employees (local_uuid, name, basic_salary, status, created_at, updated_at)
     VALUES (?1, 'موظف اختبار', ?2, ?3, 1, 1)`
  )
    .bind(nextUuid('emp'), o.salary, o.status)
    .run();
}

// ─── الاختبارات ──────────────────────────────────────────────────

describe('GET /api/finance/* — auth gate', () => {
  it('rejects an unauthenticated request with 401', async () => {
    const res = await SELF.fetch('https://example.com/api/finance/forecast');
    expect(res.status).toBe(401);
  });
});

describe('GET /api/finance/forecast', () => {
  it('returns 13 weeks with zero flows on an empty database', async () => {
    const res = await SELF.fetch(
      'https://example.com/api/finance/forecast?scenario=base',
      { headers: { Authorization: admin } }
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      source: string;
      scenario: { key: string };
      weeks: Array<Record<string, unknown>>;
      totalInflow: number;
      totalOutflow: number;
    };
    expect(body.source).toBe('d1');
    expect(body.scenario.key).toBe('base');
    expect(body.weeks.length).toBe(13);
    // بلا بيانات: خارج ثابت صفر (رواتب بلا موظفين نشطين)
    expect(body.totalInflow).toBe(0);
    expect(body.totalOutflow).toBe(0);
  });

  it('computes confirmed inflow from a current guest and history balance', async () => {
    await seedRoom(4);
    await seedEmployee({ salary: 400000, status: 'active' });

    // تاريخ يدفع رصيد البداية: +300000 نقد، -50000 مصروف
    await seedPayment({ bookingId: null, amount: 300000, date: '2026-07-01' });
    await seedExpense({ type: 'كهرباء', amount: 50000, date: '2026-07-02' });

    // نزيل حالي: دخل قبل بداية النموذج وبقية مستحقة
    const today = new Date();
    const inPast = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate() - 5));
    const after = new Date(inPast.getTime() + 10 * 86_400_000);
    const bk = await seedBooking({
      checkin: dayKey(inPast),
      checkout: dayKey(after),
      due: 200000,
      paid: 50000,
    });

    const res = await SELF.fetch(
      'https://example.com/api/finance/forecast?scenario=base',
      { headers: { Authorization: admin } }
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      openingBalance: number;
      totalInflow: number;
      weeks: Array<{ inflow: { confirmed: number } }>;
    };
    // رصيد البداية = 300000 - 50000 = 250000
    expect(body.openingBalance).toBeCloseTo(250000, 0);
    // بقايا النزيل المؤكدة = 200000 - 50000 = 150000
    const confirmed = body.weeks.reduce((s, w) => s + w.inflow.confirmed, 0);
    expect(confirmed).toBeCloseTo(150000, 0);
    expect(bk).toBeGreaterThan(0);
  });

  it('honors custom scenario factors without lowering confirmed tier', async () => {
    await seedRoom(2);
    const today = new Date();
    const inPast = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate() - 2));
    // المغادرة داخل الأسبوع الأول/الثاني من النموذج (لا على حدّه)
    const after = new Date(inPast.getTime() + 11 * 86_400_000);
    await seedBooking({ checkin: dayKey(inPast), checkout: dayKey(after), due: 90000, paid: 0 });

    const res = await SELF.fetch(
      'https://example.com/api/finance/forecast?scenario=stress&revenue=0.5&collection=0.5',
      { headers: { Authorization: admin } }
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      scenario: { key: string; revenueFactor: number };
      weeks: Array<{ inflow: { confirmed: number } }>;
    };
    expect(body.scenario.revenueFactor).toBe(0.5);
    // المؤكد لا يُخفض حتى في سيناريو الضغط
    const confirmed = body.weeks.reduce((s, w) => s + w.inflow.confirmed, 0);
    expect(confirmed).toBeCloseTo(90000, 0);
  });
});

describe('GET /api/finance/kpi', () => {
  it('returns 16 indicator rows with alert levels', async () => {
    await seedRoom(3);
    const today = new Date();
    const d = (offset: number) =>
      dayKey(new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate() + offset)));
    await seedPayment({ amount: 100000, date: d(0), revenueType: 'room' });
    await seedExpense({ type: 'ديزل', amount: 20000, date: d(0) });

    const res = await SELF.fetch('https://example.com/api/finance/kpi', {
      headers: { Authorization: admin },
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      source: string;
      rows: Array<{ label: string; status: string }>;
    };
    expect(body.source).toBe('d1');
    expect(body.rows.length).toBe(16);
    for (const row of body.rows) {
      expect(row.label.length).toBeGreaterThan(0);
      expect(['good', 'warning', 'danger', 'unknown']).toContain(row.status);
    }
  });
});

describe('finance snapshots — governance gate + approve flow', () => {
  it('blocks staff from listing and approving snapshots', async () => {
    // إنشاء موظف عادي عبر register محمي (يوجد admin مسبقاً → يتطلب admin)
    const staffRes = await SELF.fetch('https://example.com/api/auth/register', {
      method: 'POST',
      headers: { Authorization: admin, 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'staff1', password: 'staff-pw-123', role: 'staff' }),
    });
    expect(staffRes.status).toBe(201);
    const staff = ((await staffRes.json()) as { token: string }).token;

    const listRes = await SELF.fetch('https://example.com/api/finance/snapshots', {
      headers: { Authorization: `Bearer ${staff}` },
    });
    expect(listRes.status).toBe(403);

    const postRes = await SELF.fetch('https://example.com/api/finance/snapshots', {
      method: 'POST',
      headers: { Authorization: `Bearer ${staff}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    expect(postRes.status).toBe(403);
  });

  it('admin approves a snapshot then lists it', async () => {
    await seedRoom(2);
    const today = new Date();
    const start = dayKey(
      new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1))
    );
    const res = await SELF.fetch('https://example.com/api/finance/snapshots', {
      method: 'POST',
      headers: { Authorization: admin, 'Content-Type': 'application/json' },
      body: JSON.stringify({ label: 'نسخة الاختبار', scenario: 'base', start }),
    });
    expect(res.status).toBe(201);
    const saved = (await res.json()) as { snapshot: { id: number; label: string } };
    expect(saved.snapshot.id).toBeGreaterThan(0);
    expect(saved.snapshot.label).toBe('نسخة الاختبار');

    const listRes = await SELF.fetch('https://example.com/api/finance/snapshots', {
      headers: { Authorization: admin },
    });
    expect(listRes.status).toBe(200);
    const list = (await listRes.json()) as {
      snapshots: Array<{ id: number; scenario_key: string }>;
    };
    expect(list.snapshots.some((s) => s.id === saved.snapshot.id)).toBe(true);
    return;
  });

  it('variance compares ended weeks against live actuals', async () => {
    await seedRoom(2);
    // نموذج بدأ قبل 3 أسابيع ⇒ أول أسبوعين منتهيان
    const today = new Date();
    const start = new Date(
      Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()) -
        21 * 86_400_000
    );
    const startKey = dayKey(start);

    // فعلي داخل الأسبوع الأول المنتهي
    const week1Mid = dayKey(new Date(start.getTime() + 3 * 86_400_000));
    await seedPayment({ amount: 70000, date: week1Mid, revenueType: 'room' });
    await seedExpense({ type: 'ديزل', amount: 10000, date: week1Mid });

    const approveRes = await SELF.fetch('https://example.com/api/finance/snapshots', {
      method: 'POST',
      headers: { Authorization: admin, 'Content-Type': 'application/json' },
      body: JSON.stringify({ label: 'أسبوع -3', scenario: 'base', start: startKey }),
    });
    expect(approveRes.status).toBe(201);
    const { snapshot } = (await approveRes.json()) as {
      snapshot: { id: number };
    };

    const varRes = await SELF.fetch(
      `https://example.com/api/finance/variance?snapshot_id=${snapshot.id}`,
      { headers: { Authorization: admin } }
    );
    expect(varRes.status).toBe(200);
    const body = (await varRes.json()) as {
      snapshotId: number;
      weeks: Array<{
        index: number;
        actual: { inflow: number; outflow: number } | null;
        status: string;
      }>;
    };
    expect(body.snapshotId).toBe(snapshot.id);
    // الأسبوعان المنتهيان لهما فعلي؛ البقية null
    const ended = body.weeks.filter((w) => w.actual != null);
    expect(ended.length).toBeGreaterThanOrEqual(2);
    expect(ended[0].actual!.inflow).toBeCloseTo(70000, 0);
    expect(ended[0].actual!.outflow).toBeCloseTo(10000, 0);
    for (const w of body.weeks) {
      expect(['green', 'yellow', 'red', 'unknown']).toContain(w.status);
    }
  });

  it('variance returns 404 for a missing snapshot', async () => {
    const res = await SELF.fetch(
      'https://example.com/api/finance/variance?snapshot_id=999999',
      { headers: { Authorization: admin } }
    );
    expect(res.status).toBe(404);
  });
});
