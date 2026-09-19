// Natural-language hotel operations for Workers AI + D1.
// The model may classify a request, but never supplies executable SQL.

export interface AiBinding {
  run(model: string, input: unknown): Promise<unknown>;
}

export interface AiPlan {
  kind: 'query' | 'add_expense' | 'unsupported';
  queryType?: 'expenses_total' | 'employee_withdrawals' | 'employee_salary' | 'daily_summary' | 'rooms_available' | 'rooms_all' | 'current_guests' | 'guest_search' | 'bookings_current' | 'occupancy_summary' | 'occupancy_trend' | 'booking_analysis' | 'overdue_bookings' | 'stay_statistics';
  employeeName?: string;
  guestName?: string;
  roomNumber?: string;
  expenseType?: string;
  description?: string;
  amountPerDay?: number;
  dateFrom?: string;
  dateTo?: string;
  explanation: string;
}

const MODEL = '@cf/meta/llama-3.1-8b-instruct';

// The mobile app (StatusUtils) writes BILINGUAL status values and production
// D1 currently holds the Arabic forms ('شاغرة'/'محجوزة'). Every SQL status
// filter must accept both languages or it silently matches zero rows.
const ACTIVE_BOOKING_STATUSES = ['محجوزة', 'محجوز', 'نشط', 'active', 'confirmed', 'قيد الحجز', 'in_progress', 'مؤقت', 'provisional'];
const AVAILABLE_ROOM_STATUSES = ['شاغرة', 'شاغره', 'متاحة', 'متاح', 'available', 'vacant', 'empty'];
const OCCUPIED_ROOM_STATUSES = ['محجوزة', 'محجوز', 'مشغولة', 'occupied', 'محجوز temporarily', 'نشط', 'active', 'مؤقت', 'provisional'];

const KNOWN_QUERY_TYPES = new Set([
  'expenses_total', 'employee_withdrawals', 'employee_salary', 'daily_summary',
  'rooms_available', 'rooms_all', 'current_guests', 'guest_search', 'bookings_current',
  'occupancy_summary', 'occupancy_trend', 'booking_analysis', 'overdue_bookings', 'stay_statistics',
]);

function inList(values: readonly string[]): string {
  return `(${values.map(() => '?').join(',')})`;
}

function utcDate(offsetDays = 0): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + offsetDays);
  return d.toISOString().slice(0, 10);
}

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function extractJson(raw: unknown): AiPlan {
  const text = typeof raw === 'string'
    ? raw
    : raw && typeof raw === 'object' && 'response' in raw
      ? String((raw as { response: unknown }).response)
      : JSON.stringify(raw);
  const cleaned = text.replace(/```json|```/g, '').trim();
  const start = cleaned.indexOf('{');
  const end = cleaned.lastIndexOf('}');
  if (start < 0 || end <= start) throw new Error('AI returned no JSON plan');
  const value = JSON.parse(cleaned.slice(start, end + 1)) as Record<string, unknown>;
  return {
    kind: value.kind === 'query' || value.kind === 'add_expense' ? value.kind : 'unsupported',
    queryType: typeof value.queryType === 'string' ? value.queryType as AiPlan['queryType'] : undefined,
    employeeName: typeof value.employeeName === 'string' ? value.employeeName.trim() : undefined,
    guestName: typeof value.guestName === 'string' ? value.guestName.trim() : undefined,
    roomNumber: typeof value.roomNumber === 'string' ? value.roomNumber.trim() : undefined,
    expenseType: typeof value.expenseType === 'string' ? value.expenseType.trim() : undefined,
    description: typeof value.description === 'string' ? value.description.trim() : undefined,
    amountPerDay: typeof value.amountPerDay === 'number' ? value.amountPerDay : undefined,
    dateFrom: typeof value.dateFrom === 'string' ? value.dateFrom : undefined,
    dateTo: typeof value.dateTo === 'string' ? value.dateTo : undefined,
    explanation: typeof value.explanation === 'string' ? value.explanation : 'تم تحليل الطلب.',
  };
}

function validDate(value: unknown): value is string {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`));
}

function daysBetween(from: string, to: string): string[] {
  const result: string[] = [];
  const cursor = new Date(`${from}T00:00:00Z`);
  const end = new Date(`${to}T00:00:00Z`);
  for (let i = 0; cursor <= end && i < 366; i += 1) {
    result.push(cursor.toISOString().slice(0, 10));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return result;
}

async function classify(env: { AI: AiBinding }, prompt: string): Promise<AiPlan> {
  const today = new Date().toISOString().slice(0, 10);
  const instruction = `أنت محلل طلبات لنظام إدارة فندق. تاريخ اليوم ${today}. أعد JSON فقط بلا markdown.
الأنواع المسموحة: query أو add_expense أو unsupported.
للاستعلام استخدم queryType واحداً من expenses_total, employee_withdrawals, employee_salary, daily_summary, rooms_available, rooms_all, current_guests, guest_search, bookings_current, occupancy_summary, occupancy_trend, booking_analysis, overdue_bookings, stay_statistics.
rooms_available للغرف الشاغرة، rooms_all لكل الغرف وحالتها، current_guests للنزلاء الموجودين، guest_search للبحث عن نزيل باسمه أو رقم غرفته، bookings_current للحجوزات النشطة.
occupancy_summary للإشغال الحالي (النسبة والغرف المشغولة والشاغرة والوصولات اليوم). occupancy_trend لاتجاه الإشغال مع الإيرادات والمصروفات اليومية خلال فترة — إن لم تذكر فترة فاستخدم آخر 30 يوماً حتى اليوم في dateFrom وdateTo. booking_analysis لتحليل الحجوزات خلال فترة (عددها اليومي والغرف والإيراد المتوقع والمغادرات) — إن لم تذكر فترة فاجعل dateFrom أول يوم من الشهر الحالي وdateTo اليوم. overdue_bookings للحجوزات المتأخرة عن موعد المغادرة. stay_statistics لإحصائيات الإقامة الحالية (متوسط الليالي وأطول إقامة والإيراد المتوقع والمحصل والمتبقي).
لإضافة مصروف: expenseType, description, amountPerDay, dateFrom, dateTo بصيغة YYYY-MM-DD. إذا لم يذكر المستخدم تاريخاً فاجعل dateFrom=dateTo=${today}. المبلغ في مثال "40 ألف لكل يوم" هو 40000 لكل يوم، وليس إجمالياً.
لا تخترع اسماً أو مبلغاً أو تاريخاً. إذا كان الطلب غامضاً أو خطراً استخدم unsupported واشرح المطلوب.
JSON schema: {kind,queryType,employeeName,guestName,roomNumber,expenseType,description,amountPerDay,dateFrom,dateTo,explanation}
طلب المستخدم: ${prompt}`;
  const raw = await env.AI.run(MODEL, {
    messages: [
      { role: 'system', content: 'أنت محلل JSON دقيق.' },
      { role: 'user', content: instruction },
    ],
    temperature: 0,
    max_tokens: 512,
  });
  return extractJson(raw);
}

function validatePlan(plan: AiPlan): string | null {
  if (plan.kind === 'unsupported') return plan.explanation || 'الطلب غير مدعوم أو يحتاج توضيحاً.';
  if (plan.kind === 'query') {
    if (!plan.queryType || !KNOWN_QUERY_TYPES.has(plan.queryType)) return 'لم أتعرف على نوع الاستعلام.';
    if ((plan.queryType === 'employee_withdrawals' || plan.queryType === 'employee_salary') && !plan.employeeName) return 'اذكر اسم الموظف.';
    if (plan.queryType === 'guest_search' && !plan.guestName && !plan.roomNumber) return 'اذكر اسم النزيل أو رقم الغرفة.';
    return null;
  }
  if (!plan.expenseType || !plan.description || !Number.isFinite(plan.amountPerDay) || (plan.amountPerDay ?? 0) <= 0) return 'اذكر نوع المصروف والوصف والمبلغ الصحيح.';
  if (!validDate(plan.dateFrom) || !validDate(plan.dateTo) || plan.dateFrom! > plan.dateTo!) return 'التاريخ يجب أن يكون بصيغة YYYY-MM-DD وبمدى صحيح.';
  if (daysBetween(plan.dateFrom!, plan.dateTo!).length === 0) return 'مدى التاريخ غير صالح أو أكبر من سنة.';
  return null;
}

export async function handleAiRequest(
  request: Request,
  env: { DB: D1Database; AI: AiBinding },
  role: string,
): Promise<Response> {
  const body = await request.json() as { prompt?: string; plan?: AiPlan; confirm?: boolean };
  let plan = body.plan;
  if (!plan) {
    if (!body.prompt?.trim()) return jsonResponse({ error: 'prompt is required' }, 400);
    try {
      plan = await classify(env, body.prompt.trim());
    } catch (error) {
      console.error('[AI] classification failed', error);
      return jsonResponse({ error: 'تعذر تحليل الطلب حالياً' }, 502);
    }
  }
  const validationError = validatePlan(plan);
  if (validationError) return jsonResponse({ plan, requires_confirmation: false, answer: validationError }, 200);

  if (plan.kind === 'query') {
    const { rows, answer } = await runQuery(env, plan);
    return jsonResponse({ plan, requires_confirmation: false, answer: answer ?? plan.explanation, rows });
  }

  if (role !== 'admin' && role !== 'manager') return jsonResponse({ error: 'صلاحية المدير مطلوبة لإضافة مصروف' }, 403);
  if (!body.confirm) return jsonResponse({ plan, requires_confirmation: true, answer: `سأضيف ${plan.amountPerDay} يومياً من ${plan.dateFrom} إلى ${plan.dateTo}. راجع التفاصيل ثم أكد التنفيذ.` });

  const dates = daysBetween(plan.dateFrom!, plan.dateTo!);
  const now = Date.now();
  const statements = dates.map((date) => env.DB.prepare(
    `INSERT INTO expenses (expense_type,description,amount,date,hotel_day_key,is_auto_generated,local_uuid,created_at,updated_at,last_modified,origin,device_id)
     VALUES (?,?,?,?,?,0,?,?,?,?,?,?)`,
  ).bind(plan.expenseType, plan.description, plan.amountPerDay, date, date, crypto.randomUUID(), now, now, now, 'ai', 'worker'));
  await env.DB.batch(statements);
  return jsonResponse({ plan, requires_confirmation: false, answer: `تمت إضافة ${dates.length} مصروفاً بمجموع ${(dates.length * plan.amountPerDay!).toFixed(0)} ريال.` });
}

// ─── Query dispatch ────────────────────────────────────────────
// All read-only analytics live here. The model only picks the
// queryType — the SQL below is the single source of truth.

async function runQuery(
  env: { DB: D1Database; AI: AiBinding },
  plan: AiPlan,
): Promise<{ rows: unknown[]; answer?: string }> {
  switch (plan.queryType) {
    case 'expenses_total': {
      const result = await env.DB.prepare(
        `SELECT expense_type, COUNT(*) AS entries, COALESCE(SUM(amount),0) AS total
         FROM expenses WHERE deleted_at IS NULL AND date >= ? AND date <= ? GROUP BY expense_type ORDER BY total DESC LIMIT 100`,
      ).bind(plan.dateFrom ?? '0000-01-01', plan.dateTo ?? '9999-12-31').all();
      return { rows: result.results };
    }
    case 'employee_withdrawals': {
      const result = await env.DB.prepare(
        `SELECT e.name, COALESCE(SUM(sw.amount),0) AS total_withdrawn, COUNT(sw.id) AS entries
         FROM employees e LEFT JOIN salary_withdrawals sw ON sw.employee_id=e.id AND sw.deleted_at IS NULL
         WHERE e.deleted_at IS NULL AND e.name LIKE ? GROUP BY e.id,e.name LIMIT 20`,
      ).bind(`%${plan.employeeName}%`).all();
      return { rows: result.results };
    }
    case 'employee_salary': {
      const result = await env.DB.prepare(
        `SELECT e.name, e.basic_salary, COALESCE(SUM(sw.amount),0) AS total_withdrawn,
         e.basic_salary-COALESCE(SUM(sw.amount),0) AS estimated_remaining
         FROM employees e LEFT JOIN salary_withdrawals sw ON sw.employee_id=e.id AND sw.deleted_at IS NULL
         WHERE e.deleted_at IS NULL AND e.name LIKE ? GROUP BY e.id,e.name,e.basic_salary LIMIT 20`,
      ).bind(`%${plan.employeeName}%`).all();
      return { rows: result.results };
    }
    case 'rooms_available': {
      const result = await env.DB.prepare(
        `SELECT room_number, type, price, status, cleaning_status FROM rooms
         WHERE deleted_at IS NULL AND status IN ${inList(AVAILABLE_ROOM_STATUSES)} ORDER BY room_number LIMIT 200`,
      ).bind(...AVAILABLE_ROOM_STATUSES).all();
      return { rows: result.results };
    }
    case 'rooms_all': {
      const result = await env.DB.prepare(
        `SELECT room_number, type, price, status, cleaning_status, requires_maintenance
         FROM rooms WHERE deleted_at IS NULL ORDER BY room_number LIMIT 300`,
      ).all();
      return { rows: result.results };
    }
    case 'current_guests':
    case 'bookings_current': {
      const result = await env.DB.prepare(
        `SELECT room_number, guest_name, guest_phone, guest_nationality, substr(checkin_date,1,10) AS checkin_date,
         substr(checkout_date,1,10) AS checkout_date, status, total_due_cached, total_paid_cached, remaining_balance_cached
         FROM bookings WHERE deleted_at IS NULL AND status IN ${inList(ACTIVE_BOOKING_STATUSES)}
         ORDER BY room_number LIMIT 300`,
      ).bind(...ACTIVE_BOOKING_STATUSES).all();
      return { rows: result.results };
    }
    case 'guest_search': {
      const needle = plan.guestName || plan.roomNumber || '';
      const result = await env.DB.prepare(
        `SELECT room_number, guest_name, guest_phone, guest_nationality, guest_id_number,
         substr(checkin_date,1,10) AS checkin_date, substr(checkout_date,1,10) AS checkout_date, status, notes
         FROM bookings WHERE deleted_at IS NULL AND (guest_name LIKE ? OR room_number LIKE ?)
         ORDER BY checkin_date DESC LIMIT 50`,
      ).bind(`%${needle}%`, `%${needle}%`).all();
      return { rows: result.results };
    }
    case 'daily_summary': {
      const today = utcDate(0);
      const result = await env.DB.prepare(
        `SELECT date, COALESCE(SUM(amount),0) AS total_expenses, COUNT(*) AS entries
         FROM expenses WHERE deleted_at IS NULL AND date >= ? AND date <= ? GROUP BY date ORDER BY date DESC LIMIT 366`,
      ).bind(plan.dateFrom ?? today, plan.dateTo ?? today).all();
      return { rows: result.results };
    }
    case 'occupancy_summary':
      return queryOccupancySummary(env);
    case 'occupancy_trend': {
      const { from, to } = resolveWindow(plan, -29);
      return queryOccupancyTrend(env, from, to);
    }
    case 'booking_analysis': {
      const { from, to } = resolveWindow(plan, undefined, `${utcDate(0).slice(0, 7)}-01`);
      return queryBookingAnalysis(env, from, to);
    }
    case 'overdue_bookings':
      return queryOverdueBookings(env);
    case 'stay_statistics':
      return queryStayStatistics(env);
    default:
      return { rows: [] };
  }
}

/** Resolve an optional date window; falls back to a default and clamps to 366 days. */
function resolveWindow(plan: AiPlan, defaultFromOffset?: number, defaultFrom?: string): { from: string; to: string } {
  const today = utcDate(0);
  const hasValid = validDate(plan.dateFrom) && validDate(plan.dateTo) && plan.dateFrom! <= plan.dateTo!;
  let from = hasValid ? plan.dateFrom! : (defaultFrom ?? utcDate(defaultFromOffset ?? -29));
  const to = hasValid ? plan.dateTo! : today;
  if (daysBetween(from, to).length > 366) from = daysBetween(to, to).length ? offsetDate(to, -365) : from;
  return { from, to };
}

function offsetDate(base: string, offsetDays: number): string {
  const d = new Date(`${base}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + offsetDays);
  return d.toISOString().slice(0, 10);
}

async function queryOccupancySummary(env: { DB: D1Database }): Promise<{ rows: unknown[]; answer: string }> {
  const rooms = await env.DB.prepare(
    `SELECT COUNT(*) AS total_rooms,
       COALESCE(SUM(CASE WHEN status IN ${inList(AVAILABLE_ROOM_STATUSES)} THEN 1 ELSE 0 END),0) AS available_rooms,
       COALESCE(SUM(CASE WHEN status IN ${inList(OCCUPIED_ROOM_STATUSES)} THEN 1 ELSE 0 END),0) AS occupied_rooms
     FROM rooms WHERE deleted_at IS NULL`,
  ).bind(...AVAILABLE_ROOM_STATUSES, ...OCCUPIED_ROOM_STATUSES)
    .first<{ total_rooms: number; available_rooms: number; occupied_rooms: number }>();
  const bookings = await env.DB.prepare(
    `SELECT COUNT(*) AS active_bookings,
       COALESCE(SUM(CASE WHEN substr(checkin_date,1,10) = ? THEN 1 ELSE 0 END),0) AS arrivals_today
     FROM bookings WHERE deleted_at IS NULL AND status IN ${inList(ACTIVE_BOOKING_STATUSES)}`,
  ).bind(utcDate(0), ...ACTIVE_BOOKING_STATUSES)
    .first<{ active_bookings: number; arrivals_today: number }>();
  const total = rooms?.total_rooms ?? 0;
  const occupied = rooms?.occupied_rooms ?? 0;
  const available = rooms?.available_rooms ?? 0;
  const active = bookings?.active_bookings ?? 0;
  const arrivals = bookings?.arrivals_today ?? 0;
  const pct = total > 0 ? Math.round((occupied / total) * 1000) / 10 : 0;
  return {
    rows: [{
      total_rooms: total,
      occupied_rooms: occupied,
      available_rooms: available,
      occupancy_pct: pct,
      active_bookings: active,
      arrivals_today: arrivals,
    }],
    answer: `الإشغال الحالي: ${occupied}/${total} غرفة مشغولة (${pct}%) — شاغرة ${available}، حجوزات نشطة ${active}، وصولات اليوم ${arrivals}.`,
  };
}

async function queryOccupancyTrend(
  env: { DB: D1Database },
  from: string,
  to: string,
): Promise<{ rows: unknown[]; answer: string }> {
  const totalRooms = (await env.DB.prepare('SELECT COUNT(*) AS c FROM rooms WHERE deleted_at IS NULL')
    .first<{ c: number }>())?.c ?? 0;
  const occupancy = await env.DB.prepare(
    `WITH RECURSIVE days(d) AS (SELECT ? UNION ALL SELECT date(d,'+1 day') FROM days WHERE d < ?)
     SELECT d AS date,
       (SELECT COUNT(*) FROM bookings b WHERE b.deleted_at IS NULL AND b.status IN ${inList(ACTIVE_BOOKING_STATUSES)}
          AND substr(b.checkin_date,1,10) <= d
          AND (b.checkout_date IS NULL OR substr(b.checkout_date,1,10) > d OR d <= ?)) AS bookings,
       (SELECT COUNT(DISTINCT b.room_number) FROM bookings b WHERE b.deleted_at IS NULL AND b.status IN ${inList(ACTIVE_BOOKING_STATUSES)}
          AND substr(b.checkin_date,1,10) <= d
          AND (b.checkout_date IS NULL OR substr(b.checkout_date,1,10) > d OR d <= ?)) AS occupied_rooms
     FROM days ORDER BY d`,
  ).bind(from, to, ...ACTIVE_BOOKING_STATUSES, utcDate(0), ...ACTIVE_BOOKING_STATUSES, utcDate(0))
    .all<{ date: string; bookings: number; occupied_rooms: number }>();
  const revenue = await env.DB.prepare(
    `SELECT substr(payment_date,1,10) AS date, ROUND(COALESCE(SUM(amount),0),0) AS revenue
     FROM payments WHERE deleted_at IS NULL AND substr(payment_date,1,10) >= ? AND substr(payment_date,1,10) <= ? GROUP BY 1`,
  ).bind(from, to).all<{ date: string; revenue: number }>();
  const expenses = await env.DB.prepare(
    `SELECT date, ROUND(COALESCE(SUM(amount),0),0) AS expenses
     FROM expenses WHERE deleted_at IS NULL AND date >= ? AND date <= ? GROUP BY 1`,
  ).bind(from, to).all<{ date: string; expenses: number }>();
  const revMap = new Map(revenue.results.map((r) => [r.date, r.revenue ?? 0]));
  const expMap = new Map(expenses.results.map((r) => [r.date, r.expenses ?? 0]));
  const rows = occupancy.results.map((r) => {
    const occupied = r.occupied_rooms ?? 0;
    return {
      date: r.date,
      occupied_rooms: occupied,
      occupancy_pct: totalRooms > 0 ? Math.round((occupied / totalRooms) * 1000) / 10 : 0,
      bookings: r.bookings ?? 0,
      revenue: revMap.get(r.date) ?? 0,
      expenses: expMap.get(r.date) ?? 0,
    };
  });
  const avgPct = rows.length > 0
    ? Math.round((rows.reduce((sum, r) => sum + (r as { occupancy_pct: number }).occupancy_pct, 0) / rows.length) * 10) / 10
    : 0;
  const totalRevenue = rows.reduce((sum, r) => sum + (r as { revenue: number }).revenue, 0);
  const totalExpenses = rows.reduce((sum, r) => sum + (r as { expenses: number }).expenses, 0);
  return {
    rows,
    answer: `اتجاه الإشغال من ${from} إلى ${to} (${rows.length} يوماً): متوسط الإشغال ${avgPct}%، إجمالي الإيرادات ${totalRevenue}، إجمالي المصروفات ${totalExpenses}.`,
  };
}

async function queryBookingAnalysis(
  env: { DB: D1Database },
  from: string,
  to: string,
): Promise<{ rows: unknown[]; answer: string }> {
  const perDay = await env.DB.prepare(
    `SELECT substr(checkin_date,1,10) AS date, COUNT(*) AS bookings, COUNT(DISTINCT room_number) AS rooms_booked
     FROM bookings WHERE deleted_at IS NULL AND substr(checkin_date,1,10) BETWEEN ? AND ? GROUP BY 1 ORDER BY 1 LIMIT 366`,
  ).bind(from, to).all<{ date: string; bookings: number; rooms_booked: number }>();
  const totals = await env.DB.prepare(
    `SELECT COUNT(*) AS bookings, COUNT(DISTINCT room_number) AS rooms_booked,
       ROUND(COALESCE(SUM(total_due_cached),0),0) AS expected_revenue
     FROM bookings WHERE deleted_at IS NULL AND substr(checkin_date,1,10) BETWEEN ? AND ?`,
  ).bind(from, to).first<{ bookings: number; rooms_booked: number; expected_revenue: number }>();
  const departures = await env.DB.prepare(
    `SELECT COUNT(*) AS departures FROM bookings
     WHERE deleted_at IS NULL AND checkout_date IS NOT NULL AND substr(checkout_date,1,10) BETWEEN ? AND ?`,
  ).bind(from, to).first<{ departures: number }>();
  const bookings = totals?.bookings ?? 0;
  const rooms = totals?.rooms_booked ?? 0;
  const expected = totals?.expected_revenue ?? 0;
  const deps = departures?.departures ?? 0;
  return {
    rows: perDay.results,
    answer: `تحليل الحجوزات من ${from} إلى ${to}: ${bookings} حجزاً على ${rooms} غرفة، إيراد متوقع ${expected}، مغادرات ${deps}.`,
  };
}

async function queryOverdueBookings(env: { DB: D1Database }): Promise<{ rows: unknown[]; answer: string }> {
  const today = utcDate(0);
  const result = await env.DB.prepare(
    `SELECT room_number, guest_name, substr(checkin_date,1,10) AS checkin_date,
       substr(checkout_date,1,10) AS checkout_date, ROUND(COALESCE(remaining_balance_cached,0),0) AS remaining_balance, status
     FROM bookings
     WHERE deleted_at IS NULL AND status IN ${inList(ACTIVE_BOOKING_STATUSES)}
       AND checkout_date IS NOT NULL AND substr(checkout_date,1,10) < ?
     ORDER BY substr(checkout_date,1,10) ASC LIMIT 100`,
  ).bind(...ACTIVE_BOOKING_STATUSES, today)
    .all<{ room_number: string; guest_name: string; checkin_date: string; checkout_date: string; remaining_balance: number; status: string }>();
  const rows = result.results.map((r) => {
    const lateDays = Math.max(daysBetween(r.checkout_date, today).length - 1, 1);
    return { ...r, overdue_days: lateDays, overdue_status: `متأخر ${lateDays} يوم` };
  });
  return {
    rows,
    answer: rows.length > 0
      ? `توجد ${rows.length} حجوزات متأخرة عن موعد المغادرة.`
      : 'لا توجد حجوزات متأخرة حالياً.',
  };
}

async function queryStayStatistics(env: { DB: D1Database }): Promise<{ rows: unknown[]; answer: string }> {
  const stats = await env.DB.prepare(
    `SELECT COUNT(*) AS bookings,
       ROUND(COALESCE(AVG(CAST(calculated_nights AS REAL)),0),1) AS avg_nights,
       COALESCE(MAX(calculated_nights),0) AS longest_stay_nights,
       ROUND(COALESCE(SUM(total_due_cached),0),0) AS expected_revenue,
       ROUND(COALESCE(SUM(total_paid_cached),0),0) AS collected_revenue,
       ROUND(COALESCE(SUM(remaining_balance_cached),0),0) AS remaining_balance
     FROM bookings WHERE deleted_at IS NULL AND status IN ${inList(ACTIVE_BOOKING_STATUSES)}`,
  ).bind(...ACTIVE_BOOKING_STATUSES)
    .first<{ bookings: number; avg_nights: number; longest_stay_nights: number; expected_revenue: number; collected_revenue: number; remaining_balance: number }>();
  const s = stats ?? { bookings: 0, avg_nights: 0, longest_stay_nights: 0, expected_revenue: 0, collected_revenue: 0, remaining_balance: 0 };
  return {
    rows: [s],
    answer: `إحصائيات الإقامة النشطة: ${s.bookings} حجزاً، متوسط الإقامة ${s.avg_nights} ليلة، أطول إقامة ${s.longest_stay_nights} ليلة، إيراد متوقع ${s.expected_revenue}، محصل ${s.collected_revenue}، متبقٍ ${s.remaining_balance}.`,
  };
}

export { jsonResponse };
