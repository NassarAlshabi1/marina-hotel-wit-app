// ═══════════════════════════════════════════════════════════════
//  finance-data.ts — محمل بيانات D1 لمحركات التمويل + مستودع اللقطات
//
//  يجمع «مدخل التمويل» (FinanceInput) من الجداول الحية بنفس فلترة
//  النشطة التي تستخدمها شاشات التطبيق:
//    bookings / expenses / employees / cash_transactions → deleted_at IS NULL
//    payments → + is_voided = 0 (الدفعات الملغاة ليست نقداً محصلاً)
//    rooms → العدد الكلي = الغرف المتاحة
//  ويدير جدول finance_snapshots لاعتماد نسخة أسبوعية مؤرّخة من النموذج
//  (خطوات التحديث الأسبوعي §8) وتتبع «الفعلي مقابل المتوقع».
// ═══════════════════════════════════════════════════════════════

import type { FinanceInput } from './finance';

// ─── تحميل مدخل التمويل من D1 ───────────────────────────────────

export async function loadFinanceInput(db: D1Database): Promise<FinanceInput> {
  const [roomsRes, bookingsRes, paymentsRes, expensesRes, employeesRes, cashRes] =
    await db.batch<
      | { c: number }[]
      | FinanceBookingRow[]
      | FinancePaymentRow[]
      | FinanceExpenseRow[]
      | FinanceEmployeeRow[]
      | FinanceCashRow[]
    >([
      db
        .prepare('SELECT COUNT(*) AS c FROM rooms WHERE deleted_at IS NULL')
        .bind(),
      db
        .prepare(
          `SELECT id AS booking_row_id, checkin_date, checkout_date,
                  actual_checkout, status, calculated_nights,
                  total_due_cached, total_paid_cached
           FROM bookings WHERE deleted_at IS NULL`
        )
        .bind(),
      db
        .prepare(
          `SELECT booking_local_id, amount, payment_date, payment_method, revenue_type
           FROM payments WHERE deleted_at IS NULL AND is_voided = 0`
        )
        .bind(),
      db
        .prepare(
          'SELECT expense_type, amount, date FROM expenses WHERE deleted_at IS NULL'
        )
        .bind(),
      db
        .prepare(
          'SELECT basic_salary, status FROM employees WHERE deleted_at IS NULL'
        )
        .bind(),
      db
        .prepare(
          `SELECT transaction_type, amount, transaction_time
           FROM cash_transactions WHERE deleted_at IS NULL`
        )
        .bind(),
    ]);

  const rooms = roomsRes.results as unknown as { c: number }[];
  const bookings = bookingsRes.results as unknown as FinanceBookingRow[];
  const payments = paymentsRes.results as unknown as FinancePaymentRow[];
  const expenses = expensesRes.results as unknown as FinanceExpenseRow[];
  const employees = employeesRes.results as unknown as FinanceEmployeeRow[];
  const cash = cashRes.results as unknown as FinanceCashRow[];

  return {
    bookings: bookings.map((b) => ({
      booking_row_id: Number(b.booking_row_id),
      checkin_date: String(b.checkin_date ?? ''),
      checkout_date: b.checkout_date == null ? null : String(b.checkout_date),
      actual_checkout: b.actual_checkout == null ? null : String(b.actual_checkout),
      status: String(b.status ?? ''),
      calculated_nights: Number(b.calculated_nights ?? 1),
      total_due_cached: Number(b.total_due_cached ?? 0),
      total_paid_cached: Number(b.total_paid_cached ?? 0),
    })),
    payments: payments.map((p) => ({
      booking_local_id:
        p.booking_local_id == null ? null : Number(p.booking_local_id),
      amount: Number(p.amount ?? 0),
      payment_date: String(p.payment_date ?? ''),
      payment_method: String(p.payment_method ?? ''),
      revenue_type: String(p.revenue_type ?? ''),
    })),
    expenses: expenses.map((e) => ({
      expense_type: String(e.expense_type ?? ''),
      amount: Number(e.amount ?? 0),
      date: String(e.date ?? ''),
    })),
    employees: employees.map((e) => ({
      basic_salary: Number(e.basic_salary ?? 0),
      status: String(e.status ?? ''),
    })),
    cashTransactions: cash.map((t) => ({
      transaction_type: String(t.transaction_type ?? ''),
      amount: Number(t.amount ?? 0),
      transaction_time: String(t.transaction_time ?? ''),
    })),
    totalRooms: rooms[0]?.c ?? 0,
  };
}

// أسماء صفوف D1 الخام قبل التطبيع (snake_case كما في القاعدة)
interface FinanceBookingRow {
  booking_row_id: number;
  checkin_date: string;
  checkout_date: string | null;
  actual_checkout: string | null;
  status: string;
  calculated_nights: number;
  total_due_cached: number;
  total_paid_cached: number;
}
interface FinancePaymentRow {
  booking_local_id: number | null;
  amount: number;
  payment_date: string;
  payment_method: string;
  revenue_type: string;
}
interface FinanceExpenseRow {
  expense_type: string;
  amount: number;
  date: string;
}
interface FinanceEmployeeRow {
  basic_salary: number;
  status: string;
}
interface FinanceCashRow {
  transaction_type: string;
  amount: number;
  transaction_time: string;
}

// ─── مستودع اللقطات الأسبوعية (finance_snapshots) ────────────────

export interface FinanceSnapshotRow {
  id: number;
  label: string;
  scenario_key: string;
  scenario_json: string;
  model_start: string;
  model_end: string;
  opening_balance: number;
  total_inflow: number;
  total_outflow: number;
  financing_need: number;
  weeks_below_threshold: number;
  forecast_json: string;
  approved_by: string;
  approved_at: number;
}

export async function saveFinanceSnapshot(
  db: D1Database,
  snap: {
    label: string;
    scenarioKey: string;
    scenarioJson: string;
    modelStart: string;
    modelEnd: string;
    openingBalance: number;
    totalInflow: number;
    totalOutflow: number;
    financingNeed: number;
    weeksBelowThreshold: number;
    forecastJson: string;
    approvedBy: string;
  }
): Promise<FinanceSnapshotRow> {
  const approvedAt = Date.now();
  const res = await db
    .prepare(
      `INSERT INTO finance_snapshots
         (label, scenario_key, scenario_json, model_start, model_end,
          opening_balance, total_inflow, total_outflow, financing_need,
          weeks_below_threshold, forecast_json, approved_by, approved_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)`
    )
    .bind(
      snap.label,
      snap.scenarioKey,
      snap.scenarioJson,
      snap.modelStart,
      snap.modelEnd,
      snap.openingBalance,
      snap.totalInflow,
      snap.totalOutflow,
      snap.financingNeed,
      snap.weeksBelowThreshold,
      snap.forecastJson,
      snap.approvedBy,
      approvedAt
    )
    .run();

  const id = Number(res.meta?.last_row_id ?? 0);
  return {
    id,
    label: snap.label,
    scenario_key: snap.scenarioKey,
    scenario_json: snap.scenarioJson,
    model_start: snap.modelStart,
    model_end: snap.modelEnd,
    opening_balance: snap.openingBalance,
    total_inflow: snap.totalInflow,
    total_outflow: snap.totalOutflow,
    financing_need: snap.financingNeed,
    weeks_below_threshold: snap.weeksBelowThreshold,
    forecast_json: snap.forecastJson,
    approved_by: snap.approvedBy,
    approved_at: approvedAt,
  };
}

/** سجل مختصر (بدون forecast_json) لقائمة اللقطات. */
export interface FinanceSnapshotMeta {
  id: number;
  label: string;
  scenario_key: string;
  model_start: string;
  model_end: string;
  total_inflow: number;
  total_outflow: number;
  financing_need: number;
  approved_by: string;
  approved_at: number;
}

export async function listFinanceSnapshots(
  db: D1Database,
  limit = 26
): Promise<FinanceSnapshotMeta[]> {
  const capped = Math.min(Math.max(1, limit), 100);
  const res = await db
    .prepare(
      `SELECT id, label, scenario_key, model_start, model_end,
              total_inflow, total_outflow, financing_need,
              approved_by, approved_at
       FROM finance_snapshots
       ORDER BY approved_at DESC, id DESC
       LIMIT ${capped}`
    )
    .all<FinanceSnapshotMeta>();
  return (res.results ?? []).map((r) => ({
    ...r,
    id: Number(r.id),
    total_inflow: Number(r.total_inflow ?? 0),
    total_outflow: Number(r.total_outflow ?? 0),
    financing_need: Number(r.financing_need ?? 0),
    approved_at: Number(r.approved_at ?? 0),
  }));
}

export async function getFinanceSnapshot(
  db: D1Database,
  id: number
): Promise<FinanceSnapshotRow | null> {
  const res = await db
    .prepare('SELECT * FROM finance_snapshots WHERE id = ?1')
    .bind(id)
    .first<FinanceSnapshotRow>();
  return res ?? null;
}
