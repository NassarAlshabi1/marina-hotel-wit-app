// ✅ (2026-11-04) اختبارات البنود المتبقية من «وثيقة الربط والمزامنة
// الموحدة» — PR-5 (pending_links) + PR-2/6 (relink المالي بعد الاستعادة)
// + §11 (تقرير السلامة الدائم).
//
// تغطي:
// 1. PendingLinksService: تسجيل دائم/upsert بلا تكرار، عدّاد محاولات،
//    الاستعلام بالمُعلق/بالأب، markResolved يُبقي الأثر ولا يحذف.
// 2. FinancialLinkRelinkService: إعادة اشتقاق الأرقام المحلية من UUID
//    (صيغ الثلاث)، بلا outbox وبلا version/lastModified (§10.2)، لا
//    تخمين للمراجع غير المحلولة (§4.2/§5.2)، وsalary_payments بلا
//    employeeId (يرتبط بالدورة عبر cycleUuid فقط).
// 3. FinancialIntegrityRepository (§11): مصروف بلا مرآة، مرآة يتيمة،
//    مرايا مكررة، مسحوب بلا موظف، روابط رقمية متقادمة، UUID مجهول،
//    pending links وoutbox متعثر، وقاعدة نظيفة → isClean.
import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/financial_integrity_repository.dart';
import 'package:marina_hotel_mobile/services/sync_core/financial_link_relink_service.dart';
import 'package:marina_hotel_mobile/services/sync_core/pending_links_service.dart';
import '../helpers/test_database.dart';

const _now = 1760000000;

AppDatabase _db() => TestDatabase.create();

Future<Employee> _insertEmployee(
  AppDatabase db, {
  required String localUuid,
  String name = 'موظف',
}) async {
  await db
      .into(db.employees)
      .insert(
        EmployeesCompanion.insert(
          localUuid: localUuid,
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
          name: name,
          basicSalary: 1000,
          status: 'active',
        ),
      );
  return (db.select(
    db.employees,
  )..where((e) => e.localUuid.equals(localUuid))).getSingle();
}

Future<int> _insertExpense(
  AppDatabase db, {
  required String localUuid,
  int? relatedId,
  String? employeeUuid,
  String expenseType = 'سحب من الراتب',
  double amount = 100,
  String date = '2026-11-01',
}) {
  return db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          localUuid: localUuid,
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
          expenseType: expenseType,
          description: 'اختبار',
          amount: amount,
          date: date,
          relatedId: d.Value(relatedId),
          employeeUuid: d.Value(employeeUuid),
        ),
      );
}

Future<int> _insertWithdrawal(
  AppDatabase db, {
  required String localUuid,
  required int employeeId,
  String? employeeUuid,
  int? expenseId,
  String? expenseUuid,
  double amount = 100,
  String date = '2026-11-01',
  String? withdrawalType = 'سحب من الراتب',
}) {
  return db
      .into(db.salaryWithdrawals)
      .insert(
        SalaryWithdrawalsCompanion.insert(
          localUuid: localUuid,
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
          employeeId: employeeId,
          employeeUuid: d.Value(employeeUuid),
          amount: amount,
          withdrawDate: date,
          expenseId: expenseId == null
              ? const d.Value.absent()
              : d.Value(expenseId),
          expenseUuid: d.Value(expenseUuid),
          withdrawalType: d.Value(withdrawalType),
        ),
      );
}

Future<int> _insertCycle(
  AppDatabase db, {
  required String localUuid,
  required int employeeId,
  String? employeeUuid,
  String cycleKey = '2026-10',
}) {
  return db
      .into(db.salaryCycles)
      .insert(
        SalaryCyclesCompanion.insert(
          localUuid: localUuid,
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
          employeeId: employeeId,
          employeeUuid: d.Value(employeeUuid),
          cycleKey: cycleKey,
        ),
      );
}

Future<int> _insertPayment(
  AppDatabase db, {
  required String localUuid,
  required int cycleId,
  String? cycleUuid,
  String? employeeUuid,
  int amount = 200,
}) {
  return db
      .into(db.salaryPayments)
      .insert(
        SalaryPaymentsCompanion.insert(
          localUuid: localUuid,
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
          cycleId: cycleId,
          cycleUuid: d.Value(cycleUuid),
          employeeUuid: d.Value(employeeUuid),
          amount: d.Value(amount),
          paymentDateIso: '2026-11-01',
        ),
      );
}

Future<int> _insertCarryOver(
  AppDatabase db, {
  required String localUuid,
  required int employeeId,
  String? employeeUuid,
}) {
  return db
      .into(db.salaryCarryOverLogs)
      .insert(
        SalaryCarryOverLogsCompanion.insert(
          localUuid: localUuid,
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
          employeeId: employeeId,
          employeeUuid: d.Value(employeeUuid),
          amount: 50,
          previousCycleStart: '2026-09-01',
          previousCycleEnd: '2026-09-30',
          newCycleStart: '2026-10-01',
          newCycleEnd: '2026-10-31',
          reason: 'اختبار',
          carriedAt: _now,
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PendingLinksService (§4.1/§5.2/§8.1)', () {
    test(
      '1. recordUnresolved يُنشئ صفاً ويزيد المحاولات دون تكرار الصفوف',
      () async {
        final db = _db();
        addTearDown(db.close);
        final svc = PendingLinksService(db);

        await svc.recordUnresolved(
          entity: 'salary_cycles',
          localUuid: 'cyc-1',
          parentEntity: 'employees',
          parentUuid: 'emp-1',
          payload: {'localUuid': 'cyc-1', 'amount': 500},
          reason: 'employee unresolved',
        );
        await svc.recordUnresolved(
          entity: 'salary_cycles',
          localUuid: 'cyc-1',
          parentEntity: 'employees',
          parentUuid: 'emp-1',
          payload: {'localUuid': 'cyc-1', 'amount': 600},
          reason: 'employee unresolved (retry)',
        );

        final rows = await db.select(db.pendingLinks).get();
        expect(rows.length, 1, reason: 'القيد الفريد (entity, localUuid)');
        expect(rows.first.attempts, 2);
        expect(rows.first.resolvedAt, isNull);
        final payload = rows.first.payloadJson;
        expect(
          payload.contains('600'),
          isTrue,
          reason: 'آخر payload هو المحفوظ',
        );
      },
    );

    test(
      '2. unresolved يُرجع المعلق فقط وmarkResolved يُبقي الأثر بلا حذف',
      () async {
        final db = _db();
        addTearDown(db.close);
        final svc = PendingLinksService(db);

        await svc.recordUnresolved(
          entity: 'salary_payments',
          localUuid: 'pay-1',
          parentEntity: 'salary_cycles',
          parentUuid: 'cyc-1',
          payload: {'localUuid': 'pay-1'},
          reason: 'cycle unresolved',
        );
        expect(await svc.unresolvedCount(), 1);

        await svc.markResolved('salary_payments', 'pay-1');
        expect(
          await svc.unresolvedCount(),
          0,
          reason: 'المحلول يخرج من قائمة المعلق',
        );
        final all = await db.select(db.pendingLinks).get();
        expect(all.length, 1, reason: 'الأثر يبقى — لا حذف (§1.3-1)');
        expect(all.first.resolvedAt, isNotNull);
        expect(all.first.resolvedHow, 'parent_arrived');
      },
    );

    test(
      '3. unresolvedForParent يفلتر بالأب وcountsByEntity تجمع بالكيان',
      () async {
        final db = _db();
        addTearDown(db.close);
        final svc = PendingLinksService(db);

        await svc.recordUnresolved(
          entity: 'salary_cycles',
          localUuid: 'cyc-1',
          parentEntity: 'employees',
          parentUuid: 'emp-A',
          payload: {},
          reason: 'r',
        );
        await svc.recordUnresolved(
          entity: 'salary_payments',
          localUuid: 'pay-1',
          parentEntity: 'salary_cycles',
          parentUuid: 'cyc-1',
          payload: {},
          reason: 'r',
        );

        final waitingEmployee = await svc.unresolvedForParent(
          parentEntity: 'employees',
          parentUuid: 'emp-A',
        );
        expect(waitingEmployee.map((r) => r.localUuid), ['cyc-1']);
        final counts = await svc.unresolvedCountsByEntity();
        expect(counts['salary_cycles'], 1);
        expect(counts['salary_payments'], 1);
      },
    );
  });

  group('FinancialLinkRelinkService (§5.1/§9.1/§9.2/§10.2)', () {
    test('4. يعيد اشتقاق كل الأرقام المشتقة من UUID ويصححها', () async {
      final db = _db();
      addTearDown(db.close);

      final emp = await _insertEmployee(
        db,
        localUuid: '11111111-2222-3333-4444-555555555555',
      );
      // موظف آخر + دورة/مصروف آخرون — الروابط الخاطئة الواقعية تشير
      // إلى صفوف موجودة فعلاً (علة "الاورمو محمد": relatedId يشير
      // لموظف آخر بينما employeeUuid يشير للصحيح).
      final emp2 = await _insertEmployee(db, localUuid: 'emp-other');
      final otherExpId = await _insertExpense(
        db,
        localUuid: 'exp-other',
        relatedId: emp2.id,
        employeeUuid: emp2.localUuid,
      );
      final otherCycId = await _insertCycle(
        db,
        localUuid: 'cyc-other',
        employeeId: emp2.id,
        employeeUuid: emp2.localUuid,
        cycleKey: '2026-09',
      );

      final expId = await _insertExpense(
        db,
        localUuid: 'exp-1',
        relatedId: emp2.id, // ❌ يشير لموظف آخر
        employeeUuid: emp.localUuid,
      );
      final cycId = await _insertCycle(
        db,
        localUuid: 'cyc-1',
        employeeId: emp2.id, // ❌ يشير لموظف آخر
        employeeUuid: emp.localUuid,
        cycleKey: '2026-10',
      );
      await _insertWithdrawal(
        db,
        localUuid: 'w-1',
        employeeId: emp2.id, // ❌
        employeeUuid: emp.localUuid,
        expenseId: otherExpId, // ❌ مصروف آخر
        expenseUuid: 'exp-1',
      );
      await _insertPayment(
        db,
        localUuid: 'p-1',
        cycleId: otherCycId, // ❌ دورة أخرى
        cycleUuid: 'cyc-1',
        employeeUuid: emp.localUuid,
      );
      await _insertCarryOver(
        db,
        localUuid: 'co-1',
        employeeId: emp2.id, // ❌
        employeeUuid: emp.localUuid,
      );

      final report = await FinancialLinkRelinkService(db).relinkAll();

      expect(report.expensesRelatedIdFixed, 1);
      expect(report.withdrawalsEmployeeIdFixed, 1);
      expect(report.withdrawalsExpenseIdFixed, 1);
      expect(report.cyclesEmployeeIdFixed, 1);
      expect(report.paymentsCycleIdFixed, 1);
      expect(report.carryOversEmployeeIdFixed, 1);
      expect(report.unresolvedEmployeeRefs, 0);
      expect(report.hasRepairs, isTrue);

      // التحقق الفعلي من القيم بعد التصحيح
      final exp = await (db.select(
        db.expenses,
      )..where((e) => e.id.equals(expId))).getSingle();
      expect(exp.relatedId, emp.id);
      final cyc = await (db.select(
        db.salaryCycles,
      )..where((c) => c.id.equals(cycId))).getSingle();
      expect(cyc.employeeId, emp.id);
      final w = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.localUuid.equals('w-1'))).getSingle();
      expect(w.employeeId, emp.id);
      expect(w.expenseId, expId);
      final p = await (db.select(
        db.salaryPayments,
      )..where((t) => t.localUuid.equals('p-1'))).getSingle();
      expect(p.cycleId, cycId);
    });

    test('5. صيغ UUID بلا شرطات تُحل أيضاً (بقايا Drive القديم)', () async {
      final db = _db();
      addTearDown(db.close);

      final emp = await _insertEmployee(
        db,
        localUuid: 'AABBCCDD-1122-3344-5566-778899001122',
      );
      await _insertExpense(
        db,
        localUuid: 'exp-stripped',
        relatedId: 123,
        employeeUuid: 'aabbccdd112233445566778899001122',
      );

      final report = await FinancialLinkRelinkService(db).relinkAll();
      expect(report.expensesRelatedIdFixed, 1);
      final exp = await (db.select(
        db.expenses,
      )..where((e) => e.localUuid.equals('exp-stripped'))).getSingle();
      expect(exp.relatedId, emp.id);
    });

    test('6. بلا outbox وبلا version/lastModified (§10.2) والمرجع غير '
        'المحلول لا يُخمَّن (§4.2)', () async {
      final db = _db();
      addTearDown(db.close);

      final emp = await _insertEmployee(db, localUuid: 'emp-x');
      final expId = await _insertExpense(
        db,
        localUuid: 'exp-x',
        relatedId: emp.id,
        employeeUuid: 'emp-x',
      );
      // مرجع مجهول: employeeUuid لا يطابق موظفاً — يجب أن يبقى كما هو.
      // employeeId يشير لموظف موجود (قيد FK) لكن UUID مجهول — لا يُمس.
      await _insertWithdrawal(
        db,
        localUuid: 'w-unknown',
        employeeId: emp.id,
        employeeUuid: 'no-such-employee-uuid',
      );

      final beforeW = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.localUuid.equals('w-unknown'))).getSingle();

      final outboxBefore = await db.select(db.outbox).get();
      await FinancialLinkRelinkService(db).relinkAll();
      final outboxAfter = await db.select(db.outbox).get();
      expect(
        outboxAfter.length,
        outboxBefore.length,
        reason: 'relink لا يكتب إلى outbox (§10.2)',
      );

      final afterW = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.localUuid.equals('w-unknown'))).getSingle();
      expect(
        afterW.employeeId,
        beforeW.employeeId,
        reason: 'لا تخمين — الرقم يبقى والمرجع يُعرض في التقرير',
      );
      expect(afterW.lastModified, beforeW.lastModified);
      expect(afterW.version, beforeW.version);

      // مصروف صحيح لم يُمس (لا false positive)
      final exp = await (db.select(
        db.expenses,
      )..where((e) => e.id.equals(expId))).getSingle();
      expect(exp.relatedId, emp.id);
    });

    test('7. idempotent — إعادة التشغيل تعيد صفر إصلاحات', () async {
      final db = _db();
      addTearDown(db.close);

      await _insertEmployee(db, localUuid: 'emp-i');
      await _insertExpense(
        db,
        localUuid: 'exp-i',
        relatedId: 42,
        employeeUuid: 'emp-i',
      );

      final first = await FinancialLinkRelinkService(db).relinkAll();
      expect(first.expensesRelatedIdFixed, 1);
      final second = await FinancialLinkRelinkService(db).relinkAll();
      expect(second.expensesRelatedIdFixed, 0);
      expect(second.hasRepairs, isFalse);
    });
  });

  group('FinancialIntegrityRepository (§11)', () {
    test('8. قاعدة نظيفة → isClean', () async {
      final db = _db();
      addTearDown(db.close);
      final report = await FinancialIntegrityRepository(db).build();
      expect(report.isClean, isTrue);
    });

    test('9. يكشف: بلا مرآة، مرآة يتيمة، مرايا مكررة، بلا موظف، '
        'روابط متقادمة، UUID مجهول', () async {
      final db = _db();
      addTearDown(db.close);

      final emp = await _insertEmployee(db, localUuid: 'emp-r');
      // مصروف بلا مرآة
      await _insertExpense(
        db,
        localUuid: 'exp-nomirror',
        relatedId: emp.id,
        employeeUuid: emp.localUuid,
      );
      // زوج سليم (مصروف + مرآة مرتبطة)
      final expOk = await _insertExpense(
        db,
        localUuid: 'exp-ok',
        relatedId: emp.id,
        employeeUuid: emp.localUuid,
        amount: 70,
      );
      await _insertWithdrawal(
        db,
        localUuid: 'w-ok',
        employeeId: emp.id,
        employeeUuid: emp.localUuid,
        expenseId: expOk,
        expenseUuid: 'exp-ok',
        amount: 70,
      );
      // مرآة يتيمة (expenseUuid غير موجود)
      await _insertWithdrawal(
        db,
        localUuid: 'w-orphan',
        employeeId: emp.id,
        employeeUuid: emp.localUuid,
        expenseUuid: 'no-such-expense',
      );
      // مرآة مكررة لنفس المصروف — البيانات القديمة (قبل حارس الفهرس
      // الفريد §4.1) لا تحمل الفهرس أصلاً، فنُسقطه لمحاكاتها بلا حذف صفوف.
      await db.customStatement(
        'DROP INDEX IF EXISTS ux_salary_withdrawals_expense_uuid_active',
      );
      await _insertWithdrawal(
        db,
        localUuid: 'w-dup-1',
        employeeId: emp.id,
        employeeUuid: emp.localUuid,
        expenseUuid: 'exp-dup',
      );
      await _insertWithdrawal(
        db,
        localUuid: 'w-dup-2',
        employeeId: emp.id,
        employeeUuid: emp.localUuid,
        expenseUuid: 'exp-dup',
      );
      // مصروف الدفع المكرر نفسه ليكون المرآتان "نشطتان بمرآتين"
      await _insertExpense(
        db,
        localUuid: 'exp-dup',
        relatedId: emp.id,
        employeeUuid: emp.localUuid,
      );
      // مسحوب بلا employeeUuid + رابط رقمي متقادم
      await _insertWithdrawal(
        db,
        localUuid: 'w-nouuid',
        employeeId: emp.id, // رقمي صحيح لكن بلا UUID — §11-3
        amount: 33,
      );
      // UUID مجهول
      await _insertCycle(
        db,
        localUuid: 'cyc-unknown',
        employeeId: emp.id,
        employeeUuid: 'ghost-employee-uuid',
      );

      final report = await FinancialIntegrityRepository(db).build();

      expect(
        report.salaryExpensesWithoutMirror.join(' '),
        contains('exp-nomirror'),
      );
      expect(
        report.activeMirrorsWithoutExpense.join(' '),
        contains('w-orphan'),
      );
      expect(report.duplicateActiveMirrors.length, 1);
      expect(report.duplicateActiveMirrors.first, contains('exp-dup'));
      expect(
        report.withdrawalsWithoutEmployeeUuid.join(' '),
        contains('w-nouuid'),
      );
      expect(
        report.unknownEmployeeUuidRefs.join(' '),
        contains('ghost-employee-uuid'),
      );
      expect(report.isClean, isFalse);
    });

    test(
      '10. يكشف اختلاف الأرقام المشتقة عمّا يحله UUID (§11-5/6/7)',
      () async {
        final db = _db();
        addTearDown(db.close);

        final emp = await _insertEmployee(db, localUuid: 'emp-m');
        final emp2 = await _insertEmployee(db, localUuid: 'emp-m2');
        // relatedId يشير لموظف آخر بينما UUID يشير لـ emp — تقرير يكشف
        await _insertExpense(
          db,
          localUuid: 'exp-mismatch',
          relatedId: emp2.id,
          employeeUuid: emp.localUuid,
        );
        await _insertWithdrawal(
          db,
          localUuid: 'w-mismatch',
          employeeId: emp2.id,
          employeeUuid: emp.localUuid,
        );

        final report = await FinancialIntegrityRepository(db).build();
        expect(report.relatedIdMismatches.join(' '), contains('exp-mismatch'));
        expect(report.employeeIdMismatches.join(' '), contains('w-mismatch'));
      },
    );

    test('11. يعرض pending links وoutbox المتعثر (§11-9/10)', () async {
      final db = _db();
      addTearDown(db.close);

      final svc = PendingLinksService(db);
      await svc.recordUnresolved(
        entity: 'salary_cycles',
        localUuid: 'cyc-pending',
        parentEntity: 'employees',
        parentUuid: 'emp-missing',
        payload: {'localUuid': 'cyc-pending'},
        reason: 'employee unresolved',
      );
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              entity: 'salary_payments',
              op: 'update',
              localUuid: 'pay-stuck',
              payload: '{"localUuid":"pay-stuck"}',
              clientTs: _now,
              attempts: const d.Value(9),
              lastError: const d.Value('network timeout'),
              processingStatus: const d.Value('failed'),
            ),
          );

      final report = await FinancialIntegrityRepository(db).build();
      expect(report.pendingLinks.join(' '), contains('cyc-pending'));
      expect(report.pendingLinks.join(' '), contains('محاولات=1'));
      expect(report.stuckOutbox.join(' '), contains('pay-stuck'));
      expect(report.stuckOutbox.join(' '), contains('network timeout'));
      expect(report.isClean, isFalse);
    });

    test('12. الإجماليات المحلية لكل موظف (جانب المقارنة §11)', () async {
      final db = _db();
      addTearDown(db.close);

      final emp = await _insertEmployee(db, localUuid: 'emp-t');
      await _insertExpense(
        db,
        localUuid: 'exp-t1',
        relatedId: emp.id,
        employeeUuid: emp.localUuid,
        amount: 100,
      );
      await _insertWithdrawal(
        db,
        localUuid: 'w-t1',
        employeeId: emp.id,
        employeeUuid: emp.localUuid,
        amount: 40,
      );

      final report = await FinancialIntegrityRepository(db).build();
      final totals = report.localTotalsByEmployee['emp-t'];
      expect(totals, isNotNull);
      expect(totals!.expenseCount, 1);
      expect(totals.expenseAmount, 100);
      expect(totals.withdrawalCount, 1);
      expect(totals.withdrawalAmount, 40);
    });
  });
}
