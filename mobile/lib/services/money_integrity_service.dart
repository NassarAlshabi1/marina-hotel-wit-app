// lib/services/money_integrity_service.dart
//
// ✅ (G-10 — تدقيق الهوية المالية 2026-10-06): كاشف الكسور العشرية التاريخية.
//
// سياسة الفندق: **لا كسور عشرية** في أي مبلغ مالي، والاقتطاع نحو الصفر
// (`CurrencyFormatter.truncateAmount`) — وهي نفس السياسة المعروضة والمُدخلة
// والمُنقولة عبر المزوّد بعد إغلاق G-10.
//
// هذا الكشف **قراءة فقط**:
//   - لا يُعدّل أي صف ولا يُقرّب أي مبلغ مخزَّن (البند 12: لا إصلاح تاريخي
//     بالتخمين ولا تغيير بيانات بلا قرار المالك).
//   - يُنتج تقريراً بأماكن الكسور (جدول + هوية UUID + المبلغ المخزَّن +
//     القيمة وفق السياسة) ليُعرض للمراجعة البشرية قبل أي ترحيل مقترح.
//
// ⚠️ ملاحظة مهمة: الصفوف ذات الكسور تُنقل عبر المزوّد بالقيمة المقتطعة
// (سياسة واحدة حتمية على كل الأجهزة)، فالفرق بين الجهاز المصدر والجهاز
// المستقبِل = مجموع الكسور المقتطعة، ويظهر هنا صراحةً بدل أن يضيع بصمت.
import 'local_db.dart';
import '../utils/app_logger.dart';
import '../utils/currency_formatter.dart';

/// صف واحد فيه كسر عشري.
class FractionalMoneyRow {
  const FractionalMoneyRow({
    required this.table,
    required this.localUuid,
    required this.storedAmount,
    required this.policyAmount,
    this.employeeUuid,
    this.date,
  });

  final String table;
  final String localUuid;
  final double storedAmount;

  /// القيمة وفق سياسة «لا كسور عشرية» (اقتطاع نحو الصفر).
  final int policyAmount;

  final String? employeeUuid;
  final String? date;

  double get removedFraction => storedAmount - policyAmount;

  @override
  String toString() =>
      '$table/$localUuid: $storedAmount → $policyAmount '
      '(فرق ${removedFraction.toStringAsFixed(4)})';
}

/// تقرير الكسور العشرية — للعرض والتصدير فقط.
class MoneyIntegrityReport {
  const MoneyIntegrityReport({required this.rows, required this.scannedTables});

  final List<FractionalMoneyRow> rows;
  final List<String> scannedTables;

  bool get isClean => rows.isEmpty;
  int get affectedRows => rows.length;

  /// مجموع الكسور المقتطعة لكل جدول (لتوثيق حجم الفرق المحتمل عند النقل).
  Map<String, double> get removedFractionByTable {
    final map = <String, double>{};
    for (final row in rows) {
      map[row.table] = (map[row.table] ?? 0) + row.removedFraction;
    }
    return map;
  }

  /// عدد الصفوف في كل جدول.
  Map<String, int> get countByTable {
    final map = <String, int>{};
    for (final row in rows) {
      map[row.table] = (map[row.table] ?? 0) + 1;
    }
    return map;
  }

  @override
  String toString() => isClean
      ? 'نظيف: كل المبالغ أعداد صحيحة (${scannedTables.length} جدول)'
      : '$affectedRows صف فيه كسور: ${countByTable.entries.map((e) => '${e.key}=${e.value}').join(', ')}';
}

class MoneyIntegrityService {
  MoneyIntegrityService(this.db);

  final AppDatabase db;

  /// فحص كل الجداول المالية بحثاً عن كسور عشرية مخزَّنة.
  /// قراءة فقط — لا كتابة ولا تعديل.
  Future<MoneyIntegrityReport> scan() async {
    final rows = <FractionalMoneyRow>[];
    final scanned = <String>[];

    Future<void> scanTable({
      required String table,
      required String sql,
      String? employeeUuidColumn,
      String? dateColumn,
    }) async {
      scanned.add(table);
      try {
        final result = await db.customSelect(sql).get();
        for (final row in result) {
          final amount = (row.data['amount'] as num?)?.toDouble();
          if (amount == null) continue;
          // مقارنة واعية بالكسور: القيمة الصحيحة 150.0 ليست كسراً.
          if (CurrencyFormatter.isWholeAmount(amount)) continue;
          rows.add(
            FractionalMoneyRow(
              table: table,
              localUuid: (row.data['local_uuid'] as String?) ?? '',
              storedAmount: amount,
              policyAmount: CurrencyFormatter.truncateAmount(amount),
              employeeUuid: employeeUuidColumn == null
                  ? null
                  : row.data[employeeUuidColumn] as String?,
              date: dateColumn == null ? null : row.data[dateColumn] as String?,
            ),
          );
        }
      } catch (e) {
        AppLogger.warning(
          '⚠️ تعذّر فحص الكسور في $table (قد يكون العمود/الجدول غير موجود '
          'في هذه النسخة): $e',
          tag: 'MONEY_INTEGRITY',
        );
      }
    }

    await scanTable(
      table: 'expenses',
      sql:
          'SELECT local_uuid, amount, employee_uuid AS employee_uuid, date '
          'FROM expenses WHERE deleted_at IS NULL',
      employeeUuidColumn: 'employee_uuid',
      dateColumn: 'date',
    );
    await scanTable(
      table: 'salary_withdrawals',
      sql:
          'SELECT local_uuid, amount, employee_uuid AS employee_uuid, '
          'withdraw_date AS withdraw_date FROM salary_withdrawals '
          'WHERE deleted_at IS NULL',
      employeeUuidColumn: 'employee_uuid',
      dateColumn: 'withdraw_date',
    );
    await scanTable(
      table: 'salary_payments',
      sql:
          'SELECT local_uuid, amount, employee_uuid AS employee_uuid, '
          'payment_date_iso AS payment_date_iso FROM salary_payments '
          'WHERE deleted_at IS NULL',
      employeeUuidColumn: 'employee_uuid',
      dateColumn: 'payment_date_iso',
    );
    await scanTable(
      table: 'cash_transactions',
      sql: 'SELECT local_uuid, amount FROM cash_transactions',
    );
    await scanTable(
      table: 'debts',
      sql: 'SELECT local_uuid, total_amount AS amount FROM debts',
    );
    await scanTable(
      table: 'price_adjustments',
      sql: 'SELECT local_uuid, amount FROM price_adjustments',
    );
    await scanTable(
      table: 'booking_price_adjustments',
      sql: 'SELECT local_uuid, amount FROM booking_price_adjustments',
    );
    await scanTable(
      table: 'salary_carry_over_logs',
      sql: 'SELECT local_uuid, amount FROM salary_carry_over_logs',
    );

    AppLogger.info(
      rows.isEmpty
          ? '✅ فحص الكسور: كل المبالغ أعداد صحيحة في ${scanned.length} جدول'
          : '⚠️ فحص الكسور: ${rows.length} صف فيه كسور عشرية — للمراجعة '
                'البشرية (بلا تعديل تلقائي)',
      tag: 'MONEY_INTEGRITY',
    );
    return MoneyIntegrityReport(rows: rows, scannedTables: scanned);
  }
}
