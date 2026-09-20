// ignore_for_file: lines_longer_than_80_chars
// ═══════════════════════════════════════════════════════════════
//  employee_financial_history_guard_test.dart — 2026-09-21
//  «لفصل موظف استخدم «إنهاء الخدمة» من التطبيق (تغيّر الحالة فقط) —
//  أما الحذف فيتيّم تاريخه المالي على بقية الأجهزة»
//
//  اختبار خط الدفاع الأول في التطبيق:
//  EmployeesRepository.financialHistoryCount — قبل أي حذف موظف تُفحص
//  الجداول الخمسة (سحوبات/دورات/مدفوعات/ترحيلات/مصروفات مرتبطة).
//  العقد مطابق لحارس worker/sync.ts (عقد الربط نفسه — انظر
//  test/sync.employee-delete-guard.test.ts):
//   * employee_uuid أولاً — dash-insensitive
//   * المسك الرقمي سقوطٌ للصفوف عديمة uuid فقط
//   * expenses: related_id متعدد الدلالة → يُعتمد فقط مع الأنواع
//     المرتبطة بالموظف (دونها لا إيجابيات كاذبة)
//   * الـ tombstones تُحتسب (التاريخ المحذوف قابل للإحياء)
//   * الفشل لا يرمي — EmployeeFinancialHistory.unknown يمنع الحذف
// ═══════════════════════════════════════════════════════════════
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/employees_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late EmployeesRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = EmployeesRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  const now = 1700000000;
  final dashedUuid = 'aaaa1111-2222-3333-4444-555566667777';
  final dashlessUuid = dashedUuid.replaceAll('-', '');

  Future<int> seedEmployee({String? uuid}) async {
    return db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            name: 'موظف ${uuid ?? 'تلقائي'}',
            localUuid: uuid ?? dashedUuid,
            basicSalary: 500,
            status: 'active',
            createdAt: now,
            updatedAt: now,
            lastModified: now,
          ),
        );
  }

  Future<int> seedWithdrawal({int employeeId = 1, String? employeeUuid}) async {
    return db
        .into(db.salaryWithdrawals)
        .insert(
          SalaryWithdrawalsCompanion.insert(
            employeeId: employeeId,
            amount: 100,
            withdrawDate: '2026-09-10',
            localUuid: 'wd-${DateTime.now().microsecondsSinceEpoch}',
            employeeUuid: employeeUuid == null
                ? const d.Value.absent()
                : d.Value(employeeUuid),
            createdAt: now,
            updatedAt: now,
            lastModified: now,
          ),
        );
  }

  Future<int> seedExpense({
    String expenseType = 'سحب راتب',
    int? relatedId,
    String? employeeUuid,
    bool deleted = false,
  }) async {
    return db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            localUuid: 'exp-${DateTime.now().microsecondsSinceEpoch}',
            expenseType: expenseType,
            amount: 100,
            date: '2026-09-10',
            description: 'مصروف اختبار',
            relatedId: d.Value(relatedId),
            employeeUuid: employeeUuid == null
                ? const d.Value.absent()
                : d.Value(employeeUuid),
            deletedAt: deleted ? const d.Value(now) : const d.Value.absent(),
            createdAt: now,
            updatedAt: now,
            lastModified: now,
          ),
        );
  }

  Future<EmployeeFinancialHistory> historyFor(int id) =>
      repo.financialHistoryCount(id: id, localUuid: dashedUuid);

  // ═══════════════════════════════════════════════════════════════
  group('حارس التاريخ المالي — «الحذف يتيّم التاريخ المالي»', () {
    test('موظف بلا أي تاريخ مالي — لا يمنع الحذف', () async {
      final id = await seedEmployee();
      final h = await historyFor(id);
      expect(h.isKnown, true);
      expect(h.total, 0);
      expect(h.blocksDeletion, false, reason: 'موظف حديث خاطئ يُحذف بحرية');
    });

    test('سحب عبر employee_uuid يمنع الحذف', () async {
      final id = await seedEmployee();
      await seedWithdrawal(employeeId: id, employeeUuid: dashedUuid);
      final h = await historyFor(id);
      expect(h.withdrawals, 1);
      expect(h.blocksDeletion, true);
    });

    test('الشكل dashless للمسك يطابق أيضاً (الإنتاج يحوي الشكلين)', () async {
      final id = await seedEmployee();
      await seedWithdrawal(employeeId: id, employeeUuid: dashlessUuid);
      final h = await historyFor(id);
      expect(h.withdrawals, 1);
      expect(h.blocksDeletion, true);
    });

    test('سحب قديم بمسك رقمي (uuid=NULL) يمنع الحذف', () async {
      final id = await seedEmployee();
      await seedWithdrawal(employeeId: id, employeeUuid: null);
      final h = await historyFor(id);
      expect(h.withdrawals, 1);
      expect(h.blocksDeletion, true);
    });

    test('مصروف مرتبط عبر employee_uuid يمنع الحذف', () async {
      final id = await seedEmployee();
      await seedExpense(expenseType: 'سلفة', employeeUuid: dashedUuid);
      final h = await historyFor(id);
      expect(h.expenses, 1);
      expect(h.blocksDeletion, true);
    });

    test('مصروف راتب قديم بمسك related_id رقمي يمنع الحذف', () async {
      final id = await seedEmployee();
      await seedExpense(
        expenseType: 'سحب من الراتب',
        relatedId: id,
        employeeUuid: null,
      );
      final h = await historyFor(id);
      expect(h.expenses, 1);
      expect(h.blocksDeletion, true);
    });

    test(
      'مصروف «حجز» عابر يطابق related_id رقمياً — لا إيجابيات كاذبة',
      () async {
        final id = await seedEmployee();
        await seedExpense(
          expenseType: 'حجز',
          relatedId: id,
          employeeUuid: null,
        );
        final h = await historyFor(id);
        expect(h.expenses, 0, reason: 'related_id متعدد الدلالة — ليس تاريخاً');
        expect(h.blocksDeletion, false);
      },
    );

    test(
      'السحب المحذوف ناعماً (tombstone) يبقى حاجباً — قابل للإحياء',
      () async {
        final id = await seedEmployee();
        final wdId = await seedWithdrawal(
          employeeId: id,
          employeeUuid: dashedUuid,
        );
        // احذف السحب نفسه (soft delete) ثم تحقق
        await (db.update(db.salaryWithdrawals)..where((t) => t.id.equals(wdId)))
            .write(const SalaryWithdrawalsCompanion(deletedAt: d.Value(now)));
        final h = await historyFor(id);
        expect(h.withdrawals, 1, reason: 'tombstone يُحتسب — قابل للإحياء');
        expect(h.blocksDeletion, true);
      },
    );

    test('دورات رواتب / مدفوعات / ترحيلات مرتبطة تمنع الحذف', () async {
      // دورة عبر uuid
      final idA = await seedEmployee();
      await db
          .into(db.salaryCycles)
          .insert(
            SalaryCyclesCompanion.insert(
              employeeId: idA,
              cycleKey: '2026-09',
              localUuid: 'cyc-a',
              employeeUuid: d.Value(dashedUuid),
              createdAt: now,
              updatedAt: now,
              lastModified: now,
            ),
          );
      final hA = await historyFor(idA);
      expect(hA.cycles, 1);
      expect(hA.blocksDeletion, true);

      // دورة عبر المسك الرقمي (uuid=NULL)
      final idB = await seedEmployee(
        uuid: 'bbbb1111-2222-3333-4444-555566667777',
      );
      final cycB = await db
          .into(db.salaryCycles)
          .insert(
            SalaryCyclesCompanion.insert(
              employeeId: idB,
              cycleKey: '2026-09',
              localUuid: 'cyc-b',
              createdAt: now,
              updatedAt: now,
              lastModified: now,
            ),
          );
      final hB = await repo.financialHistoryCount(
        id: idB,
        localUuid: 'bbbb1111-2222-3333-4444-555566667777',
      );
      expect(hB.cycles, 1);
      expect(hB.blocksDeletion, true);

      // دفعة عبر employee_uuid (مرجعها الوحيد)
      await db
          .into(db.salaryPayments)
          .insert(
            SalaryPaymentsCompanion.insert(
              cycleId: cycB,
              paymentDateIso: '2026-09-10',
              localUuid: 'pay-b',
              employeeUuid: d.Value('bbbb1111-2222-3333-4444-555566667777'),
              createdAt: now,
              updatedAt: now,
              lastModified: now,
            ),
          );
      final hB2 = await repo.financialHistoryCount(
        id: idB,
        localUuid: 'bbbb1111-2222-3333-4444-555566667777',
      );
      expect(hB2.payments, 1);
      expect(hB2.blocksDeletion, true);

      // ترحيل عبر المسك الرقمي (لا يحمل uuid أصلاً)
      final idC = await seedEmployee(
        uuid: 'cccc1111-2222-3333-4444-555566667777',
      );
      await db
          .into(db.salaryCarryOverLogs)
          .insert(
            SalaryCarryOverLogsCompanion.insert(
              employeeId: idC,
              amount: 50,
              previousCycleStart: '2026-08-01',
              previousCycleEnd: '2026-08-31',
              newCycleStart: '2026-09-01',
              newCycleEnd: '2026-09-30',
              reason: 'ترحيل اختبار',
              carriedAt: now,
              localUuid: 'cko-c',
              createdAt: now,
              updatedAt: now,
              lastModified: now,
            ),
          );
      final hC = await repo.financialHistoryCount(
        id: idC,
        localUuid: 'cccc1111-2222-3333-4444-555566667777',
      );
      expect(hC.carryOvers, 1);
      expect(hC.blocksDeletion, true);
    });

    test('سحوبات موظف آخر لا تحجب موظفنا', () async {
      final otherId = await seedEmployee(
        uuid: 'dddd1111-2222-3333-4444-555566667777',
      );
      final myId = await seedEmployee();
      // سحب لموظف آخر عبر uuid الخاص به
      await seedWithdrawal(
        employeeId: otherId,
        employeeUuid: 'dddd1111-2222-3333-4444-555566667777',
      );
      final h = await historyFor(myId);
      expect(h.total, 0);
      expect(h.blocksDeletion, false);
    });

    test('موظف غير موجود محلياً — unknown يمنع الحذف احتياطاً', () async {
      final h = await historyFor(99999);
      expect(h.isKnown, false);
      expect(h.blocksDeletion, true, reason: 'الاتجاه الآمن دائماً');
    });
  });
}
