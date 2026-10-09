import 'cloudflare_config.dart';
import 'local_db.dart';

/// Read-only preflight for a first Cloudflare D1 upload.
///
/// Local integer ids are device-local implementation details. This validator
/// only accepts `local_uuid` as the portable identity and checks that the
/// UUID-based financial links agree with the local foreign keys before any
/// upload request is sent.
class CloudflareD1IdentityValidator {
  CloudflareD1IdentityValidator._();

  static const _salaryExpenseKinds =
      "'salary_advance', 'salary_installment', 'salary_withdrawal', 'salary_deduction'";
  static const _legacySalaryExpenseTypes =
      "'رواتب', 'سحب راتب', 'سحب من الراتب', 'سلفة', 'خصم من الراتب', 'خصم راتب', 'خصم', 'غياب'";

  static Future<List<String>> inspect({
    required AppDatabase db,
    required Set<String> selectedTables,
  }) async {
    final issues = <String>{};
    final knownTables = <String>{
      ...CloudflareConfig.entityToTable.values,
      'blacklist',
    };
    final selected = selectedTables.intersection(knownTables);

    // `blacklist` is a projection of local shift_notes; inspect its source.
    for (final table in selected) {
      final sourceTable = table == 'blacklist' ? 'shift_notes' : table;
      final where = table == 'shift_notes'
          ? "COALESCE(created_by, '') <> 'blacklist'"
          : table == 'blacklist'
          ? "COALESCE(created_by, '') = 'blacklist'"
          : null;
      final whereSql = where == null ? '' : ' WHERE $where';
      final joiner = where == null ? ' WHERE' : ' AND';

      final missing = await _count(
        db,
        '''
          SELECT COUNT(*) AS n FROM $sourceTable$whereSql$joiner
            (local_uuid IS NULL OR TRIM(local_uuid) = ''
              OR TRIM(local_uuid) <> local_uuid)
        ''',
      );
      if (missing > 0) {
        issues.add(
          '$table: $missing صفاً بلا local_uuid صالح؛ أوقف الرفع حتى إصلاح الهوية.',
        );
      }

      final duplicates = await _count(
        db,
        '''
          SELECT COUNT(*) AS n FROM (
            SELECT LOWER(TRIM(local_uuid)) AS uuid_key
            FROM $sourceTable$whereSql$joiner local_uuid IS NOT NULL
              AND TRIM(local_uuid) <> ''
            GROUP BY LOWER(TRIM(local_uuid))
            HAVING COUNT(*) > 1
          )
        ''',
      );
      if (duplicates > 0) {
        issues.add(
          '$table: توجد $duplicates هويات local_uuid مكررة بعد التطبيع؛ لا يمكن ضمان upsert آمن.',
        );
      }
    }

    // UUID is authoritative; a local numeric FK, when present, must resolve
    // to the employee row carrying that same UUID.
    for (final table in [
      'salary_withdrawals',
      'salary_cycles',
      'salary_carry_over_logs',
    ]) {
      if (!selected.contains(table)) continue;
      final invalid = await _count(
        db,
        '''
          SELECT COUNT(*) AS n FROM $table r WHERE
            r.employee_uuid IS NULL OR TRIM(r.employee_uuid) = ''
            OR NOT EXISTS (
              SELECT 1 FROM employees e
              WHERE LOWER(TRIM(e.local_uuid)) = LOWER(TRIM(r.employee_uuid))
            )
            OR (r.employee_id IS NOT NULL AND NOT EXISTS (
              SELECT 1 FROM employees e
              WHERE e.id = r.employee_id
                AND LOWER(TRIM(e.local_uuid)) = LOWER(TRIM(r.employee_uuid))
            ))
        ''',
      );
      if (invalid > 0) {
        issues.add(
          '$table: $invalid صفاً له employee_uuid مفقود أو لا يطابق الموظف المحلي.',
        );
      }
      if (!selected.contains('employees') &&
          await _count(db, 'SELECT COUNT(*) AS n FROM $table') > 0) {
        issues.add(
          '$table: اختر employees مع هذا الجدول قبل أول رفع للعلاقات.',
        );
      }
    }

    if (selected.contains('expenses')) {
      final invalidEmployee = await _count(
        db,
        '''
          SELECT COUNT(*) AS n FROM expenses x WHERE
            (x.employee_uuid IS NOT NULL AND
              (TRIM(x.employee_uuid) = '' OR NOT EXISTS (
                SELECT 1 FROM employees e
                WHERE LOWER(TRIM(e.local_uuid)) = LOWER(TRIM(x.employee_uuid))
              )))
            OR ((COALESCE(x.expense_kind, '') IN ($_salaryExpenseKinds)
              OR (COALESCE(x.expense_kind, '') = ''
                AND x.expense_type IN ($_legacySalaryExpenseTypes)))
              AND (x.employee_uuid IS NULL OR TRIM(x.employee_uuid) = ''))
            OR (x.employee_uuid IS NOT NULL AND x.related_id IS NOT NULL
              AND NOT EXISTS (
                SELECT 1 FROM employees e
                WHERE e.id = x.related_id
                  AND LOWER(TRIM(e.local_uuid)) = LOWER(TRIM(x.employee_uuid))
              ))
        ''',
      );
      if (invalidEmployee > 0) {
        issues.add(
          'expenses: $invalidEmployee صفاً لديه employee_uuid مفقود أو غير مطابق، بما فيها المصروفات الراتبية.',
        );
      }

      final linkedExpenses = await _count(
        db,
        "SELECT COUNT(*) AS n FROM expenses WHERE withdrawal_uuid IS NOT NULL AND TRIM(withdrawal_uuid) <> ''",
      );
      if (linkedExpenses > 0 && !selected.contains('salary_withdrawals')) {
        issues.add(
          'expenses: توجد $linkedExpenses علاقة withdrawal_uuid؛ اختر salary_withdrawals قبل الرفع.',
        );
      }
      final invalidExpenseLinks = await _count(
        db,
        '''
          SELECT COUNT(*) AS n FROM expenses x
          WHERE x.withdrawal_uuid IS NOT NULL AND TRIM(x.withdrawal_uuid) <> ''
            AND NOT EXISTS (
              SELECT 1 FROM salary_withdrawals w
              WHERE LOWER(TRIM(w.local_uuid)) = LOWER(TRIM(x.withdrawal_uuid))
                AND LOWER(TRIM(w.expense_uuid)) = LOWER(TRIM(x.local_uuid))
                AND COALESCE(LOWER(TRIM(w.employee_uuid)), '') =
                    COALESCE(LOWER(TRIM(x.employee_uuid)), '')
            )
        ''',
      );
      if (invalidExpenseLinks > 0) {
        issues.add(
          'expenses.withdrawal_uuid: $invalidExpenseLinks رابطاً لا يقابله salary_withdrawals.expense_uuid وemployee_uuid متطابقان.',
        );
      }
      final expensesWithEmployee = await _count(
        db,
        "SELECT COUNT(*) AS n FROM expenses WHERE employee_uuid IS NOT NULL AND TRIM(employee_uuid) <> ''",
      );
      if (expensesWithEmployee > 0 && !selected.contains('employees')) {
        issues.add('expenses: اختر employees مع المصروفات المرتبطة بموظف.');
      }
    }

    if (selected.contains('salary_withdrawals')) {
      final linkedWithdrawals = await _count(
        db,
        "SELECT COUNT(*) AS n FROM salary_withdrawals WHERE expense_uuid IS NOT NULL AND TRIM(expense_uuid) <> ''",
      );
      if (linkedWithdrawals > 0 && !selected.contains('expenses')) {
        issues.add(
          'salary_withdrawals: توجد $linkedWithdrawals علاقة expense_uuid؛ اختر expenses قبل الرفع.',
        );
      }
      final invalidWithdrawalLinks = await _count(
        db,
        '''
          SELECT COUNT(*) AS n FROM salary_withdrawals w
          WHERE w.expense_uuid IS NOT NULL AND TRIM(w.expense_uuid) <> ''
            AND NOT EXISTS (
              SELECT 1 FROM expenses x
              WHERE LOWER(TRIM(x.local_uuid)) = LOWER(TRIM(w.expense_uuid))
                AND LOWER(TRIM(x.withdrawal_uuid)) = LOWER(TRIM(w.local_uuid))
                AND COALESCE(LOWER(TRIM(x.employee_uuid)), '') =
                    COALESCE(LOWER(TRIM(w.employee_uuid)), '')
            )
        ''',
      );
      if (invalidWithdrawalLinks > 0) {
        issues.add(
          'salary_withdrawals.expense_uuid: $invalidWithdrawalLinks رابطاً لا يقابله expenses.withdrawal_uuid وemployee_uuid متطابقان.',
        );
      }
      final duplicateActiveExpenseLinks = await _count(
        db,
        '''
          SELECT COUNT(*) AS n FROM (
            SELECT LOWER(TRIM(expense_uuid)) AS uuid_key
            FROM salary_withdrawals
            WHERE deleted_at IS NULL AND expense_uuid IS NOT NULL
              AND TRIM(expense_uuid) <> ''
            GROUP BY LOWER(TRIM(expense_uuid))
            HAVING COUNT(*) > 1
          )
        ''',
      );
      if (duplicateActiveExpenseLinks > 0) {
        issues.add(
          'salary_withdrawals: توجد $duplicateActiveExpenseLinks روابط expense_uuid نشطة مكررة.',
        );
      }
    }

    if (selected.contains('salary_payments')) {
      final invalidCycles = await _count(
        db,
        '''
          SELECT COUNT(*) AS n FROM salary_payments p
          WHERE p.cycle_uuid IS NULL OR TRIM(p.cycle_uuid) = ''
            OR NOT EXISTS (
              SELECT 1 FROM salary_cycles c
              WHERE LOWER(TRIM(c.local_uuid)) = LOWER(TRIM(p.cycle_uuid))
                AND c.id = p.cycle_id
                AND COALESCE(LOWER(TRIM(c.employee_uuid)), '') =
                    COALESCE(LOWER(TRIM(p.employee_uuid)), '')
            )
        ''',
      );
      if (invalidCycles > 0) {
        issues.add(
          'salary_payments: $invalidCycles صفاً لديه cycle_uuid لا يطابق الدورة والموظف المحليين.',
        );
      }
      if (!selected.contains('salary_cycles') &&
          await _count(db, 'SELECT COUNT(*) AS n FROM salary_payments') > 0) {
        issues.add('salary_payments: اختر salary_cycles قبل رفع الدفعات.');
      }
    }

    return issues.toList(growable: false);
  }

  static Future<int> _count(AppDatabase db, String sql) async {
    final row = await db.customSelect(sql).getSingle();
    return row.read<int>('n');
  }
}
