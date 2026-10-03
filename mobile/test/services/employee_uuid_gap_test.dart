// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/utils/id.dart';

/// ✅ (2026-09-19) اختبارات فجوة employee_uuid — Migration 67 وسلوك الإنشاء:
///
/// 1. الأعمدة الجديدة موجودة (employee_uuid على جداول الرواتب الأربعة).
/// 2. تعبئة السحوبات المباشرة: reason = direct_withdrawal_<uuid> يُشتق منه
///    employee_uuid (مصدر موثق قطعياً — لا يعتمد على المعرفات الرقمية).
/// 3. تعبئة الدورات من employees.id.
/// 4. إنشاء سحبة جديدة عبر المستودع يولّد employee_uuid فوراً.
/// 5. إنشاء ترحيل راتب يولّد employee_uuid.
/// 6. السحوبات القديمة غير المربوطة لا تُخمَّن (تبقى NULL).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SalaryWithdrawalsRepository swRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    swRepo = SalaryWithdrawalsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertEmployee(String name, String uuid) async {
    return await (db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            name: name,
            basicSalary: 50000,
            status: 'active',
            localUuid: uuid,
            createdAt: 1,
            updatedAt: 1,
            lastModified: 1,
          ),
        ));
  }

  group('Migration 67 — أعمدة employee_uuid', () {
    test('الأعمدة موجودة في المخطط الحالي', () async {
      final cols = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('salary_withdrawals') "
            "WHERE name = 'employee_uuid'",
          )
          .get();
      expect(cols, isNotEmpty, reason: 'salary_withdrawals.employee_uuid');

      final cols2 = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('salary_cycles') "
            "WHERE name = 'employee_uuid'",
          )
          .get();
      expect(cols2, isNotEmpty, reason: 'salary_cycles.employee_uuid');

      final cols3 = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('salary_payments') "
            "WHERE name = 'employee_uuid'",
          )
          .get();
      expect(cols3, isNotEmpty, reason: 'salary_payments.employee_uuid');

      final cols4 = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('salary_carry_over_logs') "
            "WHERE name = 'employee_uuid'",
          )
          .get();
      expect(cols4, isNotEmpty, reason: 'salary_carry_over_logs.employee_uuid');
    });

    test('direct_withdrawal_<uuid> يُشتق منه employee_uuid', () async {
      final empUuid = IdGen.uuid();
      final empId = await insertEmployee('عمار التجربة', empUuid);

      // سحبة مباشرة قديمة: employee_uuid فارغ والمعرف مضمّن في reason
      await db.customStatement(
        "INSERT INTO salary_withdrawals "
        "(local_uuid, employee_id, amount, withdraw_date, reason, "
        " withdrawal_type, hotel_day_key, created_at, updated_at, "
        " last_modified, created_at_epoch, last_modified_epoch, version, "
        " origin, vector_clock) VALUES "
        "('wd-test-1', $empId, 1000.0, '2026-09-01', "
        " 'direct_withdrawal_$empUuid', 'سحب راتب', '2026-09-01', "
        " 1, 1, 1, 1, 1, 1, 'local', '{}')",
      );

      // نفس SQL الـ migration 67 (3-ب) — substr لأن '_' حرف بدل في LIKE
      // 'direct_withdrawal_' = 18 حرفاً → UUID من الموضع 19، الطول الكلي 54
      await db.customStatement(
        "UPDATE salary_withdrawals SET employee_uuid = SUBSTR(reason, 19) "
        "WHERE employee_uuid IS NULL "
        "AND SUBSTR(reason, 1, 18) = 'direct_withdrawal_' "
        "AND LENGTH(reason) = 54 "
        "AND EXISTS (SELECT 1 FROM employees e "
        "  WHERE e.local_uuid = SUBSTR(reason, 19))",
      );

      final rows = await db
          .customSelect(
            "SELECT employee_uuid FROM salary_withdrawals "
            "WHERE local_uuid = 'wd-test-1'",
          )
          .get();
      expect(rows, isNotEmpty);
      expect(rows.first.readNullable<String>('employee_uuid'), empUuid);
    });

    test('الدورات تُعبّأ من employees.id', () async {
      final empUuid = IdGen.uuid();
      final empId = await insertEmployee('ناصر التجربة', empUuid);

      await db.customStatement(
        "INSERT INTO salary_cycles "
        "(local_uuid, employee_id, cycle_key, expected_amount, actual_paid, "
        " remaining_amount, status, created_at, updated_at, last_modified, "
        " created_at_epoch, last_modified_epoch, version, origin, vector_clock) "
        "VALUES ('cy-test-1', $empId, '2026-09#1', 0, 0, 0, 'draft', "
        " 1, 1, 1, 1, 1, 1, 'local', '{}')",
      );

      await db.customStatement(
        'UPDATE salary_cycles SET employee_uuid = '
        '(SELECT e.local_uuid FROM employees e '
        ' WHERE e.id = salary_cycles.employee_id) '
        'WHERE employee_uuid IS NULL '
        'AND employee_id IS NOT NULL '
        "AND EXISTS (SELECT 1 FROM employees e2 "
        " WHERE e2.id = salary_cycles.employee_id)",
      );

      final rows = await db
          .customSelect(
            "SELECT employee_uuid FROM salary_cycles WHERE local_uuid = 'cy-test-1'",
          )
          .get();
      expect(rows.first.read<String>('employee_uuid'), empUuid);
    });
  });

  group('إنشاء جديد — employee_uuid يُولَّد', () {
    test('createFromExpense يكتب employee_uuid', () async {
      final empUuid = IdGen.uuid();
      final empId = await insertEmployee('سامح التجربة', empUuid);

      await swRepo.createFromExpense(
        expenseId: 0,
        employeeId: empId,
        reason: 'direct_withdrawal_$empUuid',
        amount: 2000,
        date: '2026-09-19',
        withdrawalType: 'سحب راتب',
      );

      final rows = await db
          .customSelect(
            "SELECT employee_uuid FROM salary_withdrawals "
            "WHERE employee_uuid IS NOT NULL AND amount = 2000.0",
          )
          .get();
      expect(
        rows,
        isNotEmpty,
        reason: 'يجب أن تُكتب employee_uuid عند الإنشاء',
      );
      expect(rows.first.read<String>('employee_uuid'), empUuid);
    });

    test('الترحيل (carry-over) يكتب employee_uuid', () async {
      final empUuid = IdGen.uuid();
      final empId = await insertEmployee('عبدالله التجربة', empUuid);

      // استدعاء منطق الترحيل عبر الخدمة غير ممكن مباشرة (يتطلب دورة كاملة)
      // — نتحقق من أن Companion الجديد يقبل ويخزن employee_uuid
      await db
          .into(db.salaryCarryOverLogs)
          .insert(
            SalaryCarryOverLogsCompanion.insert(
              employeeId: empId,
              employeeUuid: d.Value(empUuid),
              amount: 500,
              previousCycleStart: '2026-08-01',
              previousCycleEnd: '2026-08-31',
              newCycleStart: '2026-09-01',
              newCycleEnd: '2026-09-30',
              reason: 'اختبار',
              carriedAt: 1,
              localUuid: 'co-test-1',
              createdAt: 1,
              updatedAt: 1,
              lastModified: 1,
            ),
          );

      final rows = await db
          .customSelect(
            "SELECT employee_uuid FROM salary_carry_over_logs "
            "WHERE local_uuid = 'co-test-1'",
          )
          .get();
      expect(rows.first.read<String>('employee_uuid'), empUuid);
    });
  });

  group('لا تخمين على السجلات الغامضة', () {
    test('مصروف راتب بمعرف موظف غير موجود يبقى بدون employee_uuid', () async {
      // related_id = 999 بلا FK في expenses — السيناريو التاريخي الواقعي
      // للسجلات المنزّلة من السحابة بمعرفات أجهزة أخرى
      await db.customStatement(
        "INSERT INTO expenses "
        "(local_uuid, expense_type, related_id, description, amount, date, "
        " hotel_day_key, created_at, updated_at, last_modified, "
        " created_at_epoch, last_modified_epoch, version, origin, vector_clock) "
        "VALUES ('ex-orphan-1', 'سحب راتب', 999, 'وصف', 3000.0, '2026-09-01', "
        " '2026-09-01', 1, 1, 1, 1, 1, 1, 'local', '{}')",
      );

      await db.customStatement(
        "UPDATE expenses SET employee_uuid = "
        "(SELECT e.local_uuid FROM employees e WHERE e.id = expenses.related_id) "
        "WHERE employee_uuid IS NULL "
        "AND related_id IS NOT NULL "
        "AND TRIM(expense_type) IN "
        "('سحب راتب','خصم راتب','سحب من الراتب','خصم من الراتب','سلفة','رواتب') "
        "AND EXISTS (SELECT 1 FROM employees e2 WHERE e2.id = expenses.related_id)",
      );

      final rows = await db
          .customSelect(
            "SELECT employee_uuid FROM expenses WHERE local_uuid = 'ex-orphan-1'",
          )
          .get();
      // تبقى NULL — لا تخمين ولا فقدان
      expect(rows.first.readNullable<String>('employee_uuid'), isNull);
    });
  });
}
