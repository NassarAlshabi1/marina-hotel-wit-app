// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/salary_expense_classifier.dart';
import 'package:marina_hotel_mobile/services/salary_mirror_matcher.dart';

/// 🔬 إعادة إنتاج عيب «تعديل مبلغ مصروف راتب من شاشة عرض المصروفات
/// → يتكرر في التقرير».
///
/// يحاكي حرفياً مسار المستخدم:
/// 1. مصروف راتب 100 وصل لهذا الجهاز عبر المزامنة (رابط مرآته يحمل
///    معرّف جهاز المصدر — الحالة الموثقة «الاورمو محمد»).
/// 2. المستخدم يفتح شاشة عرض المصروفات ويعدّل المبلغ 100→150:
///    repo.update ثم salaryRepo.saveFromExpense (بنفس استدعاء الشاشة).
/// 3. نحسب إجمالي التقرير النقدي بنفس قواعد expenses_report_screen.
///
/// النتيجة على الكود قبل الإصلاح: 250 (تكرار!)
/// النتيجة على الكود بعد الإصلاح: 150 (صحيح)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const day = '2026-09-25';

  test('إعادة الإنتاج: تعديل 100→150 من شاشة عرض المصروفات', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final empId = await db
        .into(db.employees)
        .insert(
          const EmployeesCompanion(
            name: d.Value('موظف التحرير'),
            basicSalary: d.Value(1000),
            status: d.Value('active'),
            hireDate: d.Value('2026-01-01'),
            localUuid: d.Value('emp-uuid-edit'),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );

    // 1) مصروف الراتب كما وصل من جهاز المصدر (id محلي جديد هنا).
    final expenseId = await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion(
            expenseType: const d.Value('سحب راتب'),
            relatedId: d.Value(empId),
            employeeUuid: const d.Value('emp-uuid-edit'),
            amount: const d.Value(100),
            date: const d.Value(day),
            hotelDayKey: const d.Value(day),
            description: const d.Value('راتب شهر ٩'),
            localUuid: const d.Value('exp-repro-uuid'),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );

    // 2) مرآة الراتب كما وصلت من جهاز المصدر: رابطها 962 = معرّف
    //    المصروف على جهاز المصدر (أجنبي عن هذا الجهاز).
    await db
        .into(db.salaryWithdrawals)
        .insert(
          SalaryWithdrawalsCompanion(
            employeeId: d.Value(empId),
            amount: const d.Value(100),
            withdrawDate: const d.Value(day),
            withdrawalType: const d.Value('سحب راتب'),
            reason: const d.Value('exp_962'),
            expenseId: const d.Value(962),
            hotelDayKey: const d.Value(day),
            localUuid: const d.Value('sw-repro-uuid'),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );

    // قبل التعديل: التقرير = 100 مرة واحدة (Level 3 يطابق المبلغ).
    final before = await reportCashTotal(db);
    // ignore: avoid_print
    print('التقرير قبل التعديل: $before');

    // 3) تعديل المبلغ 100→150 — كما تفعل شاشة عرض المصروفات تماماً:
    final expensesRepo = ExpensesRepository(db);
    final salaryRepo = SalaryWithdrawalsRepository(db);
    await expensesRepo.update(expenseId, amount: 150);
    await salaryRepo.saveFromExpense(
      expenseId: expenseId,
      employeeId: empId,
      action: 'سحب راتب',
      amount: 150,
      date: day,
      note: 'راتب شهر ٩',
      hotelDayKey: day,
    );

    final after = await reportCashTotal(db);
    // ignore: avoid_print
    print('التقرير بعد التعديل: $after');

    // الإصلاح: المبلغ الصحيح مرة واحدة = 150.
    expect(after, 150, reason: 'قبل الإصلاح كان $after (مكرر)');
  });
}

/// إجمالي التقرير النقدي — نفس قواعد expenses_report_screen:
/// مصروفات غير خصمية + سحوبات يتيمة موجبة (غير خصمية، ليست مرايا).
Future<double> reportCashTotal(AppDatabase db) async {
  final expensesStmt = db.select(db.expenses)
    ..where((t) => t.deletedAt.isNull());
  final expenses = await expensesStmt.get();
  final withdrawalsStmt = db.select(db.salaryWithdrawals)
    ..where((t) => t.deletedAt.isNull());
  final withdrawals = await withdrawalsStmt.get();

  final candidates = expenses
      .map(
        (e) => MirrorExpenseCandidate(
          id: e.id,
          serverId: e.serverId,
          expenseType: e.expenseType,
          amount: e.amount,
          date: e.date,
          hotelDayKey: e.hotelDayKey,
          relatedId: e.relatedId,
        ),
      )
      .toList(growable: false);

  var total = 0.0;
  for (final e in expenses) {
    if (SalaryExpenseClassifier.isSalaryDeduction(e.expenseType)) continue;
    total += e.amount;
  }
  for (final sw in withdrawals) {
    if (sw.amount <= 0) continue;
    final wType = sw.withdrawalType ?? 'سحب راتب';
    if (wType.contains('خصم')) continue;
    final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
      expenseId: sw.expenseId,
      reason: sw.reason,
      amount: sw.amount,
      hotelDayKey: sw.hotelDayKey,
      withdrawDate: sw.withdrawDate,
      employeeId: sw.employeeId,
      expenses: candidates,
    );
    if (!isMirror) total += sw.amount;
  }
  return total;
}
