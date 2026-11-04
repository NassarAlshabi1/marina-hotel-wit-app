// test/services/salary_expense_service_test.dart
//
// ✅ (2026-11-05 — وثيقة الربط والمزامنة الموحدة §6.1/§13) اختبارات
// الخدمة الذرية SalaryExpenseService:
// - المصروف + المرآة في transaction واحدة؛ فشل المرآة يلغي المصروف (§13).
// - تثبيت employeeUuid في الطرفين وexpenseUuid في المرآة وقت الكتابة.
// - منع مرآة ثانية نشطة للمصروف نفسه.
// - حذف ذري (tombstones للطرفين) وإعادة إسناد ذرية (§6.3).
// - تسديد سلفة نقدي: مرآة سالبة بلا مصروف (§6.2).
// - فشل حل الموظف يمنع أي كتابة (§5.2).
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/salary_expense_service.dart';

const String day = '2026-11-05';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<int> _insertEmployee(
  AppDatabase db, {
  String name = 'موظف الخدمة',
  String uuid = 'emp-uuid-svc',
}) => db
    .into(db.employees)
    .insert(
      EmployeesCompanion(
        name: d.Value(name),
        basicSalary: const d.Value(1000),
        status: const d.Value('active'),
        hireDate: const d.Value('2026-01-01'),
        localUuid: d.Value(uuid),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
      ),
    );

/// مستودع مرايا يفشل دائماً — لمحاكاة «فشل إنشاء المرآة» واختبار
/// أن المعاملة تلغي حفظ المصروف معه (§13).
class _ThrowingMirrorRepo extends SalaryWithdrawalsRepository {
  _ThrowingMirrorRepo(super.db);

  @override
  Future<void> saveFromExpense({
    required int expenseId,
    required int employeeId,
    required String action,
    required double amount,
    required String date,
    String? note,
    String? hotelDayKey,
    double? previousAmount,
    int? previousEmployeeId,
    bool originIsServer = false,
  }) async {
    throw StateError('فشل مرآة مُحاكى للاختبار (§13)');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SalaryExpenseService — الحفظ الذري (§6.1)', () {
    late AppDatabase database;
    late ExpensesRepository expensesRepo;
    late SalaryWithdrawalsRepository mirrorRepo;
    late SalaryExpenseService service;

    setUp(() {
      database = _db();
      expensesRepo = ExpensesRepository(database);
      mirrorRepo = SalaryWithdrawalsRepository(database);
      service = SalaryExpenseService(
        database,
        expensesRepo: expensesRepo,
        salaryRepo: mirrorRepo,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('إنشاء: مصروف + مرآة معاً مع تثبيت UUID في الطرفين', () async {
      await _insertEmployee(database, uuid: 'emp-uuid-svc');

      final result = await service.saveSalaryExpense(
        const SalaryExpenseDraft(
          expenseType: 'سحب راتب',
          amount: 250,
          date: day,
          hotelDayKey: day,
          description: 'سحب تجريبي',
          isSalaryFamily: true,
          employeeUuid: 'emp-uuid-svc',
        ),
      );

      // المصروف: موجود برابط الموظف.
      final expense = await (database.select(
        database.expenses,
      )..where((e) => e.id.equals(result.expenseId!))).getSingle();
      expect(expense.localUuid, result.expenseLocalUuid);
      expect(expense.employeeUuid, 'emp-uuid-svc');

      // المرآة: واحدة نشطة برابط المصروف الدائم ومبلغ موجب (سحب).
      final mirrors = await (database.select(
        database.salaryWithdrawals,
      )..where((w) => w.deletedAt.isNull())).get();
      expect(mirrors, hasLength(1));
      expect(mirrors.first.expenseUuid, expense.localUuid);
      expect(mirrors.first.employeeUuid, 'emp-uuid-svc');
      expect(mirrors.first.amount, 250);
      expect(result.mirrorLocalUuid, mirrors.first.localUuid);
    });

    test(
      'فشل إنشاء المرآة يلغي حفظ المصروف — transaction واحدة (§13)',
      () async {
        await _insertEmployee(database, uuid: 'emp-uuid-svc');
        final failing = SalaryExpenseService(
          database,
          expensesRepo: expensesRepo,
          salaryRepo: _ThrowingMirrorRepo(database),
        );

        await expectLater(
          failing.saveSalaryExpense(
            const SalaryExpenseDraft(
              expenseType: 'سحب راتب',
              amount: 100,
              date: day,
              hotelDayKey: day,
              description: 'سيناريو الفشل',
              isSalaryFamily: true,
              employeeUuid: 'emp-uuid-svc',
            ),
          ),
          throwsA(isA<StateError>()),
        );

        // المصروف لا يبقى بلا مرآة: التراجع الكامل.
        final expenses = await database.select(database.expenses).get();
        expect(
          expenses,
          isEmpty,
          reason: 'فشل المرآة يلغي المصروف (§13) — لا missing_mirror',
        );
      },
    );

    test('منع المرآة الثانية: حفظان متتاليان → مرآة نشطة واحدة', () async {
      await _insertEmployee(database, uuid: 'emp-uuid-svc');

      final first = await service.saveSalaryExpense(
        const SalaryExpenseDraft(
          expenseType: 'سحب راتب',
          amount: 100,
          date: day,
          hotelDayKey: day,
          description: 'أولى',
          isSalaryFamily: true,
          employeeUuid: 'emp-uuid-svc',
        ),
      );
      // حفظ ثانٍ لنفس العملية (نفس هوية المصروف) بمبلغ معدّل.
      final expenseRow = await (database.select(
        database.expenses,
      )..where((e) => e.id.equals(first.expenseId!))).getSingle();
      await service.saveSalaryExpense(
        SalaryExpenseDraft(
          existing: expenseRow,
          expenseType: 'سحب راتب',
          amount: 150,
          date: day,
          hotelDayKey: day,
          description: 'أولى (معدلة)',
          isSalaryFamily: true,
          employeeUuid: 'emp-uuid-svc',
        ),
      );

      final active = await (database.select(
        database.salaryWithdrawals,
      )..where((w) => w.deletedAt.isNull())).get();
      expect(active, hasLength(1), reason: 'لا مرآة ثانية نشطة (§6.1)');
      expect(active.first.amount, 150);
      expect(active.first.expenseUuid, first.expenseLocalUuid);
    });

    test('موظف غير محلول → لا أي كتابة (§5.2)', () async {
      await expectLater(
        service.saveSalaryExpense(
          const SalaryExpenseDraft(
            expenseType: 'سحب راتب',
            amount: 100,
            date: day,
            hotelDayKey: day,
            description: 'بلا موظف',
            isSalaryFamily: true,
            employeeUuid: 'no-such-uuid',
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await database.select(database.expenses).get(), isEmpty);
      expect(await database.select(database.salaryWithdrawals).get(), isEmpty);
    });

    test('تسديد سلفة نقدي: مرآة سالبة بلا مصروف (§6.2)', () async {
      await _insertEmployee(database, uuid: 'emp-uuid-svc');

      final result = await service.saveSalaryExpense(
        const SalaryExpenseDraft(
          expenseType: 'تسديد سلفة',
          amount: 75,
          date: day,
          hotelDayKey: day,
          description: 'تسديد نقدي',
          isSalaryFamily: true,
          employeeUuid: 'emp-uuid-svc',
          cashRepaymentOnly: true,
        ),
      );

      expect(result.cashRepayment, isTrue);
      expect(result.expenseId, isNull);
      expect(await database.select(database.expenses).get(), isEmpty);
      final mirrors = await (database.select(
        database.salaryWithdrawals,
      )..where((w) => w.deletedAt.isNull())).get();
      expect(mirrors, hasLength(1));
      expect(mirrors.first.amount, -75, reason: 'سداد لا سحب — سالب');
      expect(mirrors.first.expenseUuid, isNull, reason: 'بلا مصروف مرآة');
    });
  });

  group('SalaryExpenseService — الحذف وإعادة الإسناد الذريان (§6.3)', () {
    late AppDatabase database;
    late SalaryExpenseService service;

    setUp(() {
      database = _db();
      service = SalaryExpenseService(
        database,
        expensesRepo: ExpensesRepository(database),
        salaryRepo: SalaryWithdrawalsRepository(database),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('حذف ذري: soft-delete للمصروف والمرآة معاً', () async {
      await _insertEmployee(database, uuid: 'emp-uuid-svc');

      final created = await service.saveSalaryExpense(
        const SalaryExpenseDraft(
          expenseType: 'سحب راتب',
          amount: 120,
          date: day,
          hotelDayKey: day,
          description: 'سحب للحذف',
          isSalaryFamily: true,
          employeeUuid: 'emp-uuid-svc',
        ),
      );
      final expense = await (database.select(
        database.expenses,
      )..where((e) => e.id.equals(created.expenseId!))).getSingle();

      await service.deleteSalaryExpense(expense);

      final expenses = await database.select(database.expenses).get();
      expect(expenses.single.deletedAt, isNotNull, reason: 'tombstone مصروف');
      final mirrors = await database.select(database.salaryWithdrawals).get();
      expect(mirrors.single.deletedAt, isNotNull, reason: 'tombstone مرآة');
      // outbox للطرفين (§6.3).
      final outboxRows = await database.select(database.outbox).get();
      final entities = outboxRows.map((o) => o.entity).toSet();
      expect(entities, containsAll(['expenses', 'salary_withdrawals']));
      expect(
        outboxRows.where((o) => o.localUuid == expense.localUuid),
        isNotEmpty,
      );
    });

    test('إعادة إسناد: employeeUuid يتغير في المصروف والمرآة معاً', () async {
      final empA = await _insertEmployee(database, uuid: 'uuid-A');
      await _insertEmployee(database, name: 'موظف ب', uuid: 'uuid-B');

      final created = await service.saveSalaryExpense(
        const SalaryExpenseDraft(
          expenseType: 'سحب راتب',
          amount: 200,
          date: day,
          hotelDayKey: day,
          description: 'إعادة إسناد',
          isSalaryFamily: true,
          employeeUuid: 'uuid-A',
        ),
      );
      expect(created.expenseId, isNotNull);

      await service.reassignEmployee(
        expenseUuid: created.expenseLocalUuid,
        employeeUuid: 'uuid-B',
      );

      final expense =
          await (database.select(database.expenses)
                ..where((e) => e.localUuid.equals(created.expenseLocalUuid)))
              .getSingle();
      expect(expense.employeeUuid, 'uuid-B');
      expect(expense.relatedId, isNot(empA), reason: 'relatedId أُعيد اشتقاقه');

      final mirror =
          await (database.select(database.salaryWithdrawals)
                ..where((w) => w.expenseUuid.equals(created.expenseLocalUuid)))
              .getSingle();
      expect(mirror.employeeUuid, 'uuid-B', reason: 'المرآة تبعت المصروف');
      expect(mirror.employeeId, isNot(empA));
    });

    test('إعادة إسناد بموظف غير موجود تفشل بلا أي كتابة (§5.2)', () async {
      await _insertEmployee(database, uuid: 'uuid-A');

      final created = await service.saveSalaryExpense(
        const SalaryExpenseDraft(
          expenseType: 'سحب راتب',
          amount: 90,
          date: day,
          hotelDayKey: day,
          description: 'قبل الفشل',
          isSalaryFamily: true,
          employeeUuid: 'uuid-A',
        ),
      );

      await expectLater(
        service.reassignEmployee(
          expenseUuid: created.expenseLocalUuid,
          employeeUuid: 'ghost-uuid',
        ),
        throwsA(isA<StateError>()),
      );

      final expense =
          await (database.select(database.expenses)
                ..where((e) => e.localUuid.equals(created.expenseLocalUuid)))
              .getSingle();
      expect(expense.employeeUuid, 'uuid-A', reason: 'لم تُمسّ الروابط');
    });
  });
}
