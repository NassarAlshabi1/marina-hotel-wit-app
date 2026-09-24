// ═══════════════════════════════════════════════════════════════
//  expense_edit_report_dup_test.dart — (2026-09-25) انحدار Bug 2
//
//  العَرَض المُبلَّغ: عند تعديل مبلغ مصروف (أو مصروف رواتب) يتكرر
//  السطر عند عرض التقرير.
//
//  الجذر (من الكود والتاريخ الموثَّق، لا تخمين):
//  سجلات قديمة بلا أي ربط (expense_id=NULL وreason بلا exp_ و ليست
//  direct_withdrawal) كانت تُخفى في تقرير المصروفات حصراً عبر
//  «المطابقة بالبيانات» — الطريقة 3 في expenses_report_screen
//  (نوع راتب + موظف + يوم + مبلغ متطابق). أول تعديل لمبلغ المصروف
//  يكسر تطابق المبلغ → السحوبة القديمة تصبح يتيمة → صف مكرر يظهر
//  في التقرير مع ازدواج المجموع.
//
//  الإصلاح: softDeleteUnlinkedDuplicatesForExpense تُستدعى من مسار
//  التعديل قبل تحديث المبلغ — تنظّف اليتيمة غير المرتبطة بحذف
//  ناعم + مزامنة outbox، مع استثناء صريح للسحوبات المباشرة وكل
//  ما يحمل ربط exp_/expense_id.
// ═══════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/utils/id.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

/// خوارزمية صفوف تقرير المصروفات — نسخة وفية من expenses_report_screen:
/// كل المصروفات الحية + السحوبات «اليتيمة» فقط (بلا مطابقة بالثلاث طرق).
Future<int> reportRowCount(AppDatabase db) async {
  final expenses = await (db.select(
    db.expenses,
  )..where((t) => t.deletedAt.isNull())).get();
  final withdrawals = await (db.select(
    db.salaryWithdrawals,
  )..where((t) => t.deletedAt.isNull())).get();

  final swExpenseId = <int, int>{};
  if (withdrawals.isNotEmpty) {
    final ids = withdrawals.map((w) => w.id).toList();
    final rows = await db
        .customSelect(
          'SELECT id, expense_id FROM salary_withdrawals '
          'WHERE id IN (${List.filled(ids.length, '?').join(',')})',
          variables: ids.map(Variable.withInt).toList(),
        )
        .get();
    for (final row in rows) {
      final raw = row.data['expense_id'];
      if (raw is int) swExpenseId[row.read<int>('id')] = raw;
    }
  }

  final addedExpenseIds = expenses.map((e) => e.id).toSet();
  var rows = expenses.length;
  for (final sw in withdrawals) {
    if (sw.reason?.startsWith('direct_withdrawal_') ?? false) {
      rows++; // يُعرض دائماً — كيان مستقل
      continue;
    }
    var matched = false;
    final byColumn = swExpenseId[sw.id];
    if (byColumn != null && addedExpenseIds.contains(byColumn)) {
      matched = true;
    }
    if (!matched && sw.reason != null) {
      final match = RegExp(r'exp_(\d+)').firstMatch(sw.reason!);
      if (match != null) {
        final expId = int.tryParse(match.group(1)!);
        matched = expId != null && addedExpenseIds.contains(expId);
      }
    }
    if (!matched) {
      // الطريقة 3: مطابقة بالبيانات (المخفية التاريخية للمكررات القديمة)
      for (final expense in expenses) {
        final isSalaryType = [
          'رواتب',
          'سحب راتب',
          'سحب من الراتب',
          'خصم راتب',
          'خصم من الراتب',
        ].contains(expense.expenseType);
        final dayMatch =
            sw.hotelDayKey == expense.hotelDayKey ||
            sw.withdrawDate.startsWith(expense.date);
        if (isSalaryType &&
            expense.relatedId == sw.employeeId &&
            dayMatch &&
            expense.amount.abs() == sw.amount.abs()) {
          matched = true;
          break;
        }
      }
    }
    if (!matched) rows++;
  }
  return rows;
}

Future<int> insertEmployee(AppDatabase db) {
  final now = Time.nowEpoch();
  return db
      .into(db.employees)
      .insert(
        EmployeesCompanion(
          localUuid: Value(IdGen.uuid()),
          name: const Value('موظف الانحدار'),
          basicSalary: const Value(1000.0),
          status: const Value('نشط'),
          createdAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
        ),
      );
}

Future<int> insertLegacyOrphanWithdrawal(
  AppDatabase db, {
  required int employeeId,
  required double amount,
  required String date,
  required String? hotelDayKey,
}) {
  final now = Time.nowEpoch();
  return db
      .into(db.salaryWithdrawals)
      .insert(
        SalaryWithdrawalsCompanion(
          localUuid: Value(IdGen.uuid()),
          employeeId: Value(employeeId),
          amount: Value(amount),
          withdrawDate: Value(date),
          // ⚠️ شكل السجل القديم المعطوب: بلا ربط إطلاقاً
          reason: const Value(null),
          hotelDayKey: Value(hotelDayKey),
          withdrawalType: const Value('سحب راتب'),
          createdAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ExpensesRepository expensesRepo;
  late SalaryWithdrawalsRepository salaryRepo;
  final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expensesRepo = ExpensesRepository(db);
    salaryRepo = SalaryWithdrawalsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('تعديل مبلغ المصروف مع سحوبة قديمة غير مرتبطة: لا يتكرر الصف', () async {
    final employeeId = await insertEmployee(db);

    // 1) المصروف المربوط بسحوبة سليمة (نمط الشاشة الحالي)
    final expenseId = await expensesRepo.create(
      expenseType: 'سحب راتب',
      relatedId: employeeId,
      description: 'سحب راتب',
      amount: 100,
      date: '2026-09-25',
      hotelDayKey: '2026-09-25',
      employeeUuid: null,
    );
    await salaryRepo.saveFromExpense(
      expenseId: expenseId,
      employeeId: employeeId,
      action: 'سحب راتب',
      amount: 100,
      date: '2026-09-25',
      note: 'سحب راتب',
      hotelDayKey: '2026-09-25',
    );

    // 2) سحوبة قديمة غير مرتبطة بنفس الموظف/المبلغ/اليوم
    //    (من إصدار قديم — تُخفى في التقرير بالطريقة 3 فقط)
    await insertLegacyOrphanWithdrawal(
      db,
      employeeId: employeeId,
      amount: 100,
      date: '2026-09-25',
      hotelDayKey: '2026-09-25',
    );

    // قبل التعديل: المكرر مخفي بمطابقة المبلغ → سطر واحد ظاهرياً
    expect(await reportRowCount(db), 1);

    // 3) التعديل 100 → 250 (نفس مسار الشاشة: تنظيف ثم تحديث ثم حفظ)
    final existing = await (db.select(
      db.expenses,
    )..where((t) => t.id.equals(expenseId))).getSingle();

    // الخطوة الجديدة في مسار التعديل (قبل repo.update):
    await salaryRepo.softDeleteUnlinkedDuplicatesForExpense(
      expenseId: existing.id,
      relatedEmployeeId: existing.relatedId,
      oldAmountAbs: existing.amount,
      oldDate: existing.date,
      oldHotelDayKey: existing.hotelDayKey,
    );

    await expensesRepo.update(
      existing.id,
      expenseType: 'سحب راتب',
      relatedId: employeeId,
      description: 'سحب راتب',
      amount: 250,
      date: '2026-09-25',
      hotelDayKey: '2026-09-25',
      employeeUuid: null,
    );
    await salaryRepo.saveFromExpense(
      expenseId: expenseId,
      employeeId: employeeId,
      action: 'سحب راتب',
      amount: 250,
      date: '2026-09-25',
      note: 'سحب راتب',
      hotelDayKey: '2026-09-25',
    );

    // بعد التعديل: اليتيمة القديمة حُذفت ناعماً → سطر واحد فعلاً
    expect(
      await reportRowCount(db),
      1,
      reason:
          'السحوبة القديمة غير المرتبطة نُظفت عند التعديل — '
          'لا صف مكرر ولا ازدواج مجموع',
    );

    // السحوبة السليمة الوحيدة باقية بالقيمة الجديدة
    final live = await (db.select(
      db.salaryWithdrawals,
    )..where((t) => t.deletedAt.isNull())).get();
    expect(live, hasLength(1));
    expect(live.single.amount, 250);
  });

  test(
    'التنظيف لا يلمس السحوبات المباشرة ولا المربوطة بغير هذا المصروف',
    () async {
      final employeeId = await insertEmployee(db);

      // سحوبة مباشرة مستقلة (كيان مالي مستقل بلا مصروف) بنفس الموظف/المبلغ/اليوم
      final now = Time.nowEpoch();
      await db
          .into(db.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion(
              localUuid: Value(IdGen.uuid()),
              employeeId: Value(employeeId),
              amount: const Value(100.0),
              withdrawDate: const Value('2026-09-25'),
              reason: const Value('direct_withdrawal_202609251'),
              hotelDayKey: const Value('2026-09-25'),
              withdrawalType: const Value('سحب راتب'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      await salaryRepo.softDeleteUnlinkedDuplicatesForExpense(
        expenseId: 999, // مصروف غير موجود أصلاً
        relatedEmployeeId: employeeId,
        oldAmountAbs: 100,
        oldDate: '2026-09-25',
        oldHotelDayKey: '2026-09-25',
      );

      final live = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.deletedAt.isNull())).get();
      expect(live, hasLength(1), reason: 'السحوبة المباشرة كيان مستقل — محمية');
      expect(live.single.deletedAt, isNull);
    },
  );

  test('التنظيف لا يعمل بلا موظف مرتبط (حارس relatedId)', () async {
    await salaryRepo.softDeleteUnlinkedDuplicatesForExpense(
      expenseId: 1,
      relatedEmployeeId: null,
      oldAmountAbs: 100,
      oldDate: '2026-09-25',
      oldHotelDayKey: '2026-09-25',
    );
    // لا استثناء — عقد صامت الحارس
  });
}
