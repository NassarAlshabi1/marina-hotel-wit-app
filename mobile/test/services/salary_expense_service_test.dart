// اختبارات PR-3 (وثيقة الربط §6.1): SalaryExpenseService
//  · حفظ المصروف + مرآته في معاملة واحدة
//  · تصنيف صريح في expense_kind (لا اشتقاق من النص عند الكتابة)
//  · لا مرآة ثانية نشطة عند التعديل
//  · حذف منطقي للمصروف ومرآته معاً
//  · إعادة الإسناد تُحدّث الطرفين وتعيد اشتقاق الأرقام من UUID
//  · موظف غير محلول ⇒ رفض صريح بلا كتابة جزئية

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/salary_expense_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SalaryExpenseService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = SalaryExpenseService(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertEmployee(String uuid, {String name = 'موظف'}) {
    return db
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
        );
  }

  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    final result = await db
        .customSelect(
          sql,
          variables: args.map(Variable.new).toList(),
        )
        .get();
    return result.map((r) => r.data).toList();
  }

  Future<int> activeMirrors(String expenseUuid) async {
    final result = await query(
      'SELECT COUNT(*) AS c FROM salary_withdrawals '
      'WHERE expense_uuid = ? AND deleted_at IS NULL',
      [expenseUuid],
    );
    return result.first['c'] as int;
  }

  group('ExpenseKind', () {
    test('أكواد ثابتة (تُخزَّن سحابياً) وتصنيف نصي انتقالي واحد', () {
      expect(ExpenseKind.salaryWithdrawal.code, 'salary_withdrawal');
      expect(ExpenseKind.advance.code, 'advance');
      expect(ExpenseKind.general.isSalaryFamily, isFalse);
      expect(ExpenseKind.payroll.isSalaryFamily, isTrue);

      expect(ExpenseKind.fromCode('advance'), ExpenseKind.advance);
      expect(ExpenseKind.fromCode('nope'), isNull);
      expect(ExpenseKind.fromCode(null), isNull);

      expect(
        ExpenseKind.classifyLegacyLabel('سحب من الراتب'),
        ExpenseKind.salaryWithdrawal,
      );
      expect(ExpenseKind.classifyLegacyLabel('سلفة'), ExpenseKind.advance);
      expect(ExpenseKind.classifyLegacyLabel('كهرباء'), ExpenseKind.general);
    });
  });

  group('saveSalaryExpense — إنشاء', () {
    test('ينشئ المصروف ومرآته معاً مع تصنيف صريح وoutbox للطرفين', () async {
      final empId = await insertEmployee('emp-uuid');

      final uuid = await service.saveSalaryExpense(
        kind: ExpenseKind.salaryWithdrawal,
        amount: 1500,
        date: '2026-11-01',
        employeeUuid: 'emp-uuid',
        description: 'سحب اختبار',
      );

      final expense = await query(
        'SELECT id, related_id, employee_uuid, expense_kind, amount '
        'FROM expenses WHERE local_uuid = ?',
        [uuid],
      );
      expect(expense, hasLength(1));
      expect(expense.first['related_id'], empId);
      expect(expense.first['employee_uuid'], 'emp-uuid');
      expect(expense.first['expense_kind'], 'salary_withdrawal');
      expect(expense.first['amount'], 1500.0);

      expect(await activeMirrors(uuid), 1);

      final mirror = await query(
        'SELECT employee_id, employee_uuid, amount FROM salary_withdrawals '
        'WHERE expense_uuid = ? AND deleted_at IS NULL',
        [uuid],
      );
      expect(mirror.single['employee_id'], empId);
      expect(mirror.single['employee_uuid'], 'emp-uuid');
      expect(mirror.single['amount'], 1500.0);

      final outbox = await query(
        'SELECT entity, COUNT(*) AS c FROM outbox GROUP BY entity',
      );
      final byEntity = {
        for (final row in outbox) '${row['entity']}': row['c'] as int,
      };
      expect(byEntity['expenses'], greaterThanOrEqualTo(1));
      expect(byEntity['salary_withdrawals'], greaterThanOrEqualTo(1));
    });

    test('مصروف عام (general) لا ينشئ مرآة', () async {
      await insertEmployee('emp-general');
      final uuid = await service.saveSalaryExpense(
        kind: ExpenseKind.general,
        amount: 250,
        date: '2026-11-01',
        employeeUuid: 'emp-general',
        description: 'كهرباء',
      );
      expect(await activeMirrors(uuid), 0);
      expect(await service.kindOf(uuid), ExpenseKind.general);
    });

    test('موظف غير محلول ⇒ رفض صريح بلا كتابة جزئية', () async {
      await expectLater(
        service.saveSalaryExpense(
          kind: ExpenseKind.salaryWithdrawal,
          amount: 700,
          date: '2026-11-01',
          employeeUuid: 'emp-does-not-exist',
        ),
        throwsA(isA<SalaryExpenseUnresolvedEmployee>()),
      );

      expect(await query('SELECT id FROM expenses'), isEmpty);
      expect(await query('SELECT id FROM salary_withdrawals'), isEmpty);
    });

    test('employeeUuid فارغ أو تاريخ فارغ ⇒ ArgumentError بلا كتابة', () async {
      await insertEmployee('emp-arg');
      await expectLater(
        service.saveSalaryExpense(
          kind: ExpenseKind.advance,
          amount: 10,
          date: '2026-11-01',
          employeeUuid: '  ',
        ),
        throwsArgumentError,
      );
      await expectLater(
        service.saveSalaryExpense(
          kind: ExpenseKind.advance,
          amount: 10,
          date: '  ',
          employeeUuid: 'emp-arg',
        ),
        throwsArgumentError,
      );
      expect(await query('SELECT id FROM expenses'), isEmpty);
    });
  });

  group('saveSalaryExpense — تعديل', () {
    test('التعديل يحدّث نفس المصروف والمرآة (لا مرآة ثانية)', () async {
      final empId = await insertEmployee('emp-edit');
      final uuid = await service.saveSalaryExpense(
        kind: ExpenseKind.salaryWithdrawal,
        amount: 1000,
        date: '2026-11-01',
        employeeUuid: 'emp-edit',
      );
      expect(await activeMirrors(uuid), 1);

      await service.saveSalaryExpense(
        kind: ExpenseKind.salaryWithdrawal,
        amount: 1800,
        date: '2026-11-01',
        employeeUuid: 'emp-edit',
        expenseUuid: uuid,
      );

      expect(await activeMirrors(uuid), 1, reason: 'مرآة واحدة لا اثنتان');

      final mirror = await query(
        'SELECT amount, employee_id FROM salary_withdrawals '
        'WHERE expense_uuid = ? AND deleted_at IS NULL',
        [uuid],
      );
      expect(mirror.single['amount'], 1800.0);
      expect(mirror.single['employee_id'], empId);

      final expense = await query(
        'SELECT amount, version FROM expenses WHERE local_uuid = ?',
        [uuid],
      );
      expect(expense.single['amount'], 1800.0);
      expect(expense.single['version'] as int, greaterThan(1));
    });
  });

  group('deleteSalaryExpense', () {
    test('حذف منطقي للمصروف ومرآته في معاملة واحدة', () async {
      await insertEmployee('emp-del');
      final uuid = await service.saveSalaryExpense(
        kind: ExpenseKind.salaryWithdrawal,
        amount: 900,
        date: '2026-11-02',
        employeeUuid: 'emp-del',
      );

      expect(await service.deleteSalaryExpense(uuid), isTrue);

      final expense = await query(
        'SELECT deleted_at FROM expenses WHERE local_uuid = ?',
        [uuid],
      );
      expect(expense.single['deleted_at'], isNotNull);

      final mirror = await query(
        'SELECT deleted_at FROM salary_withdrawals WHERE expense_uuid = ?',
        [uuid],
      );
      expect(mirror, hasLength(1));
      expect(mirror.single['deleted_at'], isNotNull);
      expect(await activeMirrors(uuid), 0);
    });

    test('حذف هوية غير موجودة يُرجع false بلا استثناء', () async {
      expect(await service.deleteSalaryExpense('uuid-not-there'), isFalse);
      expect(await service.deleteSalaryExpense('   '), isFalse);
    });
  });

  group('reassignEmployee', () {
    test('يحدّث الطرفين ويعيد اشتقاق الأرقام من UUID', () async {
      final firstEmployeeId = await insertEmployee('emp-first', name: 'أول');
      final secondEmployeeId = await insertEmployee('emp-second', name: 'ثاني');

      final uuid = await service.saveSalaryExpense(
        kind: ExpenseKind.salaryWithdrawal,
        amount: 1200,
        date: '2026-11-03',
        employeeUuid: 'emp-first',
      );

      expect(
        await service.reassignEmployee(
          expenseUuid: uuid,
          employeeUuid: 'emp-second',
        ),
        isTrue,
      );

      final expense = await query(
        'SELECT related_id, employee_uuid FROM expenses WHERE local_uuid = ?',
        [uuid],
      );
      expect(expense.single['related_id'], secondEmployeeId);
      expect(expense.single['employee_uuid'], 'emp-second');

      final mirror = await query(
        'SELECT employee_id, employee_uuid FROM salary_withdrawals '
        'WHERE expense_uuid = ?',
        [uuid],
      );
      expect(mirror.single['employee_id'], secondEmployeeId);
      expect(mirror.single['employee_uuid'], 'emp-second');
      expect(mirror.single['employee_id'], isNot(firstEmployeeId));
    });

    test('إعادة الإسناد لموظف غير محلول تُرفض بلا كتابة', () async {
      await insertEmployee('emp-stay');
      final uuid = await service.saveSalaryExpense(
        kind: ExpenseKind.salaryWithdrawal,
        amount: 400,
        date: '2026-11-03',
        employeeUuid: 'emp-stay',
      );

      await expectLater(
        service.reassignEmployee(
          expenseUuid: uuid,
          employeeUuid: 'emp-ghost',
        ),
        throwsA(isA<SalaryExpenseUnresolvedEmployee>()),
      );

      final expense = await query(
        'SELECT employee_uuid FROM expenses WHERE local_uuid = ?',
        [uuid],
      );
      expect(expense.single['employee_uuid'], 'emp-stay');
    });

    test('هوية الإسناد لا تُكتب على مرآة تراثية بلا هوية', () async {
      final empId = await insertEmployee('emp-owner');
      final uuid = await service.saveSalaryExpense(
        kind: ExpenseKind.salaryWithdrawal,
        amount: 300,
        date: '2026-11-04',
        employeeUuid: 'emp-owner',
      );
      final expenseId =
          (await query('SELECT id FROM expenses WHERE local_uuid = ?', [
                uuid,
              ])).single['id']
              as int;

      await db
          .into(db.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion.insert(
              localUuid: 'legacy-mirror',
              employeeId: empId,
              amount: 300,
              withdrawDate: '2026-11-04',
              createdAt: 1,
              updatedAt: 1,
              lastModified: 1,
            ),
          );
      // الرابط التراثي يُكتب بـ raw SQL (عمود expense_id معلن في Drift لكن
      // القيمة تعتمد على رقم المصروف المحلي).
      await db.customStatement(
        "UPDATE salary_withdrawals SET expense_id = ? "
        "WHERE local_uuid = 'legacy-mirror'",
        [expenseId],
      );

      await service.reassignEmployee(
        expenseUuid: uuid,
        employeeUuid: 'emp-owner',
      );

      // المرآة التراثية تُعاد إليها الأرقام المحلية، لكن **لا تُتبنّى** هوية
      // المصروف (expense_uuid يبقى NULL) — التبني عملية تدقيق منفصلة.
      final legacy = await query(
        'SELECT expense_uuid, employee_uuid, employee_id '
        "FROM salary_withdrawals WHERE local_uuid = 'legacy-mirror'",
      );
      expect(legacy.single['expense_uuid'], isNull);
      expect(legacy.single['employee_uuid'], 'emp-owner');
      expect(legacy.single['employee_id'], empId);
    });
  });

  group('سلامة التصنيف', () {
    test('kindOf يعيد null للمصروف غير الموجود', () async {
      expect(await service.kindOf('missing'), isNull);
    });

    test('التصنيف المكتوب صريح ويختلف عن النص الحر', () async {
      await insertEmployee('emp-kind');
      final uuid = await service.saveSalaryExpense(
        kind: ExpenseKind.advance,
        amount: 500,
        date: '2026-11-05',
        employeeUuid: 'emp-kind',
        description: 'سلفة',
      );
      expect(await service.kindOf(uuid), ExpenseKind.advance);

      final row = await query(
        'SELECT expense_kind, expense_type FROM expenses WHERE local_uuid = ?',
        [uuid],
      );
      expect(row.single['expense_kind'], 'advance');
      expect(row.single['expense_type'], 'سلفة');
    });
  });
}
