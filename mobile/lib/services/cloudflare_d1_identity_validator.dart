import 'package:marina_hotel_mobile/services/local_db.dart';

/// Local-only preflight for the first Cloudflare D1 upload.
///
/// This class never repairs or guesses an identity. Any returned issue must be
/// resolved locally before the caller starts an HTTP request to Cloudflare.
class CloudflareD1IdentityValidator {
  const CloudflareD1IdentityValidator._();

  static const Set<String> _identityTables = {
    'rooms',
    'bookings',
    'booking_nights',
    'booking_notes',
    'booking_price_adjustments',
    'payments',
    'payment_voids',
    'price_adjustments',
    'expenses',
    'debts',
    'employees',
    'guest_infos',
    'cash_transactions',
    'shift_notes',
    'salary_cycles',
    'salary_payments',
    'salary_withdrawals',
    'salary_carry_over_logs',
    'audit_logs',
    'inventory_items',
    'inventory_transactions',
  };

  static Future<List<String>> inspect({
    required AppDatabase db,
    required Set<String> selectedTables,
  }) async {
    final issues = <String>[];

    for (final table
        in selectedTables.intersection(_identityTables).toList()..sort()) {
      final missing = await _count(
        db,
        'SELECT COUNT(*) AS n FROM "$table" '
        "WHERE local_uuid IS NULL OR TRIM(local_uuid) = ''",
      );
      if (missing > 0) {
        issues.add('$table: يوجد $missing صف بلا local_uuid صالح.');
      }

      final duplicates = await _count(
        db,
        'SELECT COUNT(*) AS n FROM ('
        'SELECT local_uuid FROM "$table" '
        "WHERE local_uuid IS NOT NULL AND TRIM(local_uuid) != '' "
        'GROUP BY LOWER(TRIM(local_uuid)) HAVING COUNT(*) > 1)',
      );
      if (duplicates > 0) {
        issues.add('$table: يوجد $duplicates UUID مكرر؛ الرفع متوقف.');
      }
    }

    if (selectedTables.contains('expenses')) {
      final salaryTypes = [
        'رواتب',
        'سحب راتب',
        'سحب من الراتب',
        'خصم راتب',
        'خصم من الراتب',
        'سلفة',
      ];
      final predicate = salaryTypes
          .map((word) => "INSTR(e.expense_type, '$word') > 0")
          .join(' OR ');
      final invalidSalaryExpenses = await _count(
        db,
        'SELECT COUNT(*) AS n FROM expenses e '
        'WHERE e.deleted_at IS NULL AND ($predicate) AND ('
        "e.employee_uuid IS NULL OR TRIM(e.employee_uuid) = '' OR "
        'NOT EXISTS (SELECT 1 FROM employees owner '
        'WHERE LOWER(TRIM(owner.local_uuid)) = LOWER(TRIM(e.employee_uuid))) OR '
        'NOT EXISTS (SELECT 1 FROM employees owner '
        'WHERE owner.id = e.related_id '
        'AND LOWER(TRIM(owner.local_uuid)) = LOWER(TRIM(e.employee_uuid))))',
      );
      if (invalidSalaryExpenses > 0) {
        issues.add(
          'expenses: يوجد $invalidSalaryExpenses مصروف راتب/سلفة لا يتطابق فيه '
          'employee_uuid مع الموظف المحلي وrelated_id؛ لن يُرفع بتخمين.',
        );
      }
    }

    for (final table in const [
      'salary_cycles',
      'salary_withdrawals',
      'salary_carry_over_logs',
    ]) {
      if (!selectedTables.contains(table)) continue;
      final invalidOwners = await _count(
        db,
        'SELECT COUNT(*) AS n FROM "$table" r '
        'WHERE r.deleted_at IS NULL AND ('
        "r.employee_uuid IS NULL OR TRIM(r.employee_uuid) = '' OR "
        'NOT EXISTS (SELECT 1 FROM employees owner '
        'WHERE owner.id = r.employee_id '
        'AND LOWER(TRIM(owner.local_uuid)) = LOWER(TRIM(r.employee_uuid))))',
      );
      if (invalidOwners > 0) {
        issues.add(
          '$table: يوجد $invalidOwners صف لا يربط employee_uuid والـ employee_id '
          'بالموظف نفسه؛ لن يُرفع.',
        );
      }
    }

    if (selectedTables.contains('salary_payments')) {
      final invalidOwners = await _count(
        db,
        'SELECT COUNT(*) AS n FROM salary_payments p '
        'WHERE p.deleted_at IS NULL AND ('
        "p.employee_uuid IS NULL OR TRIM(p.employee_uuid) = '' OR "
        'NOT EXISTS (SELECT 1 FROM employees owner '
        'WHERE LOWER(TRIM(owner.local_uuid)) = LOWER(TRIM(p.employee_uuid))) OR '
        'NOT EXISTS (SELECT 1 FROM salary_cycles c '
        'WHERE c.id = p.cycle_id '
        'AND LOWER(TRIM(c.employee_uuid)) = LOWER(TRIM(p.employee_uuid))))',
      );
      if (invalidOwners > 0) {
        issues.add(
          'salary_payments: يوجد $invalidOwners دفعة لا يطابق فيها employee_uuid '
          'موظفها ودورة الراتب؛ لن تُرفع.',
        );
      }
    }

    if (selectedTables.contains('salary_withdrawals')) {
      final brokenExpenseLinks = await _count(
        db,
        'SELECT COUNT(*) AS n FROM salary_withdrawals sw '
        'WHERE sw.deleted_at IS NULL AND sw.expense_uuid IS NOT NULL AND ('
        "TRIM(sw.expense_uuid) = '' OR NOT EXISTS ("
        'SELECT 1 FROM expenses e '
        'WHERE LOWER(TRIM(e.local_uuid)) = LOWER(TRIM(sw.expense_uuid)) '
        'AND LOWER(TRIM(COALESCE(e.withdrawal_uuid, \'\'))) = '
        'LOWER(TRIM(sw.local_uuid)) '
        'AND LOWER(TRIM(COALESCE(e.employee_uuid, \'\'))) = '
        'LOWER(TRIM(COALESCE(sw.employee_uuid, \'\')))))',
      );
      if (brokenExpenseLinks > 0) {
        issues.add(
          'salary_withdrawals: يوجد $brokenExpenseLinks رابط expense_uuid لا '
          'يقابله مصروف local_uuid ورابط withdrawal_uuid وموظف متطابق؛ لن تُرفع.',
        );
      }
      final duplicateExpenseLinks = await _count(
        db,
        'SELECT COUNT(*) AS n FROM ('
        'SELECT expense_uuid FROM salary_withdrawals '
        "WHERE expense_uuid IS NOT NULL AND TRIM(expense_uuid) != '' "
        'AND deleted_at IS NULL GROUP BY LOWER(TRIM(expense_uuid)) '
        'HAVING COUNT(*) > 1)',
      );
      if (duplicateExpenseLinks > 0) {
        issues.add(
          'salary_withdrawals: توجد $duplicateExpenseLinks روابط expense_uuid '
          'مكررة نشطة؛ يلزم إصلاحها قبل الرفع.',
        );
      }
    }

    if (selectedTables.contains('expenses')) {
      final brokenWithdrawalLinks = await _count(
        db,
        'SELECT COUNT(*) AS n FROM expenses e '
        'WHERE e.deleted_at IS NULL AND e.withdrawal_uuid IS NOT NULL AND ('
        "TRIM(e.withdrawal_uuid) = '' OR NOT EXISTS ("
        'SELECT 1 FROM salary_withdrawals sw '
        'WHERE LOWER(TRIM(sw.local_uuid)) = LOWER(TRIM(e.withdrawal_uuid)) '
        'AND LOWER(TRIM(COALESCE(sw.expense_uuid, \'\'))) = '
        'LOWER(TRIM(e.local_uuid)) '
        'AND LOWER(TRIM(COALESCE(sw.employee_uuid, \'\'))) = '
        'LOWER(TRIM(COALESCE(e.employee_uuid, \'\')))))',
      );
      if (brokenWithdrawalLinks > 0) {
        issues.add(
          'expenses: يوجد $brokenWithdrawalLinks رابط withdrawal_uuid لا '
          'يقابله سحب local_uuid وexpense_uuid وموظف متطابق؛ لن تُرفع.',
        );
      }
      final duplicateWithdrawalLinks = await _count(
        db,
        'SELECT COUNT(*) AS n FROM ('
        'SELECT withdrawal_uuid FROM expenses '
        "WHERE withdrawal_uuid IS NOT NULL AND TRIM(withdrawal_uuid) != '' "
        'AND deleted_at IS NULL GROUP BY LOWER(TRIM(withdrawal_uuid)) '
        'HAVING COUNT(*) > 1)',
      );
      if (duplicateWithdrawalLinks > 0) {
        issues.add(
          'expenses: توجد $duplicateWithdrawalLinks روابط withdrawal_uuid '
          'مكررة نشطة؛ يلزم إصلاحها قبل الرفع.',
        );
      }
    }

    return issues;
  }

  static Future<int> _count(AppDatabase db, String sql) async {
    final rows = await db.customSelect(sql).get();
    if (rows.isEmpty) return 0;
    return (rows.first.data['n'] as num?)?.toInt() ?? 0;
  }
}
