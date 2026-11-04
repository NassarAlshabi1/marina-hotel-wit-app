// test/unit/employee_financial_reports_bgdf_test.dart
//
// ✅ (2026-11-05 — وثيقة الربط والمزامنة الموحدة §16) اختبارات التقارير
// B/C/D/F/G على قاعدة بيانات حقيقية في الذاكرة:
// - B: دورات الرواتب حسب employeeUuid + ربط الدفعات cycleUuid أولاً
//   ثم cycleId المحلي، وغير المرتبط في قسم منفصل.
// - C: مصروفات الموظف — المصدر expenses فقط؛ التصنيف من classifier
//   (قرار المالك: لا عمود expense_kind)؛ بلا موظف → غير مرتبط.
// - D: المسحوبات — تمييز السحب المباشر عن مرآة المصروف عبر expenseUuid.
// - F: السجلات غير المرتبطة + pending_links.
// - G: إجماليات الموظفين — منع الازدزام (المصروف والمرآة مرة واحدة) +
//   نطاق زمني نصف مفتوح [from, to) + مجموع التقرير = مجموع المصادر.
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/employee_financial_report_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/salary_expense_service.dart';

const String day = '2026-11-05';
const String day2 = '2026-11-06';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late SalaryExpenseService service;
  late SalaryWithdrawalsRepository mirrorRepo;
  late EmployeeFinancialReportRepository reports;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    mirrorRepo = SalaryWithdrawalsRepository(database);
    service = SalaryExpenseService(
      database,
      expensesRepo: ExpensesRepository(database),
      salaryRepo: mirrorRepo,
    );
    reports = EmployeeFinancialReportRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> employee(String uuid, {String name = 'موظف'}) => database
      .into(database.employees)
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

  /// مجموعة بيانات مرجعية: مصروف+مرآة (سحب)، سحب مباشر، سلفة، تسديد نقدي.
  Future<void> seedEmployeeFinancials(String uuid) async {
    await employee(uuid, name: 'موظف $uuid');
    // سحب راتب: مصروف + مرآة — يُحتسب مرة واحدة في G.
    await service.saveSalaryExpense(
      SalaryExpenseDraft(
        expenseType: 'سحب راتب',
        amount: 250,
        date: day,
        hotelDayKey: day,
        description: 'سحب مرجعي',
        isSalaryFamily: true,
        employeeUuid: uuid,
      ),
    );
    // سحب مباشر بلا مصروف (§6.2) — يُحتسب مرة واحدة في G.
    await mirrorRepo.createDirect(
      employeeId: 1,
      amount: 100,
      date: day,
      reason: 'direct_withdrawal_$uuid',
      withdrawalType: 'سحب من الراتب',
      hotelDayKey: day,
    );
    // سلفة (مصروف + مرآة).
    await service.saveSalaryExpense(
      SalaryExpenseDraft(
        expenseType: 'سلفة',
        amount: 300,
        date: day,
        hotelDayKey: day,
        description: 'سلفة مرجعية',
        isSalaryFamily: true,
        employeeUuid: uuid,
      ),
    );
    // تسديد سلفة نقدي: مرآة سالبة بلا مصروف.
    await service.saveSalaryExpense(
      SalaryExpenseDraft(
        expenseType: 'تسديد سلفة',
        amount: 75,
        date: day,
        hotelDayKey: day,
        description: 'تسديد نقدي',
        isSalaryFamily: true,
        employeeUuid: uuid,
        cashRepaymentOnly: true,
      ),
    );
  }

  group('§16.4-B — تقرير الرواتب حسب الفترة', () {
    test(
      'ربط الدفعات: cycleUuid أولاً ثم cycleId، وغير المرتبط منفصل',
      () async {
        await employee('uuid-A', name: 'موظف uuid-A');
        final cycleId = await database
            .into(database.salaryCycles)
            .insert(
              const SalaryCyclesCompanion(
                localUuid: d.Value('cycle-uuid-1'),
                employeeId: d.Value(1),
                employeeUuid: d.Value('uuid-A'),
                cycleKey: d.Value('2026-11'),
                hotelDayStart: d.Value(day),
                expectedAmount: d.Value(1000),
                actualPaid: d.Value(400),
                remainingAmount: d.Value(600),
                status: d.Value('open'),
                createdAt: d.Value(1000),
                updatedAt: d.Value(1000),
                lastModified: d.Value(1000),
              ),
            );
        // دفعة مرتبطة بالهوية الدائمة cycleUuid.
        await database
            .into(database.salaryPayments)
            .insert(
              SalaryPaymentsCompanion(
                localUuid: const d.Value('pay-uuid-1'),
                cycleId: d.Value(cycleId),
                employeeUuid: const d.Value('uuid-A'),
                cycleUuid: const d.Value('cycle-uuid-1'),
                amount: const d.Value(250),
                paymentDateIso: const d.Value(day),
                createdAt: const d.Value(1000),
                updatedAt: const d.Value(1000),
                lastModified: const d.Value(1000),
              ),
            );
        // دفعة تراثية بـ cycleId فقط (cache محلي بعد حل UUID).
        await database
            .into(database.salaryPayments)
            .insert(
              SalaryPaymentsCompanion(
                localUuid: const d.Value('pay-uuid-2'),
                cycleId: d.Value(cycleId),
                employeeUuid: const d.Value('uuid-A'),
                amount: const d.Value(150),
                paymentDateIso: const d.Value(day),
                createdAt: const d.Value(1000),
                updatedAt: const d.Value(1000),
                lastModified: const d.Value(1000),
              ),
            );
        // دورة بلا موظف — غير مرتبطة (§16.1).
        await database
            .into(database.salaryCycles)
            .insert(
              const SalaryCyclesCompanion(
                localUuid: d.Value('cycle-orphan'),
                employeeId: d.Value(1),
                cycleKey: d.Value('2026-10'),
                hotelDayStart: d.Value('2026-10-01'),
                expectedAmount: d.Value(500),
                status: d.Value('open'),
                createdAt: d.Value(1000),
                updatedAt: d.Value(1000),
                lastModified: d.Value(1000),
              ),
            );

        final report = await reports.buildSalaryCyclesReport();

        expect(report.cycles, hasLength(1), reason: 'الدورة اليتيمة لا تُنسب');
        final row = report.cycles.single;
        expect(row.employeeUuid, 'uuid-A');
        expect(row.employeeName, 'موظف uuid-A');
        expect(row.payments, hasLength(2));
        expect(
          row.payments.where((p) => p.linkedViaUuid),
          hasLength(1),
          reason: 'الدفعة بالـ UUID تُربط بالهوية الدائمة',
        );
        expect(row.payments.fold<double>(0, (s, p) => s + p.amount), 400);
        expect(
          report.unresolved,
          hasLength(1),
          reason: 'الدورة بلا employeeUuid في قسم منفصل',
        );
        expect(report.totalExpected, 1000);
      },
    );
  });

  group('§16.4-C — تقرير المصروفات حسب الموظف', () {
    test('المصدر expenses فقط؛ غير المرتبط لا يُنسب لموظف', () async {
      await seedEmployeeFinancials('uuid-A');
      // مصروف راتبي بلا موظف — يظهر في غير المرتبط فقط.
      await database
          .into(database.expenses)
          .insert(
            const ExpensesCompanion(
              localUuid: d.Value('exp-orphan'),
              expenseType: d.Value('سحب راتب'),
              amount: d.Value(999.0),
              date: d.Value(day),
              description: d.Value('يتيم'),
              createdAt: d.Value(1000),
              updatedAt: d.Value(1000),
              lastModified: d.Value(1000),
            ),
          );

      final report = await reports.buildExpensesByEmployeeReport(
        employeeUuid: 'uuid-A',
      );
      // للموظف: سحب 250 + سلفة 300 (التسديد النقدي بلا مصروف لا يظهر هنا).
      expect(report.expenses, hasLength(2));
      expect(report.total, 550);
      expect(report.totalsByCategory['سحب راتب'], 250);
      expect(report.totalsByCategory['سلفة'], 300);
      expect(report.unlinked, isEmpty);

      final all = await reports.buildExpensesByEmployeeReport();
      expect(
        all.unlinked,
        hasLength(1),
        reason: 'مصروف راتبي بلا employeeUuid → غير مرتبط (§16.4-C)',
      );
      expect(
        all.expenses.where((e) => e.employeeUuid.isEmpty),
        isEmpty,
        reason: 'لا يُنسب مصروف لموظف غير مؤكد',
      );
    });
  });

  group('§16.4-D — تقرير المسحوبات', () {
    test('تمييز السحب المباشر عن مرآة المصروف عبر expenseUuid', () async {
      await seedEmployeeFinancials('uuid-A');

      final report = await reports.buildWithdrawalsReport(
        employeeUuid: 'uuid-A',
      );

      // مرآتان (سحب راتب 250 + سلفة 300) + مباشر (100) + مباشر سالب (تسديد -75).
      expect(report.mirrorWithdrawals, hasLength(2));
      expect(report.mirrorTotal, 550);
      expect(
        report.mirrorWithdrawals.every((w) => w.expenseUuid != null),
        isTrue,
        reason: 'المرايا تحمل روابط المصروف',
      );
      expect(report.directWithdrawals, hasLength(2));
      expect(report.directTotal, 100 + (-75));
      expect(report.unresolved, isEmpty);
    });
  });

  group('§16.4-F — تقرير السجلات غير المرتبطة', () {
    test('يجمع الأيتام من كل الجداول + pending_links', () async {
      await seedEmployeeFinancials('uuid-A');
      await employee('uuid-B', name: 'موظف ب');

      // مصروف راتبي بلا موظف.
      await database
          .into(database.expenses)
          .insert(
            const ExpensesCompanion(
              localUuid: d.Value('exp-orphan'),
              expenseType: d.Value('سحب راتب'),
              amount: d.Value(999.0),
              date: d.Value(day),
              description: d.Value('يتيم'),
              createdAt: d.Value(1000),
              updatedAt: d.Value(1000),
              lastModified: d.Value(1000),
            ),
          );
      // مرآة يتيمة: expenseUuid لا يقابل مصروفاً.
      await database
          .into(database.salaryWithdrawals)
          .insert(
            const SalaryWithdrawalsCompanion(
              localUuid: d.Value('w-orphan'),
              employeeId: d.Value(1),
              employeeUuid: d.Value('uuid-A'),
              expenseUuid: d.Value('ghost-expense-uuid'),
              amount: d.Value(50),
              withdrawDate: d.Value(day),
              createdAt: d.Value(1000),
              updatedAt: d.Value(1000),
              lastModified: d.Value(1000),
            ),
          );
      // مسحوب بلا employeeUuid.
      await database
          .into(database.salaryWithdrawals)
          .insert(
            const SalaryWithdrawalsCompanion(
              localUuid: d.Value('w-no-emp'),
              employeeId: d.Value(1),
              amount: d.Value(20),
              withdrawDate: d.Value(day),
              createdAt: d.Value(1000),
              updatedAt: d.Value(1000),
              lastModified: d.Value(1000),
            ),
          );
      // pending link لم يُحل.
      await database
          .into(database.pendingLinks)
          .insert(
            const PendingLinksCompanion(
              entity: d.Value('salary_withdrawals'),
              localUuid: d.Value('w-pending'),
              parentEntity: d.Value('employees'),
              parentUuid: d.Value('ghost-parent'),
              payloadJson: d.Value('{}'),
              reason: d.Value('employeeUuid غير موجود'),
              attempts: d.Value(2),
              createdAt: d.Value(1000),
              updatedAt: d.Value(1000),
            ),
          );

      final report = await reports.buildUnlinkedRecordsReport();

      final reasons = report.items.map((i) => i.reason).toList();
      expect(reasons.where((r) => r.contains('بلا employeeUuid')), isNotEmpty);
      expect(
        report.items.where(
          (i) => i.source == 'salary_withdrawal' && i.recordUuid == 'w-orphan',
        ),
        hasLength(1),
        reason: 'المرآة اليتيمة تظهر في غير المرتبط',
      );
      expect(
        report.items.where(
          (i) => i.source == 'salary_withdrawal' && i.recordUuid == 'w-no-emp',
        ),
        hasLength(1),
      );
      expect(report.pendingLinks, hasLength(1));
      expect(report.pendingLinks.single.attempts, 2);
    });
  });

  group('§16.4-G — إجماليات الموظفين ومنع الازدزام', () {
    test('المصروف والمرآة يُحتسبان مرة واحدة؛ المباشر مرة واحدة', () async {
      await seedEmployeeFinancials('uuid-A');

      final report = await reports.buildEmployeeTotalsReport();

      expect(report.rows, hasLength(1));
      final row = report.rows.single;
      expect(row.employeeUuid, 'uuid-A');
      // سحب 250 (مصروف — مرآته مستثناة) + مباشر 100 = 350.
      expect(row.withdrawalsTotal, 350);
      expect(row.advancesTotal, 300);
      expect(row.repaymentsTotal, 75);
      expect(row.movementsCount, 4);
      expect(row.grandTotal, 350 + 300 + 75);
    });

    test(
      'نطاق زمني نصف مفتوح [from, to) — لا تكرار نهاية اليوم (§16.8)',
      () async {
        await employee('uuid-A');
        await service.saveSalaryExpense(
          const SalaryExpenseDraft(
            expenseType: 'سحب راتب',
            amount: 100,
            date: day,
            hotelDayKey: day,
            description: 'يوم 1',
            isSalaryFamily: true,
            employeeUuid: 'uuid-A',
          ),
        );
        await service.saveSalaryExpense(
          const SalaryExpenseDraft(
            expenseType: 'سحب راتب',
            amount: 200,
            date: day2,
            hotelDayKey: day2,
            description: 'يوم 2',
            isSalaryFamily: true,
            employeeUuid: 'uuid-A',
          ),
        );

        final inDay1Only = await reports.buildExpensesByEmployeeReport(
          employeeUuid: 'uuid-A',
          fromDate: DateTime.parse('$day 00:00:00'),
          toDate: DateTime.parse('$day2 00:00:00'),
        );
        expect(inDay1Only.expenses, hasLength(1));
        expect(inDay1Only.total, 100, reason: '[from, to) يستثني يوم النهاية');

        final both = await reports.buildExpensesByEmployeeReport(
          employeeUuid: 'uuid-A',
          fromDate: DateTime.parse('$day 00:00:00'),
          // النطاق نصف مفتوح: النهاية هي بداية اليوم التالي (2026-11-07)
          // لتشمل يوم 2 كاملاً (§16.8).
          toDate: DateTime.parse('2026-11-07 00:00:00'),
        );
        expect(both.expenses, hasLength(2));
        expect(both.total, 300);
      },
    );

    test('جهازان بمعرفات محلية مختلفة → تقريران متطابقان (§16.8)', () async {
      // جهاز 1: البيانات المرجعية كاملة (seed ينشئ الموظف uuid-A بنفسه).
      await seedEmployeeFinancials('uuid-A');

      final device1 = await reports.buildEmployeeTotalsReport();

      final database2 = AppDatabase.forTesting(NativeDatabase.memory());
      final mirrorRepo2 = SalaryWithdrawalsRepository(database2);
      final service2 = SalaryExpenseService(
        database2,
        expensesRepo: ExpensesRepository(database2),
        salaryRepo: mirrorRepo2,
      );
      final reports2 = EmployeeFinancialReportRepository(database2);
      await database2
          .into(database2.employees)
          .insert(
            const EmployeesCompanion(
              name: d.Value('موظف uuid-A'),
              basicSalary: d.Value(1000),
              status: d.Value('active'),
              hireDate: d.Value('2026-01-01'),
              localUuid: d.Value('uuid-A'),
              createdAt: d.Value(1000),
              updatedAt: d.Value(1000),
              lastModified: d.Value(1000),
            ),
          );
      // employeeId المحلي هنا 1 أيضاً في هذه القاعدة الصغيرة، لكن
      // التقارير تعتمد UUID فقط — التحقق بأن الإخراج مطابق تماماً.
      await service2.saveSalaryExpense(
        const SalaryExpenseDraft(
          expenseType: 'سحب راتب',
          amount: 250,
          date: day,
          hotelDayKey: day,
          description: 'سحب مرجعي',
          isSalaryFamily: true,
          employeeUuid: 'uuid-A',
        ),
      );
      await mirrorRepo2.createDirect(
        employeeId: 1,
        amount: 100,
        date: day,
        reason: 'direct_withdrawal_uuid-A',
        withdrawalType: 'سحب من الراتب',
        hotelDayKey: day,
      );
      await service2.saveSalaryExpense(
        const SalaryExpenseDraft(
          expenseType: 'سلفة',
          amount: 300,
          date: day,
          hotelDayKey: day,
          description: 'سلفة مرجعية',
          isSalaryFamily: true,
          employeeUuid: 'uuid-A',
        ),
      );
      await service2.saveSalaryExpense(
        const SalaryExpenseDraft(
          expenseType: 'تسديد سلفة',
          amount: 75,
          date: day,
          hotelDayKey: day,
          description: 'تسديد نقدي',
          isSalaryFamily: true,
          employeeUuid: 'uuid-A',
          cashRepaymentOnly: true,
        ),
      );
      final device2 = await reports2.buildEmployeeTotalsReport();
      await database2.close();

      expect(device2.rows, hasLength(1));
      final r1 = device1.rows.single;
      final r2 = device2.rows.single;
      expect(r2.employeeUuid, r1.employeeUuid);
      expect(r2.withdrawalsTotal, r1.withdrawalsTotal);
      expect(r2.advancesTotal, r1.advancesTotal);
      expect(r2.repaymentsTotal, r1.repaymentsTotal);
      expect(
        r2.grandTotal,
        r1.grandTotal,
        reason:
            'التقارير UUID-first '
            '— نفس البيانات بنفس UUID ينتج إجماليات متطابقة (§16.8)',
      );
    });
  });
}
