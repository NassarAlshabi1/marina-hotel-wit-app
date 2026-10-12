// ═══════════════════════════════════════════════════════════════
//  finance.ts — محرك التدفقات النقدية 13 أسبوعاً + مؤشرات الأداء
//
//  يقرأ جداول D1 الحية (bookings / payments / expenses / employees /
//  cash_transactions / rooms) ويحسب على السيرفر نفس منطق محركات Dart
//  في mobile/lib/src/finance (المرآة الرسمية) ليعمل النموذج موحداً
//  عبر كل الأجهزة، مع جدول finance_snapshots لاعتماد نسخة أسبوعية
//  مؤرّخة (خطوات التحديث الأسبوعي 8.1–8.10) وتتبع «الفعلي مقابل
//  المتوقع» بإنذارات 5% / 10%.
//
//  مرجع الألوان: أخضر = مستقر، أصفر = يُراقب (5–10%)، أحمر = إجراء
//  تصحيحي (>10% أو رصيد تحت الحد الأدنى).
//
//  ملاحظات نقل مهمة (فروق مقصودة عن أول تنفيذ Dart):
//  - الحجوزات الملغاة مستبعدة من الإشغال ومن طبقات الداخل (الإلغاء
//    يخفض التدفق المتوقع — جدول المؤشرات §2).
//  - حركات الصندوق income|in كلاهما مقبول (بيانات PHP القديمة).
// ═══════════════════════════════════════════════════════════════

// ─── أدوات التاريخ (جدار زمني موحّد UTC) ────────────────────────

const DAY_MS = 86_400_000;

/**
 * يحلّ أي صيغة تاريخ موجودة في D1 إلى منتصف ليل UTC:
 * '2026-09-27' / '2026-09-27 14:01:00' / '2026-09-27T14:01:00.000'.
 * يعيد null للقيم الفارغة أو الفاسدة (نفس عقد tryParseDate في Dart).
 */
export function parseDate(raw: string | null | undefined): Date | null {
  if (raw == null) return null;
  const s = String(raw).trim();
  if (s.length < 10) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?/.exec(s);
  if (!m) {
    // آخر محاولة: أول 10 أحرف
    const fallback = /^(\d{4})-(\d{2})-(\d{2})/.exec(s.substring(0, 10));
    if (!fallback) return null;
    return new Date(Date.UTC(+fallback[1], +fallback[2] - 1, +fallback[3]));
  }
  return new Date(
    Date.UTC(+m[1], +m[2] - 1, +m[3], +(m[4] ?? 0), +(m[5] ?? 0), +(m[6] ?? 0))
  );
}

/** بداية اليوم (00:00 UTC) — مكافئ dayStart. */
export function dayStart(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

/** عدد الأيام الكاملة بين تاريخين (b − a). */
export function daysBetween(a: Date, b: Date): number {
  return Math.round((dayStart(b).getTime() - dayStart(a).getTime()) / DAY_MS);
}

/** مفتاح يوم yyyy-MM-dd. */
export function toDayKey(d: Date): string {
  const y = String(d.getUTCFullYear()).padStart(4, '0');
  const mo = String(d.getUTCMonth() + 1).padStart(2, '0');
  const da = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${mo}-${da}`;
}

/** بداية النموذج الافتراضية: أول يوم في الشهر القادم (بتوقيت الفندق). */
export function defaultForecastStart(now: Date): Date {
  const y = now.getUTCFullYear();
  const m = now.getUTCMonth();
  return m === 11 ? new Date(Date.UTC(y + 1, 0, 1)) : new Date(Date.UTC(y, m + 1, 1));
}

function isCancelled(status: string): boolean {
  const s = status.trim().toLowerCase();
  return s === 'ملغي' || s === 'cancelled' || s === 'canceled';
}

/** أنواع مصروفات الرواتب — تُستبعد من الخارج لتفادي الاحتساب المزدوج. */
const SALARY_KEYWORDS = ['رواتب', 'سحب راتب', 'سحب من الراتب', 'خصم راتب', 'خصم من الراتب'];

function isSalaryExpenseType(type: string): boolean {
  for (const k of SALARY_KEYWORDS) if (type.includes(k)) return true;
  return false;
}

// ─── صفوف الإدخال (أعمدة D1 المستخدمة فقط) ──────────────────────

export interface BookingRow {
  /** الصف الرقمي في D1 (bookings.id) — تربط به المدفوعات عبر booking_local_id */
  booking_row_id: number;
  checkin_date: string;
  checkout_date: string | null;
  actual_checkout: string | null;
  status: string;
  calculated_nights: number;
  total_due_cached: number;
  total_paid_cached: number;
}

export interface PaymentRow {
  booking_local_id: number | null;
  amount: number;
  payment_date: string;
  payment_method: string;
  revenue_type: string;
}

export interface ExpenseRow {
  expense_type: string;
  amount: number;
  date: string;
}

export interface EmployeeRow {
  basic_salary: number;
  status: string;
}

export interface CashTransactionRow {
  transaction_type: string;
  amount: number;
  transaction_time: string;
}

export interface FinanceInput {
  bookings: BookingRow[];
  payments: PaymentRow[];
  expenses: ExpenseRow[];
  employees: EmployeeRow[];
  cashTransactions: CashTransactionRow[];
  totalRooms: number;
}

// ─── ملف التحصيل ────────────────────────────────────────────────

export interface PaymentMethodProfile {
  method: string;
  share: number;
  lagDays: number;
  sampleCount: number;
}

export interface PaymentProfile {
  methods: PaymentMethodProfile[];
  historicalOccupancy: number;
  historicalAdr: number;
  sampleDays: number;
}

/** هل يشغل هذا الحجز ليلة اليوم؟ (دخول ≤ اليوم والمغادرة بعده) */
export function occupiesOnDay(b: BookingRow, day: Date): boolean {
  const checkin = parseDate(b.checkin_date);
  if (!checkin) return false;
  if (day.getTime() < dayStart(checkin).getTime()) return false;
  let out: Date | null = null;
  const actual = b.actual_checkout?.trim();
  if (actual) out = parseDate(actual);
  if (!out && b.checkout_date?.trim()) out = parseDate(b.checkout_date);
  if (!out) out = new Date(dayStart(checkin).getTime() + Math.max(1, b.calculated_nights) * DAY_MS);
  return dayStart(out).getTime() > day.getTime();
}

/** المغادرة الفعلية المتوقعة مع البدائل المنطقية. */
function effectiveCheckout(b: BookingRow, checkin: Date): Date {
  const actual = b.actual_checkout?.trim();
  if (actual) {
    const d = parseDate(actual);
    if (d) return d;
  }
  const planned = b.checkout_date?.trim();
  if (planned) {
    const d = parseDate(planned);
    if (d) return d;
  }
  return new Date(dayStart(checkin).getTime() + Math.max(1, b.calculated_nights) * DAY_MS);
}

/**
 * يبني ملف التحصيل من المدفوعات الفعلية: توزيع الوسائل (90 يوماً)،
 * أيام التأخر المقاسة (الدخول → دخول النقد)، الإشغال وADR (30 يوماً).
 */
export function analyzePaymentProfile(
  input: FinanceInput,
  now: Date,
  lookbackDays = 90,
  occupancyDays = 30
): PaymentProfile {
  const today = dayStart(now);
  const lookbackStart = new Date(today.getTime() - lookbackDays * DAY_MS);
  const occStart = new Date(today.getTime() - occupancyDays * DAY_MS);

  // فهرس الدخول لكل حجز (لتقدير أيام التأخر)
  const checkinByBookingId = new Map<number, Date>();
  for (const b of input.bookings) {
    const ci = parseDate(b.checkin_date);
    if (ci) checkinByBookingId.set(b.booking_row_id, ci);
  }

  const amountByMethod = new Map<string, number>();
  const countByMethod = new Map<string, number>();
  const lagSumByMethod = new Map<string, number>();
  const lagCountByMethod = new Map<string, number>();

  for (const p of input.payments) {
    const pd = parseDate(p.payment_date);
    if (!pd || pd.getTime() < lookbackStart.getTime()) continue;
    const method = p.payment_method?.trim() ? p.payment_method.trim() : 'غير محدد';
    amountByMethod.set(method, (amountByMethod.get(method) ?? 0) + p.amount);
    countByMethod.set(method, (countByMethod.get(method) ?? 0) + 1);

    if (p.booking_local_id != null) {
      const ci = checkinByBookingId.get(p.booking_local_id);
      if (ci) {
        const lag = daysBetween(ci, pd);
        lagSumByMethod.set(method, (lagSumByMethod.get(method) ?? 0) + (lag < 0 ? 0 : lag));
        lagCountByMethod.set(method, (lagCountByMethod.get(method) ?? 0) + 1);
      }
    }
  }

  let grandTotal = 0;
  for (const v of amountByMethod.values()) grandTotal += v;

  const methods: PaymentMethodProfile[] = [];
  if (grandTotal > 0) {
    for (const [method, amount] of amountByMethod) {
      const lagCount = lagCountByMethod.get(method) ?? 0;
      const lagAvg =
        lagCount > 0 ? Math.round((lagSumByMethod.get(method) ?? 0) / lagCount) : 0;
      methods.push({
        method,
        share: amount / grandTotal,
        // النقد فوري دائماً — باقي الوسائل وفق التأخر المقاس.
        lagDays: method === 'نقدي' ? 0 : lagAvg,
        sampleCount: countByMethod.get(method) ?? 0,
      });
    }
    methods.sort((a, b) => b.share - a.share);
  }

  // الإشغال التاريخي (آخر occupancyDays يوماً حتى اليوم) + ADR
  const activeBookings = input.bookings.filter(
    (b) => !isCancelled(b.status)
  );
  let soldNights = 0;
  for (let i = 0; i < occupancyDays; i++) {
    const day = new Date(today.getTime() - (occupancyDays - 1 - i) * DAY_MS);
    for (const b of activeBookings) {
      if (occupiesOnDay(b, day)) soldNights++;
    }
  }
  const availableNights = Math.max(1, input.totalRooms) * occupancyDays;
  const occupancy = Math.min(1, Math.max(0, soldNights / availableNights));

  let roomRevenue = 0;
  for (const p of input.payments) {
    const pd = parseDate(p.payment_date);
    if (!pd || pd.getTime() < occStart.getTime()) continue;
    if (p.revenue_type === 'room') roomRevenue += p.amount;
  }
  const adr = soldNights > 0 ? roomRevenue / soldNights : 0;

  if (methods.length === 0) {
    return {
      methods: [{ method: 'نقدي', share: 1, lagDays: 0, sampleCount: 0 }],
      historicalOccupancy: occupancy,
      historicalAdr: adr,
      sampleDays: occupancyDays,
    };
  }
  return { methods, historicalOccupancy: occupancy, historicalAdr: adr, sampleDays: occupancyDays };
}

// ─── السيناريوهات ───────────────────────────────────────────────

export interface ScenarioParams {
  key: string;
  name: string;
  revenueFactor: number;
  collectionFactor: number;
}

export const SCENARIOS: Record<string, ScenarioParams> = {
  base: { key: 'base', name: 'أساسي', revenueFactor: 1.0, collectionFactor: 1.0 },
  conservative: { key: 'conservative', name: 'متحفظ', revenueFactor: 0.9, collectionFactor: 0.85 },
  stress: { key: 'stress', name: 'ضغط', revenueFactor: 0.8, collectionFactor: 0.7 },
};

// ─── نموذج الـ13 أسبوعاً ─────────────────────────────────────────

export interface WeeklyInflow {
  confirmed: number;
  probable: number;
  estimated: number;
}

export interface WeeklyOutflow {
  salaries: number;
  diesel: number;
  utilities: number;
  maintenance: number;
  other: number;
}

export interface WeekForecast {
  index: number;
  start: string; // yyyy-MM-dd
  end: string;
  inflow: WeeklyInflow;
  outflow: WeeklyOutflow;
  openingBalance: number;
  closingBalance: number;
  avgWeeklyOutflow: number;
  liquidityThreshold: number;
  netFlow: number;
  surplusOverThreshold: number;
  coverageWeeks: number;
  financingNeed: number;
  /** good | warning | danger */
  status: 'good' | 'warning' | 'danger';
}

export interface ForecastResult {
  scenario: ScenarioParams;
  start: string;
  generatedAt: string;
  openingBalance: number;
  avgWeeklyOutflow: number;
  liquidityThreshold: number;
  coverageTargetWeeks: number;
  weeks: WeekForecast[];
  paymentProfile: PaymentProfile;
  totalInflow: number;
  totalOutflow: number;
  financingNeed: number;
  weeksBelowThreshold: number;
  worstWeek: { index: number; closingBalance: number } | null;
}

function weeklyOutflow(
  expenses: ExpenseRow[],
  employees: EmployeeRow[],
  forecastStart: Date,
  lookbackDays: number
): WeeklyOutflow {
  let monthlySalaries = 0;
  for (const e of employees) {
    const st = (e.status ?? '').trim();
    if (st.toLowerCase() === 'active' || st === 'نشط') monthlySalaries += e.basic_salary;
  }
  const salariesWeekly = monthlySalaries / 4.33;

  const historyStart = new Date(dayStart(forecastStart).getTime() - lookbackDays * DAY_MS);
  let diesel = 0, utilities = 0, maintenance = 0, other = 0;
  for (const e of expenses) {
    if (isSalaryExpenseType(e.expense_type)) continue;
    const d = parseDate(e.date);
    if (!d || d.getTime() < historyStart.getTime() || d.getTime() >= dayStart(forecastStart).getTime()) continue;
    const t = e.expense_type.trim();
    if (t.includes('ديزل')) diesel += e.amount;
    else if (t.includes('كهرباء') || t.includes('مياه') || t.includes('فاتورة')) utilities += e.amount;
    else if (t.includes('صيانة')) maintenance += e.amount;
    else other += e.amount;
  }
  const weeksFactor = lookbackDays / 7;
  return {
    salaries: salariesWeekly,
    diesel: diesel / weeksFactor,
    utilities: utilities / weeksFactor,
    maintenance: maintenance / weeksFactor,
    other: other / weeksFactor,
  };
}

function weekIndexOf(date: Date, start: Date, weeksCount: number): number {
  const idx = Math.floor(daysBetween(start, date) / 7);
  return idx < 0 || idx >= weeksCount ? -1 : idx;
}

/**
 * يبني نموذج الـ13 أسبوعاً لسيناريو واحد من بيانات D1 الحية.
 * الداخل بثلاث طبقات يقين (مؤكد لا يُخفض / مرجّح / تقديري)، الخارج
 * التزامات أسبوعية ثابتة، والرصيد متدحرج مع حد أدنى ديناميكي.
 */
export function buildForecast(
  input: FinanceInput,
  scenario: ScenarioParams,
  profile: PaymentProfile,
  now: Date,
  opts: { forecastStart?: Date; weeksCount?: number; coverageTargetWeeks?: number; expenseLookbackDays?: number } = {}
): ForecastResult {
  const weeksCount = opts.weeksCount ?? 13;
  const coverageTargetWeeks = opts.coverageTargetWeeks ?? 4;
  const lookbackDays = opts.expenseLookbackDays ?? 60;
  const start = dayStart(opts.forecastStart ?? defaultForecastStart(now));
  const startMs = start.getTime();

  // رصيد البداية: كل النقد قبل بداية النموذج (نفس منطق «الصندوق»)
  let openingBalance = 0;
  for (const p of input.payments) {
    const d = parseDate(p.payment_date);
    if (d && d.getTime() < startMs) openingBalance += p.amount;
  }
  for (const e of input.expenses) {
    const d = parseDate(e.date);
    if (d && d.getTime() < startMs) openingBalance -= e.amount;
  }

  const outflow = weeklyOutflow(input.expenses, input.employees, start, lookbackDays);
  const avgWeeklyOutflow =
    outflow.salaries + outflow.diesel + outflow.utilities + outflow.maintenance + outflow.other;
  const threshold = avgWeeklyOutflow * coverageTargetWeeks;

  const confirmedByWeek = new Array<number>(weeksCount).fill(0);
  const probableByWeek = new Array<number>(weeksCount).fill(0);
  const estimatedByWeek = new Array<number>(weeksCount).fill(0);
  const bookedNightsByDay = new Array<number>(7 * weeksCount).fill(0);

  const activeBookings = input.bookings.filter((b) => !isCancelled(b.status));

  for (const b of activeBookings) {
    const checkin = parseDate(b.checkin_date);
    if (!checkin) continue;
    const checkout = effectiveCheckout(b, checkin);
    const rawRemaining = (b.total_due_cached ?? 0) - (b.total_paid_cached ?? 0);
    const remaining = rawRemaining > 0 ? rawRemaining : 0;

    // ليالي الإشغال داخل نافذة النموذج
    for (let d = 0; d < 7 * weeksCount; d++) {
      const day = new Date(startMs + d * DAY_MS);
      if (
        day.getTime() >= dayStart(checkin).getTime() &&
        dayStart(checkout).getTime() > day.getTime()
      ) {
        bookedNightsByDay[d]++;
      }
    }

    if (remaining <= 0) continue;
    if (dayStart(checkout).getTime() <= startMs) continue; // انتهى قبل النموذج

    // توقيت التحصيل: نزيل حالي → أسبوع المغادرة؛ حجز قادم → أسبوع الدخول
    const isCurrentGuest = dayStart(checkin).getTime() < startMs;
    const anchor = isCurrentGuest ? checkout : checkin;
    const weekIdx = weekIndexOf(anchor, start, weeksCount);
    if (weekIdx < 0) continue;

    if (isCurrentGuest || (b.total_paid_cached ?? 0) > 0) {
      confirmedByWeek[weekIdx] += remaining;
    } else {
      probableByWeek[weekIdx] += remaining;
    }
  }

  // معاملات السيناريو: المؤكد لا يُخفض — المرجّح والتقديري يتأثران.
  const probableFactor = scenario.revenueFactor * scenario.collectionFactor;
  for (let i = 0; i < weeksCount; i++) probableByWeek[i] *= probableFactor;

  // التدفق التقديري: الليالي غير المحجوزة × الإشغال × ADR
  const availableRooms = Math.max(0, input.totalRooms);
  if (availableRooms > 0 && profile.historicalAdr > 0) {
    const expectedSoldPerDay = availableRooms * profile.historicalOccupancy;
    for (let d = 0; d < 7 * weeksCount; d++) {
      const incrementalNights = Math.min(
        Math.max(0, expectedSoldPerDay - bookedNightsByDay[d]),
        availableRooms
      );
      if (incrementalNights <= 0) continue;
      const dayRevenue = incrementalNights * profile.historicalAdr;
      const day = new Date(startMs + d * DAY_MS);
      for (const m of profile.methods) {
        const cashDate = new Date(day.getTime() + m.lagDays * DAY_MS);
        const wIdx = weekIndexOf(cashDate, start, weeksCount);
        if (wIdx < 0) continue;
        estimatedByWeek[wIdx] += dayRevenue * m.share;
      }
    }
    for (let i = 0; i < weeksCount; i++) estimatedByWeek[i] *= probableFactor;
  }

  // بناء الأسابيع بالرصيد المتدحرج
  const weeks: WeekForecast[] = [];
  let rolling = openingBalance;
  for (let i = 0; i < weeksCount; i++) {
    const inflow: WeeklyInflow = {
      confirmed: confirmedByWeek[i],
      probable: probableByWeek[i],
      estimated: estimatedByWeek[i],
    };
    const inflowTotal = inflow.confirmed + inflow.probable + inflow.estimated;
    const outflowTotal = avgWeeklyOutflow;
    const opening = rolling;
    rolling = opening + inflowTotal - outflowTotal;
    const surplus = rolling - threshold;
    const coverage = avgWeeklyOutflow <= 0 ? 99 : rolling / avgWeeklyOutflow;
    weeks.push({
      index: i + 1,
      start: toDayKey(new Date(startMs + i * 7 * DAY_MS)),
      end: toDayKey(new Date(startMs + (i * 7 + 6) * DAY_MS)),
      inflow,
      outflow: { ...outflow },
      openingBalance: opening,
      closingBalance: rolling,
      avgWeeklyOutflow,
      liquidityThreshold: threshold,
      netFlow: inflowTotal - outflowTotal,
      surplusOverThreshold: surplus,
      coverageWeeks: coverage,
      financingNeed: surplus < 0 ? -surplus : 0,
      status: rolling < 0 || surplus < 0 ? 'danger' : coverage < 4 ? 'warning' : 'good',
    });
  }

  const totalInflow = weeks.reduce((s, w) => s + w.inflow.confirmed + w.inflow.probable + w.inflow.estimated, 0);
  const totalOutflow = weeks.reduce((s, w) => s + w.outflow.salaries + w.outflow.diesel + w.outflow.utilities + w.outflow.maintenance + w.outflow.other, 0);
  const financingNeed = weeks.reduce((m, w) => Math.max(m, w.financingNeed), 0);
  const weeksBelowThreshold = weeks.filter((w) => w.surplusOverThreshold < 0).length;
  const worst = weeks.length > 0 ? weeks.reduce((a, b) => (b.closingBalance < a.closingBalance ? b : a)) : null;

  return {
    scenario: { ...scenario },
    start: toDayKey(start),
    generatedAt: new Date(now.getTime()).toISOString(),
    openingBalance,
    avgWeeklyOutflow,
    liquidityThreshold: threshold,
    coverageTargetWeeks,
    weeks,
    paymentProfile: profile,
    totalInflow,
    totalOutflow,
    financingNeed,
    weeksBelowThreshold,
    worstWeek: worst ? { index: worst.index, closingBalance: worst.closingBalance } : null,
  };
}

// ─── لوحة المؤشرات الأسبوعية (16 مؤشراً) ────────────────────────

export type AlertLevel = 'good' | 'warning' | 'danger' | 'unknown';

export interface KpiEntry {
  label: string;
  hint: string;
  currentText: string;
  previousText: string;
  targetText: string;
  status: AlertLevel;
}

export interface KpiSnapshotResult {
  generatedAt: string;
  currentPeriodText: string;
  previousPeriodText: string;
  rows: KpiEntry[];
}

interface PeriodStats {
  soldNights: number;
  daysCount: number;
  collected: number;
  roomRevenue: number;
  cashIncome: number;
  expensesTotal: number;
  salaries: number;
  diesel: number;
  other: number;
  dueMatured: number;

  readonly occupancy: number;
  readonly adr: number;
  revpar(rooms: number): number;
  readonly collectionRate: number;
  readonly netFlow: number;
  readonly cashDiff: number;
  readonly revenueDiff: number;
  readonly salariesRatio: number;
  readonly dieselRatio: number;
  readonly otherRatio: number;
  /** الغرف المتاحة — يُضبط من computeKpi بعد الإنشاء (مطلوب للإشغال وRevPAR) */
  totalRoomsRef: number;
}

function periodStats(
  input: FinanceInput,
  from: Date,
  to: Date
): PeriodStats {
  const activeBookings = input.bookings.filter((b) => !isCancelled(b.status));

  // الليالي المباعة: احتلال فعلي لكل يوم في الفترة
  let soldNights = 0;
  const daysCount = daysBetween(from, to) + 1;
  for (let d = 0; d < daysCount; d++) {
    const day = new Date(dayStart(from).getTime() + d * DAY_MS);
    for (const b of activeBookings) {
      if (occupiesOnDay(b, day)) soldNights++;
    }
  }

  let collected = 0, roomRevenue = 0, cashIncome = 0;
  const fromMs = dayStart(from).getTime();
  const toMs = dayStart(to).getTime();
  for (const p of input.payments) {
    const d = parseDate(p.payment_date);
    if (!d) continue;
    const ds = dayStart(d).getTime();
    if (ds < fromMs || ds > toMs) continue;
    collected += p.amount;
    if (p.revenue_type === 'room') roomRevenue += p.amount;
  }
  for (const t of input.cashTransactions) {
    if (t.transaction_type !== 'income' && t.transaction_type !== 'in') continue;
    const d = parseDate(t.transaction_time);
    if (!d) continue;
    const ds = dayStart(d).getTime();
    if (ds < fromMs || ds > toMs) continue;
    cashIncome += t.amount;
  }

  let expensesTotal = 0, salaries = 0, diesel = 0, other = 0;
  for (const e of input.expenses) {
    const d = parseDate(e.date);
    if (!d) continue;
    const ds = dayStart(d).getTime();
    if (ds < fromMs || ds > toMs) continue;
    expensesTotal += e.amount;
    const t = e.expense_type.trim();
    if (t.includes('رواتب') || t.includes('راتب')) salaries += e.amount;
    else if (t.includes('ديزل')) diesel += e.amount;
    else if (t.includes('كهرباء') || t.includes('مياه') || t.includes('صيانة') || t.includes('فاتورة')) {
      // فئات مصنفة — لا تدخل «أخرى»
    } else other += e.amount;
  }

  // المستحق: حجوزات انتهت إقامتها داخل الفترة
  let dueMatured = 0;
  for (const b of activeBookings) {
    const ci = parseDate(b.checkin_date);
    if (!ci) continue;
    const out = effectiveCheckout(b, ci);
    const outs = dayStart(out).getTime();
    if (outs >= fromMs && outs <= toMs) dueMatured += b.total_due_cached ?? 0;
  }

  const totalRoomsAt = (rooms: number) => rooms * daysCount;
  const s: PeriodStats = {
    soldNights,
    daysCount,
    collected,
    roomRevenue,
    cashIncome,
    expensesTotal,
    salaries,
    diesel,
    other,
    dueMatured,
    get occupancy() {
      const available = totalRoomsAt(s.totalRoomsRef);
      return available <= 0 ? 0 : Math.min(1, Math.max(0, soldNights / available));
    },
    get adr() {
      return soldNights > 0 ? roomRevenue / soldNights : 0;
    },
    revpar(rooms: number) {
      return rooms <= 0 ? 0 : roomRevenue / totalRoomsAt(rooms);
    },
    get collectionRate() {
      return dueMatured > 0 ? Math.min(10, Math.max(0, collected / dueMatured)) : 0;
    },
    get netFlow() {
      return collected - expensesTotal;
    },
    get cashDiff() {
      return cashIncome - collected;
    },
    get revenueDiff() {
      return dueMatured - collected;
    },
    get salariesRatio() {
      return collected <= 0 ? 0 : salaries / collected;
    },
    get dieselRatio() {
      return collected <= 0 ? 0 : diesel / collected;
    },
    get otherRatio() {
      return expensesTotal <= 0 ? 0 : other / expensesTotal;
    },
    totalRoomsRef: 0,
  };
  return s;
}

function fmtNum(v: number): string {
  return Math.round(v).toLocaleString('en-US');
}
function fmtPct(v: number): string {
  return `${v.toLocaleString('en-US', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`;
}
function fmtDay(d: Date): string {
  return `${d.getUTCDate()}/${d.getUTCMonth() + 1}`;
}

function bands(value: number, greenMax: number, yellowMax: number, higherIsWorse = false): AlertLevel {
  if (higherIsWorse) {
    if (value <= greenMax) return 'good';
    if (value <= yellowMax) return 'warning';
    return 'danger';
  }
  if (value >= greenMax) return 'good';
  if (value >= yellowMax) return 'warning';
  return 'danger';
}

function trend(current: number, previous: number, floor: number): AlertLevel {
  if (previous <= 0) return 'unknown';
  const ratio = current / previous;
  if (ratio >= floor) return 'good';
  if (ratio >= floor - 0.1) return 'warning';
  return 'danger';
}

function inverseTrend(current: number, previous: number, ceil: number): AlertLevel {
  if (previous <= 0) return 'unknown';
  const ratio = current / previous;
  if (ratio <= ceil) return 'good';
  if (ratio <= ceil + 0.1) return 'warning';
  return 'danger';
}

function zeroTolerance(diff: number, base: number, tol: number): AlertLevel {
  const a = Math.abs(diff);
  if (a <= 1) return 'good';
  const rel = base > 0 ? a / base : a;
  if (rel <= tol) return 'warning';
  return 'danger';
}

/**
 * يحسب لوحة المؤشرات: آخر 7 أيام مقابل السابقة، مع الرصيد التراكمي
 * ومتوسط الخارج (28 يوماً) وحد السيولة.
 */
export function computeKpi(
  input: FinanceInput,
  now: Date,
  forecastWeek1ConfirmedRatio: number | null,
  coverageTargetWeeks = 4
): KpiSnapshotResult {
  const today = dayStart(now);
  const curStart = new Date(today.getTime() - 6 * DAY_MS);
  const prevStart = new Date(today.getTime() - 13 * DAY_MS);
  const prevEnd = new Date(curStart.getTime() - 1 * DAY_MS);

  const cur = periodStats(input, curStart, today);
  const prev = periodStats(input, prevStart, prevEnd);
  // الغرف المتاحة تُمرَّر داخل الإحصاء عبر الإدخال
  cur.totalRoomsRef = input.totalRooms;
  prev.totalRoomsRef = input.totalRooms;

  // الرصيد النقدي الحالي (كل التاريخ) — نفس منطق «الصندوق»
  let cashBalance = 0;
  for (const p of input.payments) cashBalance += p.amount;
  for (const e of input.expenses) cashBalance -= e.amount;

  // متوسط الخارج الأسبوعي (آخر 28 يوماً)
  const start28 = new Date(today.getTime() - 27 * DAY_MS);
  let out28 = 0;
  for (const e of input.expenses) {
    const d = parseDate(e.date);
    if (d) {
      const ds = dayStart(d).getTime();
      if (ds >= start28.getTime() && ds <= today.getTime()) out28 += e.amount;
    }
  }
  const avgWeeklyOutflow = out28 / 4;
  const minLiquidity = avgWeeklyOutflow * coverageTargetWeeks;

  const coverageNow = avgWeeklyOutflow <= 0 ? 99 : cashBalance / avgWeeklyOutflow;
  const ratio = forecastWeek1ConfirmedRatio;

  const rows: KpiEntry[] = [
    {
      label: 'الإشغال',
      hint: 'الليالي المباعة ÷ الليالي المتاحة',
      currentText: fmtPct(cur.occupancy * 100),
      previousText: fmtPct(prev.occupancy * 100),
      targetText: '≥ 60%',
      status: bands(cur.occupancy * 100, 60, 40),
    },
    {
      label: 'ADR (متوسط سعر الغرفة)',
      hint: 'إيراد الغرف ÷ الليالي المباعة',
      currentText: fmtNum(cur.adr),
      previousText: fmtNum(prev.adr),
      targetText: 'ثبات أو ارتفاع',
      status: trend(cur.adr, prev.adr, 0.9),
    },
    {
      label: 'RevPAR',
      hint: 'إيراد الغرف ÷ الغرف المتاحة',
      currentText: fmtNum(cur.revpar(input.totalRooms)),
      previousText: fmtNum(prev.revpar(input.totalRooms)),
      targetText: 'ثبات أو ارتفاع',
      status: trend(cur.revpar(input.totalRooms), prev.revpar(input.totalRooms), 0.9),
    },
    {
      label: 'إيراد الغرف',
      hint: 'مدفوعات revenueType = room',
      currentText: fmtNum(cur.roomRevenue),
      previousText: fmtNum(prev.roomRevenue),
      targetText: 'ثبات أو ارتفاع',
      status: trend(cur.roomRevenue, prev.roomRevenue, 0.9),
    },
    {
      label: 'النقد المحصل',
      hint: 'إجمالي المدفوعات النشطة بالفترة',
      currentText: fmtNum(cur.collected),
      previousText: fmtNum(prev.collected),
      targetText: 'ثبات أو ارتفاع',
      status: trend(cur.collected, prev.collected, 0.9),
    },
    {
      label: 'نسبة التحصيل',
      hint: 'المحصل ÷ المستحق للحجوزات المستحقة',
      currentText: fmtPct(cur.collectionRate * 100),
      previousText: fmtPct(prev.collectionRate * 100),
      targetText: '≥ 95%',
      status: bands(cur.collectionRate * 100, 95, 85),
    },
    {
      label: 'إجمالي المصروفات',
      hint: 'مصروفات الفترة النشطة',
      currentText: fmtNum(cur.expensesTotal),
      previousText: fmtNum(prev.expensesTotal),
      targetText: 'لا يرتفع أكثر من 10%',
      status: inverseTrend(cur.expensesTotal, prev.expensesTotal, 1.1),
    },
    {
      label: 'الرواتب ÷ الإيرادات',
      hint: 'تكلفة العمالة مقابل النقد المحصل',
      currentText: fmtPct(cur.salariesRatio * 100),
      previousText: fmtPct(prev.salariesRatio * 100),
      targetText: '≤ 15% (مرجعي 11.8%)',
      status: bands(cur.salariesRatio * 100, 15, 25, true),
    },
    {
      label: 'الديزل ÷ الإيرادات',
      hint: 'كفاءة استهلاك الطاقة مقابل النقد المحصل',
      currentText: fmtPct(cur.dieselRatio * 100),
      previousText: fmtPct(prev.dieselRatio * 100),
      targetText: '≤ 15% (مرجعي 12.2%)',
      status: bands(cur.dieselRatio * 100, 15, 25, true),
    },
    {
      label: '«أخرى» ÷ المصروفات',
      hint: 'مؤشر جودة التصنيف المحاسبي',
      currentText: fmtPct(cur.otherRatio * 100),
      previousText: fmtPct(prev.otherRatio * 100),
      targetText: '< 5%',
      status: bands(cur.otherRatio * 100, 5, 15, true),
    },
    {
      label: 'صافي التدفق الأسبوعي',
      hint: 'الداخل − الخارج',
      currentText: fmtNum(cur.netFlow),
      previousText: fmtNum(prev.netFlow),
      targetText: 'موجب',
      status: cur.netFlow > 0 ? 'good' : cur.netFlow === 0 ? 'warning' : 'danger',
    },
    {
      label: 'الرصيد آخر الأسبوع',
      hint: 'رصيد الصندوق التراكمي',
      currentText: fmtNum(cashBalance),
      previousText: fmtNum(cashBalance - cur.netFlow),
      targetText: `فوق ${fmtNum(minLiquidity)} (الحد الأدنى)`,
      status: cashBalance >= minLiquidity ? 'good' : cashBalance >= 0 ? 'warning' : 'danger',
    },
    {
      label: 'أسابيع التغطية',
      hint: 'الرصيد ÷ متوسط الخارج الأسبوعي',
      currentText: `${fmtPct(coverageNow)} أسبوع تقريباً`,
      previousText: '—',
      targetText: `≥ ${coverageTargetWeeks} أسابيع`,
      status: bands(coverageNow, coverageTargetWeeks, 2),
    },
    {
      label: 'فرق الصندوق',
      hint: 'حركات الصندوق − المدفوعات المسجلة (فحص تسجيل)',
      currentText: fmtNum(cur.cashDiff),
      previousText: fmtNum(prev.cashDiff),
      targetText: 'صفر',
      status: zeroTolerance(cur.cashDiff, cur.collected, 0.05),
    },
    {
      label: 'فرق الإيرادات',
      hint: 'المستحق − المحصل (العربون المقدَّم قد يفسر الفرق)',
      currentText: fmtNum(cur.revenueDiff),
      previousText: fmtNum(prev.revenueDiff),
      targetText: 'صفر أو مبرر',
      status: zeroTolerance(cur.revenueDiff, cur.dueMatured > 0 ? cur.dueMatured : 1, 0.1),
    },
    {
      label: 'التدفق المؤكد ÷ الإجمالي',
      hint: 'جودة التوقع — الأسبوع الأول من نموذج الـ13 أسبوعاً',
      currentText: ratio == null ? '—' : fmtPct(ratio * 100),
      previousText: '—',
      targetText: '> 80%',
      status: ratio == null ? 'unknown' : bands(ratio * 100, 80, 60),
    },
  ];

  return {
    generatedAt: new Date(now.getTime()).toISOString(),
    currentPeriodText: `${fmtDay(curStart)} — ${fmtDay(today)}`,
    previousPeriodText: `${fmtDay(prevStart)} — ${fmtDay(prevEnd)}`,
    rows,
  };
}

// ─── الفعلي مقابل المتوقع (خطوات التحديث الأسبوعي §8) ───────────

export interface VarianceWeek {
  index: number;
  start: string;
  end: string;
  forecast: { inflow: number; outflow: number; netFlow: number };
  actual: { inflow: number; outflow: number; netFlow: number } | null;
  variancePct: { inflow: number | null; outflow: number | null; netFlow: number | null };
  /** green ≤5% | yellow ≤10% | red >10% | unknown أسبوع غير مكتمل */
  status: 'green' | 'yellow' | 'red' | 'unknown';
}

export interface VarianceResult {
  snapshotId: number;
  label: string;
  approvedAt: string;
  weeks: VarianceWeek[];
}

function varianceLevel(forecast: number, actual: number): { pct: number | null; level: 'green' | 'yellow' | 'red' | 'unknown' } {
  const denom = Math.abs(forecast);
  if (denom < 1) {
    // متوقع صفري تقريباً: أي فعلي جوهري غير مبرر بالأحمر
    return { pct: null, level: Math.abs(actual) < 1 ? 'green' : 'red' };
  }
  const pct = ((actual - forecast) / denom) * 100;
  const abs = Math.abs(pct);
  return { pct, level: abs <= 5 ? 'green' : abs <= 10 ? 'yellow' : 'red' };
}

/**
 * يقارن أسبوع النسخة المعتمدة المنتهية فعلياً (نهايته قبل اليوم) مع
 * الحركات الحقيقية في D1 — نفس أسبوع النموذج بالضبط.
 */
export function computeVariance(
  snapshotId: number,
  label: string,
  approvedAt: string,
  snapshotForecast: ForecastResult,
  input: FinanceInput,
  now: Date
): VarianceResult {
  const todayMs = dayStart(now).getTime();
  const weeks: VarianceWeek[] = [];

  for (const w of snapshotForecast.weeks) {
    const ws = parseDate(w.start);
    const we = parseDate(w.end);
    if (!ws || !we) continue;
    const wEndMs = dayStart(we).getTime();
    if (wEndMs >= todayMs) continue; // أسبوع غير منتهٍ — لا فعلي بعد

    const wStartMs = dayStart(ws).getTime();
    let actualIn = 0;
    for (const p of input.payments) {
      const d = parseDate(p.payment_date);
      if (d) {
        const ds = dayStart(d).getTime();
        if (ds >= wStartMs && ds <= wEndMs) actualIn += p.amount;
      }
    }
    let actualOut = 0;
    for (const e of input.expenses) {
      const d = parseDate(e.date);
      if (d) {
        const ds = dayStart(d).getTime();
        if (ds >= wStartMs && ds <= wEndMs) actualOut += e.amount;
      }
    }
    const fIn = w.inflow.confirmed + w.inflow.probable + w.inflow.estimated;
    const fOut = w.outflow.salaries + w.outflow.diesel + w.outflow.utilities + w.outflow.maintenance + w.outflow.other;
    const fNet = fIn - fOut;
    const aNet = actualIn - actualOut;

    const vIn = varianceLevel(fIn, actualIn);
    const vOut = varianceLevel(fOut, actualOut);
    const vNet = varianceLevel(fNet, aNet);

    // حالة الأسبوع تُحتكم على صافي التدفق أولاً (مؤشر القرار)
    let status: VarianceWeek['status'] = vNet.level;
    if (status === 'green' && (vIn.level === 'red' || vOut.level === 'red')) status = 'yellow';

    weeks.push({
      index: w.index,
      start: w.start,
      end: w.end,
      forecast: { inflow: fIn, outflow: fOut, netFlow: fNet },
      actual: { inflow: actualIn, outflow: actualOut, netFlow: aNet },
      variancePct: { inflow: vIn.pct, outflow: vOut.pct, netFlow: vNet.pct },
      status,
    });
  }

  return { snapshotId, label, approvedAt, weeks };
}
