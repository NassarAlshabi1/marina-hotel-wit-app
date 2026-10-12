/** Closed wire contract, shared by push validation, legacy reads and AI writes.
 *
 * Mirrors branch3 worker/src/expense-kind.ts; introduced to branch2
 * as part of the B2↔B3 parity unification. The wire contract is identical
 * so that Flutter (Drift) and Android/Kotlin (Room) clients can use the
 * same expense_kind values without per-branch translation.
 */
export const EXPENSE_KINDS = new Set([
  'normal', 'salary_advance', 'salary_installment', 'salary_withdrawal',
  'salary_deduction', 'unclassified',
]);

/**
 * Conservative legacy classifier — used when a row arrives from a pre-contract
 * client (or when the explicit `expense_kind` is null). The result is stable
 * across description edits: once an explicit kind is present on the row, this
 * function is no longer consulted, so free-text edits never re-classify.
 *
 * Arabic `expense_type` strings match the existing Flutter payload mapper
 * (lib/services/sync/payload_mapper.dart) and the Android EmployeeExpenseTypes
 * set, so a legacy client on either platform produces the same kind on the
 * server. This is the cross-branch wire contract.
 */
export function legacyExpenseKind(row: Record<string, unknown>): string {
  const type = String(row.expense_type ?? '').trim();
  if (['رواتب', 'سحب راتب', 'سحب من الراتب'].includes(type)) return 'salary_withdrawal';
  if (type === 'سلفة') return 'salary_advance';
  if (type === 'خصم من الراتب') {
    const auto = row.is_auto_generated === true || Number(row.is_auto_generated) === 1;
    if (!auto) return 'salary_deduction';
    return String(row.description ?? '').includes('قسط سلفة') ? 'salary_installment' : 'unclassified';
  }
  if (['خصم راتب', 'خصم', 'غياب'].includes(type)) return 'salary_deduction';
  return 'normal';
}

/**
 * Resolve the canonical kind for an incoming row. If the client sent an
 * explicit kind we trust it (after validating against EXPENSE_KINDS);
 * otherwise we derive one conservatively from the legacy fields.
 *
 * Throws on an invalid explicit kind so the push pipeline rejects the
 * operation with `validation_error` rather than persisting an unknown
 * discriminator.
 */
export function expenseKind(value: unknown, legacy: Record<string, unknown>): string {
  if (value === null || value === undefined) return legacyExpenseKind(legacy);
  if (typeof value !== 'string' || !EXPENSE_KINDS.has(value)) throw new Error('Invalid expense_kind');
  return value;
}
