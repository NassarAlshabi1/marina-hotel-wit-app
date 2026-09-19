// Natural-language hotel operations for Workers AI + D1.
// The model may classify a request, but never supplies executable SQL.

export interface AiBinding {
  run(model: string, input: unknown): Promise<unknown>;
}

export interface AiPlan {
  kind: 'query' | 'add_expense' | 'unsupported';
  queryType?: 'expenses_total' | 'employee_withdrawals' | 'employee_salary' | 'daily_summary' | 'rooms_available' | 'rooms_all' | 'current_guests' | 'guest_search' | 'bookings_current';
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
للاستعلام استخدم queryType واحداً من expenses_total, employee_withdrawals, employee_salary, daily_summary, rooms_available, rooms_all, current_guests, guest_search, bookings_current.
rooms_available للغرف الشاغرة، rooms_all لكل الغرف وحالتها، current_guests للنزلاء الموجودين، guest_search للبحث عن نزيل باسمه أو رقم غرفته، bookings_current للحجوزات النشطة.
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
    if (!plan.queryType) return 'لم أتعرف على نوع الاستعلام.';
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
    let rows: unknown[] = [];
    if (plan.queryType === 'expenses_total') {
      const result = await env.DB.prepare(
        `SELECT expense_type, COUNT(*) AS entries, COALESCE(SUM(amount),0) AS total
         FROM expenses WHERE deleted_at IS NULL AND date >= ? AND date <= ? GROUP BY expense_type ORDER BY total DESC LIMIT 100`,
      ).bind(plan.dateFrom ?? '0000-01-01', plan.dateTo ?? '9999-12-31').all();
      rows = result.results;
    } else if (plan.queryType === 'employee_withdrawals') {
      const result = await env.DB.prepare(
        `SELECT e.name, COALESCE(SUM(sw.amount),0) AS total_withdrawn, COUNT(sw.id) AS entries
         FROM employees e LEFT JOIN salary_withdrawals sw ON sw.employee_id=e.id AND sw.deleted_at IS NULL
         WHERE e.deleted_at IS NULL AND e.name LIKE ? GROUP BY e.id,e.name LIMIT 20`,
      ).bind(`%${plan.employeeName}%`).all();
      rows = result.results;
    } else if (plan.queryType === 'employee_salary') {
      const result = await env.DB.prepare(
        `SELECT e.name, e.basic_salary, COALESCE(SUM(sw.amount),0) AS total_withdrawn,
         e.basic_salary-COALESCE(SUM(sw.amount),0) AS estimated_remaining
         FROM employees e LEFT JOIN salary_withdrawals sw ON sw.employee_id=e.id AND sw.deleted_at IS NULL
         WHERE e.deleted_at IS NULL AND e.name LIKE ? GROUP BY e.id,e.name,e.basic_salary LIMIT 20`,
      ).bind(`%${plan.employeeName}%`).all();
      rows = result.results;
    } else if (plan.queryType === 'rooms_available') {
      const result = await env.DB.prepare(
        `SELECT room_number, type, price, status, cleaning_status FROM rooms
         WHERE deleted_at IS NULL AND status = 'available' ORDER BY room_number LIMIT 200`,
      ).all();
      rows = result.results;
    } else if (plan.queryType === 'rooms_all') {
      const result = await env.DB.prepare(
        `SELECT room_number, type, price, status, cleaning_status, requires_maintenance
         FROM rooms WHERE deleted_at IS NULL ORDER BY room_number LIMIT 300`,
      ).all();
      rows = result.results;
    } else if (plan.queryType === 'current_guests' || plan.queryType === 'bookings_current') {
      const result = await env.DB.prepare(
        `SELECT room_number, guest_name, guest_phone, guest_nationality, checkin_date,
         checkout_date, status, total_due_cached, total_paid_cached, remaining_balance_cached
         FROM bookings WHERE deleted_at IS NULL AND status IN ('active','checked_in','occupied','confirmed')
         ORDER BY room_number LIMIT 300`,
      ).all();
      rows = result.results;
    } else if (plan.queryType === 'guest_search') {
      const needle = plan.guestName || plan.roomNumber || '';
      const result = await env.DB.prepare(
        `SELECT room_number, guest_name, guest_phone, guest_nationality, guest_id_number,
         checkin_date, checkout_date, status, notes
         FROM bookings WHERE deleted_at IS NULL AND (guest_name LIKE ? OR room_number LIKE ?)
         ORDER BY checkin_date DESC LIMIT 50`,
      ).bind(`%${needle}%`, `%${needle}%`).all();
      rows = result.results;
    } else if (plan.queryType === 'daily_summary') {
      const result = await env.DB.prepare(
        `SELECT date, COALESCE(SUM(amount),0) AS total_expenses, COUNT(*) AS entries
         FROM expenses WHERE deleted_at IS NULL AND date >= ? AND date <= ? GROUP BY date ORDER BY date DESC LIMIT 366`,
      ).bind(plan.dateFrom ?? new Date().toISOString().slice(0, 10), plan.dateTo ?? new Date().toISOString().slice(0, 10)).all();
      rows = result.results;
    }
    return jsonResponse({ plan, requires_confirmation: false, answer: plan.explanation, rows });
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

export { jsonResponse };
