// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/salary_expense_classifier.dart';
import 'package:marina_hotel_mobile/services/salary_expense_service.dart';
import 'package:marina_hotel_mobile/services/salary_legacy_mirror_audit_tool.dart';
import 'package:marina_hotel_mobile/services/salary_mirror_matcher.dart';

/// 🔬 إعادة إنتاج عيب «تعديل مبلغ مصروف راتب من شاشة عرض المصروفات
/// → يتكرر في التقرير».
///
/// يحاكي حرفياً مسار المستخدم الحالي:
/// 1. مصروف راتب 100 وصل لهذا الجهاز عبر المزامنة (رابط مرآته يحمل
///    معرّف جهاز المصدر — الحالة الموثقة «الاورمو محمد»).
/// 2. المستخدم يفتح شاشة عرض المصروفات ويعدّل المبلغ 100→150:
///    ✅ (وثيقة §6.1) عبر SalaryExpenseService.saveSalaryExpense —
///    المسار الوحيد الذري الذي تمرّره الشاشة، ويتبنّى المرآة اليتيمة
///    بتمرير المبلغ/الموظف السابقين (هوية العملية لا الاستدلال).
/// 3. نحسب إجمالي التقرير النقدي بنفس قواعد expenses_report_screen.
///
/// النتيجة قبل إصلاح 2026-09-25: 250 (تكرار!)
/// النتيجة بعد إصلاح 2026-09-25 (التبنّي): 150 (صحيح)
/// النتيجة بعد §6.3 (2026-11-05): المستوى 4 أُزيل من القراءة —
/// التبنّي بهوية العملية هو الحاسم؛ وتحديث مباشر بلا تبنّي يظهر
/// غير محلول (250) في التقرير + مرشّح مشتبه به في أداة التدقيق.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const day = '2026-09-25';

  test(
    'إعادة الإنتاج: تعديل 100→150 من شاشة عرض المصروفات (مسار §6.1)',
    () async {
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
              createdAt: d.Value(1000),
              updatedAt: d.Value(1000),
              lastModified: d.Value(1000),
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

      // قبل التعديل: التقرير = 100 مرة واحدة (المستوى 3 يطابق المبلغ).
      final before = await reportCashTotal(db);
      // ignore: avoid_print
      print('التقرير قبل التعديل: $before');

      // 3) تعديل المبلغ 100→150 — كما تفعل شاشة عرض المصروفات حالياً:
      //    ✅ (وثيقة §6.1) الخدمة الذرية — تُشتق قيم التبنّي (المبلغ
      //    الموقّع القديم 100) من existing وتختم المرآة بالهوية الدائمة.
      final existing = await (db.select(
        db.expenses,
      )..where((e) => e.id.equals(expenseId))).getSingle();
      final service = SalaryExpenseService(
        db,
        expensesRepo: ExpensesRepository(db),
        salaryRepo: SalaryWithdrawalsRepository(db),
      );
      await service.saveSalaryExpense(
        SalaryExpenseDraft(
          existing: existing,
          expenseType: 'سحب راتب',
          amount: 150,
          date: day,
          hotelDayKey: day,
          description: 'راتب شهر ٩',
          isSalaryFamily: true,
          employeeUuid: 'emp-uuid-edit',
        ),
      );

      final after = await reportCashTotal(db);
      // ignore: avoid_print
      print('التقرير بعد التعديل: $after');

      // الإصلاح: المبلغ الصحيح مرة واحدة = 150 (تبنّي بهوية العملية).
      expect(after, 150, reason: 'قبل الإصلاح كان $after (مكرر)');

      // المرآة المتبنّاة أصبحت مرتبطة بهوية المصروف المحلي (§6.1).
      final mirror = await (db.select(
        db.salaryWithdrawals,
      )..where((w) => w.localUuid.equals('sw-repro-uuid'))).getSingle();
      expect(mirror.expenseUuid, 'exp-repro-uuid');
      expect(mirror.deletedAt, isNull, reason: 'تبنّي لا إنشاء مكرر');
    },
  );

  test('§6.3: تحديث مباشر بلا تبنّي → غير محلول (250) + دليل تدقيق', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final empId = await db
        .into(db.employees)
        .insert(
          const EmployeesCompanion(
            name: d.Value('موظف التدقيق'),
            basicSalary: d.Value(1000),
            status: d.Value('active'),
            hireDate: d.Value('2026-01-01'),
            localUuid: d.Value('emp-uuid-audit'),
            createdAt: d.Value(1000),
            updatedAt: d.Value(1000),
            lastModified: d.Value(1000),
          ),
        );
    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion(
            expenseType: const d.Value('سحب راتب'),
            relatedId: d.Value(empId),
            amount: const d.Value(100),
            date: const d.Value(day),
            hotelDayKey: const d.Value(day),
            description: const d.Value('راتب شهر ٩'),
            localUuid: const d.Value('exp-audit-uuid'),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );
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
            localUuid: const d.Value('sw-audit-uuid'),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );

    // تحديث مباشر بلا تبنّي (وصل من المزامنة بلا إعادة ربط).
    await (db.update(db.expenses)..where((t) => t.id.equals(1))).write(
      const ExpensesCompanion(amount: d.Value(150)),
    );

    // §6.3: بلا مطابقة استدلالية بتجاهل المبلغ → 250 ظاهرة (لا إخفاء).
    expect(await reportCashTotal(db), 250);

    // وأداة التدقيق التاريخي تعرض المرشّح الفريد للمراجعة اليدوية (§14).
    final expenses = await db.select(db.expenses).get();
    final withdrawals = await (db.select(
      db.salaryWithdrawals,
    )..where((t) => t.deletedAt.isNull())).get();
    final suspicions = SalaryLegacyMirrorAuditTool.findSuspectedMatches(
      withdrawals: withdrawals
          .map(
            (w) => LegacyAuditWithdrawal(
              id: w.id,
              localUuid: w.localUuid,
              employeeId: w.employeeId,
              expenseId: w.expenseId,
              reason: w.reason,
              expenseUuid: w.expenseUuid,
              amount: w.amount,
              withdrawDate: w.withdrawDate,
              hotelDayKey: w.hotelDayKey,
            ),
          )
          .toList(),
      expenses: expenses
          .map(
            (e) => MirrorExpenseCandidate(
              id: e.id,
              serverId: e.serverId,
              expenseType: e.expenseType,
              amount: e.amount,
              date: e.date,
              hotelDayKey: e.hotelDayKey,
              relatedId: e.relatedId,
              localUuid: e.localUuid,
            ),
          )
          .toList(),
    );
    expect(suspicions, hasLength(1));
    expect(suspicions.first.amountDiffers, isTrue);
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
