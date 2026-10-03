// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';

/// اختبارات المرحلة 0 من docs/EMPLOYEE_EXPENSE_SALARY_LINK_DRAFT.md:
/// - R3: رقم مصروف متصادم عبر الأجهزة لا يمس سحبة موظف آخر.
/// - R12: تغيير موظف المصروف يحدّث employee_uuid للمرآة.
/// - R8: مصروف موظف (ومنه السلفة) من مصدر بعيد لا يأخذ relatedId الخام.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SalaryWithdrawalsRepository repo;
  late int empA;
  late int empB;

  Future<int> insertEmployee(String name, String uuid) => db
      .into(db.employees)
      .insert(
        EmployeesCompanion(
          name: d.Value(name),
          basicSalary: const d.Value(100000),
          status: const d.Value('active'),
          localUuid: d.Value(uuid),
          createdAt: const d.Value(1000),
          updatedAt: const d.Value(1000),
          lastModified: const d.Value(1000),
        ),
      );

  /// سحبة "مسحوبة من جهاز آخر" تحمل رقم مصروف ذلك الجهاز.
  Future<int> insertForeignMirror({
    required int employeeId,
    required String employeeUuid,
    required int foreignExpenseId,
    required double amount,
  }) async {
    final id = await db
        .into(db.salaryWithdrawals)
        .insert(
          SalaryWithdrawalsCompanion(
            employeeId: d.Value(employeeId),
            employeeUuid: d.Value(employeeUuid),
            amount: d.Value(amount),
            withdrawDate: const d.Value('2026-09-01'),
            withdrawalType: const d.Value('سحب راتب'),
            reason: d.Value('exp_$foreignExpenseId'),
            hotelDayKey: const d.Value('2026-09-01'),
            localUuid: d.Value('sw-foreign-$foreignExpenseId'),
            origin: const d.Value('server'),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );
    await db.customStatement(
      'UPDATE salary_withdrawals SET expense_id = ? WHERE id = ?',
      [foreignExpenseId, id],
    );
    return id;
  }

  Future<SalaryWithdrawal> byId(int id) => (db.select(
    db.salaryWithdrawals,
  )..where((t) => t.id.equals(id))).getSingle();

  Future<List<SalaryWithdrawal>> activeFor(int employeeId) =>
      (db.select(db.salaryWithdrawals)..where(
            (t) => t.employeeId.equals(employeeId) & t.deletedAt.isNull(),
          ))
          .get();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SalaryWithdrawalsRepository(db);
    empA = await insertEmployee(
      'موظف أ',
      'aaaaaaaa-0000-0000-0000-00000000000a',
    );
    empB = await insertEmployee(
      'موظف ب',
      'bbbbbbbb-0000-0000-0000-00000000000b',
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('R3: تصادم expense_id عبر الأجهزة', () {
    test(
      'saveFromExpense لموظف أ لا يعيد كتابة سحبة موظف ب ذات نفس الرقم',
      () async {
        final foreign = await insertForeignMirror(
          employeeId: empB,
          employeeUuid: 'bbbbbbbb-0000-0000-0000-00000000000b',
          foreignExpenseId: 5,
          amount: 7000,
        );

        await repo.saveFromExpense(
          expenseId: 5,
          employeeId: empA,
          action: 'سحب راتب',
          amount: 2000,
          date: '2026-10-01',
        );

        final b = await byId(foreign);
        expect(b.employeeId, empB, reason: 'سحبة ب لا تُنقل لموظف أ');
        expect(b.amount, 7000, reason: 'مبلغ سحبة ب لا يُعاد كتابته');
        expect(b.deletedAt, isNull, reason: 'سحبة ب لا تُحذف كـ stale');

        final a = await activeFor(empA);
        expect(a, hasLength(1));
        expect(a.single.amount, 2000);
      },
    );

    test('deleteByExpenseId بموظف المصروف لا يحذف سحبة موظف آخر', () async {
      final foreign = await insertForeignMirror(
        employeeId: empB,
        employeeUuid: 'bbbbbbbb-0000-0000-0000-00000000000b',
        foreignExpenseId: 9,
        amount: 5000,
      );
      await repo.saveFromExpense(
        expenseId: 9,
        employeeId: empA,
        action: 'سحب راتب',
        amount: 3000,
        date: '2026-10-01',
      );

      await repo.deleteByExpenseId(9, employeeId: empA);

      expect((await byId(foreign)).deletedAt, isNull);
      expect(await activeFor(empA), isEmpty);
    });

    test(
      'deleteByExpenseId يقبل المطابقة عبر employeeUuid (relatedId قديم)',
      () async {
        await repo.saveFromExpense(
          expenseId: 11,
          employeeId: empA,
          action: 'سحب راتب',
          amount: 1000,
          date: '2026-10-01',
        );
        await repo.deleteByExpenseId(
          11,
          employeeId: 999, // relatedId قديم لا يطابق
          employeeUuid: 'aaaaaaaa-0000-0000-0000-00000000000a',
        );
        expect(await activeFor(empA), isEmpty);
      },
    );
  });

  group('R12: تغيير موظف المصروف', () {
    test(
      'المرآة تنتقل للموظف الجديد مع employee_uuid الجديد — بلا تكرار',
      () async {
        await repo.saveFromExpense(
          expenseId: 7,
          employeeId: empA,
          action: 'سحب راتب',
          amount: 4000,
          date: '2026-10-01',
        );
        await repo.saveFromExpense(
          expenseId: 7,
          employeeId: empB,
          action: 'سحب راتب',
          amount: 4000,
          date: '2026-10-01',
          previousEmployeeId: empA,
        );

        expect(await activeFor(empA), isEmpty);
        final b = await activeFor(empB);
        expect(b, hasLength(1));
        expect(b.single.employeeUuid, 'bbbbbbbb-0000-0000-0000-00000000000b');
      },
    );
  });

  group('R8: مصروفات الموظفين من مصدر بعيد', () {
    test('سلفة من Appwrite بلا employeeUuid لا تأخذ relatedId الخام', () async {
      final adapters = AdapterRegistry(db);
      // relatedId=empA في جهاز المصدر يعني شخصاً آخر — يجب ألا يُربط هنا.
      await adapters.expenses.upsertFromJson({
        'localUuid': 'exp-advance-remote',
        'expenseType': 'سلفة',
        'relatedId': empA,
        'amount': 15000,
        'date': '2026-10-01',
        'hotelDayKey': '2026-10-01',
        'description': 'سلفة',
        'createdAt': 1000,
        'lastModified': 1000,
      }, src: Source.appwrite);

      final row = await (db.select(
        db.expenses,
      )..where((t) => t.localUuid.equals('exp-advance-remote'))).getSingle();
      expect(row.relatedId, isNull);
    });

    test('سلفة من Appwrite بـ employeeUuid تُربط بالموظف الصحيح', () async {
      final adapters = AdapterRegistry(db);
      await adapters.expenses.upsertFromJson({
        'localUuid': 'exp-advance-uuid',
        'expenseType': 'سلفة',
        'relatedId': empA, // رقم جهاز المصدر — يُتجاهل
        'employeeUuid': 'bbbbbbbb-0000-0000-0000-00000000000b',
        'amount': 15000,
        'date': '2026-10-01',
        'hotelDayKey': '2026-10-01',
        'description': 'سلفة',
        'createdAt': 1000,
        'lastModified': 1000,
      }, src: Source.appwrite);

      final row = await (db.select(
        db.expenses,
      )..where((t) => t.localUuid.equals('exp-advance-uuid'))).getSingle();
      expect(row.relatedId, empB);
    });

    test('مصروف عام (غير مرتبط بموظف) يحتفظ بـ relatedId كما هو', () async {
      final adapters = AdapterRegistry(db);
      await adapters.expenses.upsertFromJson({
        'localUuid': 'exp-general',
        'expenseType': 'صيانة',
        'relatedId': 42,
        'amount': 500,
        'date': '2026-10-01',
        'hotelDayKey': '2026-10-01',
        'description': 'صيانة',
        'createdAt': 1000,
        'lastModified': 1000,
      }, src: Source.appwrite);

      final row = await (db.select(
        db.expenses,
      )..where((t) => t.localUuid.equals('exp-general'))).getSingle();
      expect(row.relatedId, 42);
    });
  });
}
