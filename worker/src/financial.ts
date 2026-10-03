import type { D1Database, D1PreparedStatement } from '@cloudflare/workers-types';
import type { AuthContext } from './auth';

export class FinancialPolicyError extends Error {}
export const isPostedFinancialEntity = (entity: string) => entity === 'expenses' || entity === 'salary_withdrawals';

/** Aden UTC+3, hotel day changes at 14:01, independent of client clock/timezone. */
export function financialHotelDay(now = Date.now()): string {
  return new Date(now + 3 * 3600_000 - (14 * 60 + 1) * 60_000).toISOString().slice(0, 10);
}
function reasonText(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length < 3 || value.trim().length > 500) {
    throw new FinancialPolicyError('سبب التصحيح مطلوب (3–500 حرف)');
  }
  return value.trim();
}
function validDay(day: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(day) && Number.isFinite(Date.parse(day)) && new Date(day).toISOString().slice(0, 10) === day;
}
export async function financialPolicy(db: D1Database) {
  const row = await db.prepare('SELECT closed_through FROM financial_period_lock WHERE id = 1').first<{closed_through: string}>();
  if (!row) throw new Error('Financial migration 0015 is required');
  return { ...row, hotel_day_key: financialHotelDay(), saved_entries_are_posted: true, protected_entities: ['expenses', 'salary_withdrawals'] };
}

/** Called before generic sync creates. Client-supplied reversal fields are never trusted. */
export async function validateFinancialCreate(db: D1Database, entity: string, data: Record<string, unknown>): Promise<void> {
  if (!isPostedFinancialEntity(entity)) return;
  if (data.reversal_of_uuid != null || data.reversal_actor != null || data.reversal_reason != null || !Number.isFinite(Number(data.amount)) || Number(data.amount) <= 0 || data.deleted_at) {
    throw new FinancialPolicyError('استخدم أمر reverse؛ لا يمكن رفع قيد عكسي أو حذف كإنشاء عادي');
  }
  const policy = await financialPolicy(db);
  const day = String(data.hotel_day_key || data[entity === 'expenses' ? 'date' : 'withdraw_date'] || '').slice(0, 10);
  if (!validDay(day)) throw new FinancialPolicyError('اليوم الفندقي مطلوب بصيغة YYYY-MM-DD');
  if (day <= policy.closed_through) throw new FinancialPolicyError('الفترة مقفلة؛ لا يمكن ترحيل حركة إليها');
}

type Row = Record<string, unknown> & { local_uuid: string; amount: number };
type Receipt = { reversal_uuid: string; mirror_reversal_uuid: string | null };

/**
 * A command, not an uploaded negative amount. One D1 batch commits both legs,
 * audit, conflict write times and cursor allocations. UNIQUE(source) owns
 * business idempotency even when two devices use different request keys.
 */
export async function reverseFinancial(db: D1Database, entity: string, sourceUuid: string, reason: unknown, ctx: AuthContext, deviceId: string): Promise<string> {
  if (!isPostedFinancialEntity(entity)) throw new FinancialPolicyError('هذا النوع لا يدعم الإلغاء المالي');
  const explanation = reasonText(reason);
  await financialPolicy(db); // Fail closed on incomplete rollout.
  const source = await db.prepare(`SELECT * FROM ${entity} WHERE local_uuid = ?`).bind(sourceUuid).first<Row>();
  if (!source) throw new Error('الحركة الأصلية لم تصل بعد؛ أعد المزامنة');
  if (source.deleted_at != null || source.reversal_of_uuid || !Number.isFinite(Number(source.amount)) || Number(source.amount) <= 0) {
    throw new FinancialPolicyError('لا يمكن عكس حركة محذوفة أو قيد عكسي أو مبلغ غير موجب');
  }
  if (entity === 'expenses' && (source.cash_transaction_id || source.cash_flow_uuid)) {
    throw new FinancialPolicyError('المصروف مرتبط بسجل صندوق تاريخي؛ يلزم تصحيح مترابط ومراجعة يدوية');
  }
  // A linked salary row is a representation of the expense, never a second independent correction.
  if (entity === 'salary_withdrawals' && source.expense_uuid) {
    return reverseFinancial(db, 'expenses', String(source.expense_uuid), explanation, ctx, deviceId);
  }
  if (entity === 'salary_withdrawals' && /^exp_\d/.test(String(source.reason || ''))) {
    throw new FinancialPolicyError('سحب تاريخي بلا رابط UUID موثوق؛ يلزم مراجعته');
  }
  const receipt = () => db.prepare('SELECT reversal_uuid, mirror_reversal_uuid FROM financial_events WHERE entity = ? AND source_uuid = ?')
    .bind(entity, sourceUuid).first<Receipt>();
  const prior = await receipt();
  if (prior) return prior.reversal_uuid;

  let mirror: Row | null = null;
  if (entity === 'expenses') {
    const mirrors = await db.prepare('SELECT * FROM salary_withdrawals WHERE expense_uuid = ? AND deleted_at IS NULL').bind(sourceUuid).all<Row>();
    if (mirrors.results.length > 1) throw new FinancialPolicyError('روابط سحب مكررة؛ يلزم مراجعتها');
    mirror = mirrors.results[0] ?? null;
    const employeeExpense = ['رواتب', 'سحب راتب', 'سحب من الراتب', 'سلفة', 'خصم راتب', 'خصم من الراتب', 'خصم', 'غياب', 'employee'].includes(String(source.expense_type).trim());
    if (!mirror && employeeExpense && (source.employee_uuid || source.related_id)) {
      throw new Error('رابط السحب لم يصل أو تاريخي غير مؤكد؛ لن ينشأ تصحيح جزئي');
    }
    if (mirror && (Number(mirror.amount) !== Number(source.amount) || !source.employee_uuid ||
      mirror.employee_uuid !== source.employee_uuid || mirror.reversal_of_uuid ||
      String(mirror.hotel_day_key || mirror.withdraw_date).slice(0, 10) !== String(source.hotel_day_key || source.date).slice(0, 10))) {
      throw new FinancialPolicyError('المصروف والسحب غير متطابقين؛ يلزم مراجعتهما');
    }
  }
  const day = financialHotelDay();
  const now = Math.floor(Date.now() / 1000);
  const uuid = crypto.randomUUID();
  const mirrorUuid = mirror ? crypto.randomUUID() : null;
  // One cursor group per business operation. Pull's boundary-extension keeps both
  // legs together even when limit=1, and allocation occurs INSIDE the transaction.
  const statements: D1PreparedStatement[] = [db.prepare('UPDATE sync_clock SET last_ts = MAX(last_ts + 1, ?) WHERE id = 1').bind(now)];
  const append = (table: string, original: Row, reversalUuid: string, expenseUuid?: string) => {
    const row: Record<string, unknown> = { ...original,
      local_uuid: reversalUuid, server_id: null, amount: -Number(original.amount),
      hotel_day_key: day, created_at: now, last_modified: now,
      deleted_at: null, deleted_at_iso: null, created_at_iso: null, updated_at_iso: null,
      created_at_epoch: now, last_modified_epoch: now, version: 1,
      origin: 'financial-reversal', device_id: 'financial-ledger', vector_clock: '{}', idempotency_key: null,
      reversal_of_uuid: original.local_uuid, reversal_reason: explanation, reversal_actor: ctx.userId,
    };
    delete row.id;
    delete row.updated_at;
    if (table === 'expenses') { row.date = day; row.cash_transaction_id = null; row.cash_flow_uuid = null; }
    else { row.withdraw_date = day; if (expenseUuid) row.expense_uuid = expenseUuid; }
    const columns = Object.keys(row);
    statements.push(db.prepare(`INSERT INTO ${table} (${columns.join(',')}, updated_at) VALUES (${columns.map(() => '?').join(',')}, (SELECT last_ts FROM sync_clock WHERE id = 1))`).bind(...columns.map(c => row[c])));
    statements.push(db.prepare('INSERT INTO sync_write_times(entity, local_uuid, edited_at) VALUES (?, ?, ?)').bind(table, reversalUuid, now));
  };
  append(entity, source, uuid);
  if (mirror && mirrorUuid) append('salary_withdrawals', mirror, mirrorUuid, uuid);
  statements.push(db.prepare('INSERT INTO financial_events(id, entity, source_uuid, reversal_uuid, mirror_reversal_uuid, reason, actor, device_id, hotel_day_key, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
    .bind(crypto.randomUUID(), entity, sourceUuid, uuid, mirrorUuid, explanation, ctx.userId, deviceId, day, now));
  try { await db.batch(statements); }
  catch (error) {
    // A concurrent winner committed the entire operation; our failed batch rolled back.
    const winner = await receipt();
    if (winner) return winner.reversal_uuid;
    if (String(error).includes('FINANCIAL_PERIOD_CLOSED')) throw new FinancialPolicyError('الفترة الحالية مقفلة؛ لا يمكن تسجيل التصحيح');
    throw error;
  }
  return uuid;
}

/** Irreversible high-water mark; only completed hotel days may be closed. */
export async function closeFinancialPeriod(db: D1Database, through: unknown, reason: unknown, ctx: AuthContext): Promise<void> {
  if (ctx.role !== 'admin') throw new FinancialPolicyError('صلاحية المسؤول مطلوبة');
  const day = typeof through === 'string' ? through : '';
  if (!validDay(day) || day >= financialHotelDay()) throw new FinancialPolicyError('يمكن إقفال يوم فندقي مكتمل فقط');
  const explanation = reasonText(reason);
  const current = await financialPolicy(db);
  if (day < current.closed_through) throw new FinancialPolicyError('لا يمكن إعادة فتح فترة مقفلة');
  if (day === current.closed_through) return;
  await db.batch([
    db.prepare('UPDATE financial_period_lock SET closed_through = MAX(closed_through, ?) WHERE id = 1').bind(day),
    db.prepare("INSERT OR IGNORE INTO financial_events(id, entity, source_uuid, reason, actor, device_id, hotel_day_key, created_at) VALUES (?, 'period_close', ?, ?, ?, ?, ?, ?)")
      .bind(crypto.randomUUID(), day, explanation, ctx.userId, ctx.deviceId, day, Math.floor(Date.now() / 1000)),
  ]);
}

/** Complete canonical operation, including both originals, for atomic client acknowledgement. */
export async function financialReceipt(db: D1Database, reversalUuid: string): Promise<Record<string, unknown>[]> {
  const event = await db.prepare('SELECT * FROM financial_events WHERE reversal_uuid = ?').bind(reversalUuid)
    .first<{entity: string; source_uuid: string; reversal_uuid: string; mirror_reversal_uuid: string | null}>();
  if (!event || !isPostedFinancialEntity(event.entity)) throw new Error('Missing reversal receipt');
  const records: Record<string, unknown>[] = [];
  for (const uuid of [event.source_uuid, event.reversal_uuid]) {
    const row = await db.prepare(`SELECT * FROM ${event.entity} WHERE local_uuid = ?`).bind(uuid).first();
    if (!row) throw new Error('Incomplete reversal receipt');
    records.push({...row, _entity: event.entity});
  }
  if (event.mirror_reversal_uuid) {
    const mirror = await db.prepare('SELECT * FROM salary_withdrawals WHERE local_uuid = ?').bind(event.mirror_reversal_uuid).first();
    if (!mirror) throw new Error('Incomplete mirror receipt');
    const original = await db.prepare('SELECT * FROM salary_withdrawals WHERE local_uuid = ?').bind(mirror.reversal_of_uuid).first();
    if (!original) throw new Error('Missing original mirror');
    records.push({...original, _entity: 'salary_withdrawals'}, {...mirror, _entity: 'salary_withdrawals'});
  }
  return records;
}
