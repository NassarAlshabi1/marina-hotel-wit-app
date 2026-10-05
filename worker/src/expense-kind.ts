/** Closed wire contract, shared by push validation, legacy reads and AI writes. */
export const EXPENSE_KINDS = new Set([
  'normal', 'salary_advance', 'salary_installment', 'salary_withdrawal',
  'salary_deduction', 'unclassified',
]);
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
export function expenseKind(value: unknown, legacy: Record<string, unknown>): string {
  if (value === null || value === undefined) return legacyExpenseKind(legacy);
  if (typeof value !== 'string' || !EXPENSE_KINDS.has(value)) throw new Error('Invalid expense_kind');
  return value;
}
