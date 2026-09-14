// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/employee_link_consistency_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/employees_repository.dart';

/// ✅ اختبارات قاعدة «تعديل الموظف يحدّث الجداول المرتبطة بلا سجلات يتيمة».
///
/// الحالات المشتقة من الأدلة السحابية لحالة «الاورمو محمد» (2026-09-14):
/// مصروفات بمعرف رقمي لموظف آخر/ميت بينما الـ uuid يشير للصاحب الحقيقي.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late EmployeeLinkConsistencyService consistency;
  late EmployeesRepository employeesRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    consistency = EmployeeLinkConsistencyService(db);
    employeesRepo = EmployeesRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> createEmployee(String uuid, {String name = 'موظف'}) {
    return db
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
  }

  Future<int> createExpense({
    required String uuid,
    int? relatedId,
    String? employeeUuid,
    double amount = 5000,
    String type = 'سحب راتب',
  }) {
    return db
        .into(db.expenses)
        .insert(
          ExpensesCompanion(
            expenseType: d.Value(type),
            relatedId: relatedId != null
                ? d.Value(relatedId)
                : const d.Value.absent(),
            employeeUuid: employeeUuid != null
                ? d.Value(employeeUuid)
                : const d.Value.absent(),
            description: const d.Value(''),
            amount: d.Value(amount),
            date: const d.Value('2026-08-02'),
            hotelDayKey: const d.Value('2026-08-02'),
            localUuid: d.Value(uuid),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );
  }

  /// سحبة يتيمة بموظف ميت — تُدرج عبر SQL خام لمحاكاة السجلات القديمة
  /// القادمة من مسارات ما قبل FK أو من مزامنة قديمة (FK في Drift يمنع
  /// الإدراج عبر ORM — واليتائم الواقعية موجودة فعلاً في قواعد الأجهزة).
  Future<String> createOrphanWithdrawalRaw({
    required int deadEmployeeId,
    int? expenseId,
    double amount = 5000,
  }) async {
    final localUuid =
        'sw-orphan-$expenseId-$amount-${DateTime.now().microsecondsSinceEpoch}';
    // FK مفعل حتى للـ raw SQL — نطفئه مؤقتاً لمحاكاة سجل قديم وُجد قبل القيد
    await db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await db.customStatement(
        'INSERT INTO salary_withdrawals '
        '(employee_id, amount, withdraw_date, withdrawal_type, hotel_day_key, '
        'reason, expense_id, local_uuid, created_at, updated_at, last_modified, '
        'version, origin) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1000, 1000, 1000, 1, ?)',
        [
          deadEmployeeId,
          amount,
          '2026-08-02',
          'سحب راتب',
          '2026-08-02',
          expenseId != null ? 'exp_$expenseId' : null,
          expenseId,
          localUuid,
          'server',
        ],
      );
    } finally {
      await db.customStatement('PRAGMA foreign_keys = ON');
    }
    return localUuid;
  }

  group('مصروفات: توحيد الرقمي والـ uuid', () {
    test(
      'uuid يفوز: relatedId لموظف آخر يُعاد توجيهه للصاحب الحقيقي',
      () async {
        final ormo = await createEmployee('uuid-ormo', name: 'الاورمو محمد');
        final samah = await createEmployee('uuid-samah', name: 'سامح');

        // المصروف يشير رقمياً لسامح لكن uuid يقول: الأورمو محمد
        final expId = await createExpense(
          uuid: 'exp-1',
          relatedId: samah,
          employeeUuid: 'uuid-ormo',
        );

        final report = await consistency.repairLinksForEmployee(ormo);

        expect(report.expensesRelinked, 1);
        final exp = await (db.select(
          db.expenses,
        )..where((e) => e.id.equals(expId))).getSingle();
        expect(exp.relatedId, ormo, reason: 'uuid يفوز — المصروف يعود لصاحبه');
        expect(exp.employeeUuid, 'uuid-ormo');
        // وسامح لا يخسر شيئاً — لم يكن مالكاً أصلاً
        final samahExpenses = await (db.select(
          db.expenses,
        )..where((e) => e.relatedId.equals(samah))).get();
        expect(samahExpenses, isEmpty);
      },
    );

    test('backfill: مصروف برقمي صحيح و uuid فارغ يُعَبّأ', () async {
      final ormo = await createEmployee('uuid-ormo');
      final expId = await createExpense(
        uuid: 'exp-2',
        relatedId: ormo,
        employeeUuid: null,
      );

      final report = await consistency.repairLinksForEmployee(ormo);

      expect(report.expensesUuidBackfilled, 1);
      final exp = await (db.select(
        db.expenses,
      )..where((e) => e.id.equals(expId))).getSingle();
      expect(exp.employeeUuid, 'uuid-ormo');
    });

    test(
      'يتيم حقيقي: relatedId لموظف محذوف + uuid للموظف المعدَّل يُنقذ',
      () async {
        final ormo = await createEmployee('uuid-ormo');
        // مصروف بمعرف رقمي ميت (999 غير موجود) و uuid صحيح
        final expId = await createExpense(
          uuid: 'exp-3',
          relatedId: 999,
          employeeUuid: 'uuid-ormo',
        );

        final report = await consistency.repairLinksForEmployee(ormo);

        expect(report.expensesRelinked, 1);
        final exp = await (db.select(
          db.expenses,
        )..where((e) => e.id.equals(expId))).getSingle();
        expect(exp.relatedId, ormo);
      },
    );

    test('سليم لا يُمس: صفر إصلاحات وصفر ضوضاء outbox', () async {
      final ormo = await createEmployee('uuid-ormo');
      await createExpense(
        uuid: 'exp-ok',
        relatedId: ormo,
        employeeUuid: 'uuid-ormo',
      );

      final report = await consistency.repairLinksForEmployee(ormo);

      expect(report.hasRepairs, isFalse);
      final outboxCount = await db.select(db.outbox).get();
      expect(outboxCount, isEmpty, reason: 'لا ضوضاء مزامنة لصف سليم');
    });
  });

  group('سحوبات: إنقاذ اليتيمة عبر رابط المصروف', () {
    test(
      'سحبة employeeId ميت + expense_id لمصروف يملكه الموظف → تُنقذ',
      () async {
        final ormo = await createEmployee('uuid-ormo');
        final expId = await createExpense(
          uuid: 'exp-owner',
          relatedId: ormo,
          employeeUuid: 'uuid-ormo',
        );
        // سحبة يتيمة تشير لموظف ميت (999) لكن مربوطة بمصروف الأورمو
        final orphanUuid = await createOrphanWithdrawalRaw(
          deadEmployeeId: 999,
          expenseId: expId,
          amount: 5000,
        );

        final report = await consistency.repairLinksForEmployee(ormo);

        expect(report.withdrawalsRescued, 1);
        final sw = await (db.select(
          db.salaryWithdrawals,
        )..where((w) => w.localUuid.equals(orphanUuid))).getSingle();
        expect(sw.employeeId, ormo);
        // الإصلاح يجب أن يُدفع — outbox يحتوي السحبة بـ uuid صاحبها
        final outboxRows = await (db.select(
          db.outbox,
        )..where((t) => t.entity.equals('salary_withdrawals'))).get();
        expect(
          outboxRows.any((r) => r.localUuid == orphanUuid),
          isTrue,
          reason: 'السحبة المُصلَحة تُدفع للسحابة بـ uuid صاحبها',
        );
      },
    );

    test(
      'سحبة يتيمة بلا رابط مصروف → لا تُلمس (لا تخمين) وتُحصى للتقرير',
      () async {
        final ormo = await createEmployee('uuid-ormo');
        final orphanUuid = await createOrphanWithdrawalRaw(
          deadEmployeeId: 999,
          amount: 7000,
        );

        final report = await consistency.repairLinksForEmployee(ormo);

        expect(report.withdrawalsRescued, 0);
        expect(report.orphanWithdrawalsUnrescuable, 1);
        final sw = await (db.select(
          db.salaryWithdrawals,
        )..where((w) => w.localUuid.equals(orphanUuid))).getSingle();
        expect(
          sw.employeeId,
          999,
          reason: 'بلا دليل هوية — لا إعادة إسناد تخمينية',
        );
      },
    );
  });

  group('الربط بمسار التعديل الفعلي', () {
    test('employeesRepo.update يستدعي الإصلاح تلقائياً', () async {
      final ormo = await createEmployee('uuid-ormo');
      await createExpense(
        uuid: 'exp-auto',
        relatedId: 999,
        employeeUuid: 'uuid-ormo',
      );

      await employeesRepo.update(ormo, name: 'الاورمو محمد المعدَّل');

      final expenses = await (db.select(
        db.expenses,
      )..where((e) => e.relatedId.equals(ormo))).get();
      expect(expenses.length, 1, reason: 'الإصلاح جرى ضمن التعديل مباشرة');
    });

    test('terminate يستدعي الإصلاح تلقائياً', () async {
      final ormo = await createEmployee('uuid-ormo');
      await createExpense(
        uuid: 'exp-term',
        relatedId: 999,
        employeeUuid: 'uuid-ormo',
      );

      await employeesRepo.terminate(
        id: ormo,
        terminationType: 'terminated',
        terminationDate: '2026-09-14',
      );

      final expenses = await (db.select(
        db.expenses,
      )..where((e) => e.relatedId.equals(ormo))).get();
      expect(expenses.length, 1);
    });
  });
}
