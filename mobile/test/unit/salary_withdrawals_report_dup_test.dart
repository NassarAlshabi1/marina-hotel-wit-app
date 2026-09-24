// ═══════════════════════════════════════════════════════════════
//  salary_withdrawals_report_dup_test.dart — (2026-09-25)
//
//  توضيح المستخدم: «التكرار يظهر في تقرير سحبيات الرواتب».
//
//  تقرير سحبيات الرواتب (salary_withdrawals_report_screen) يعرض
//  صفوف salary_withdrawals الحية فقط (deleted_at IS NULL) بلا أي
//  منطق إخفاء/مطابقة — إذن أي تكرار فيه = صفّان حيّان فعليان
//  في الجدول لنفس الحدث المالي.
//
//  الآلية المثبتة (من الكود المنشور للمستخدم): عند تعديل مصروف
//  راتب كانت سحوبته القديمة غير مرتبطة (إصدارات سابقة بلا
//  expense_id/exp_) لا يجدها saveFromExpense فتُدرج سحوبة جديدة
//  مرتبطة بينما القديمة تبقى حية → صفّان في التقرير (بالمبلغ
//  القديم والجديد، أو صفّان متطابقا المبلغ إن كان التعديل بلا
//  تغيير مبلغ).
//
//  الإصلاح: softDeleteUnlinkedDuplicatesForExpense تُستدعى قبل
//  التحديث فتنظّف اليتيمة غير المرتبطة (الدليل على سلامة ذلك:
//  كل السحب المباشر المشروع حتى قبل «زواج السحب» كان يحمل
//  reason = direct_withdrawal_ — أي صف حي بلا أي ربط ليس كياناً
//  مستقلاً بل صدى مصروف قديم).
//
//  هذه الاختبارات تقود استعلام التقرير نفسه (نسخة وفية من
//  _loadSalaryData): deleted_at IS NULL + فلتر hotel_day_key مع
//  fallback withdraw_date + فلتر الموظف.
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/utils/id.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

/// صف تقرير سحبيات الرواتب كما تعيده الشاشة
class _ReportRow {
  _ReportRow({required this.amount, required this.reason});

  final double amount;
  final String? reason;
}

/// نسخة وفية من استعلام salary_withdrawals_report_screen._loadSalaryData:
/// deleted_at IS NULL + فلتر hotel_day_key (مع fallback withdraw_date
/// للمفاتيح الفارغة) + فلتر الموظف الاختياري.
Future<List<_ReportRow>> salaryReportRows(
  AppDatabase db, {
  required String fromHotelDay,
  required String toHotelDay,
  int? employeeId,
}) async {
  var query = db.select(db.salaryWithdrawals)
    ..where((tbl) => tbl.deletedAt.isNull());

  query = query
    ..where(
      (tbl) =>
          (tbl.hotelDayKey.isNotNull() &
              tbl.hotelDayKey.isBiggerOrEqualValue(fromHotelDay)) |
          (tbl.hotelDayKey.isNull() &
              tbl.withdrawDate.isBiggerOrEqualValue(fromHotelDay)),
    );
  query = query
    ..where(
      (tbl) =>
          (tbl.hotelDayKey.isNotNull() &
              tbl.hotelDayKey.isSmallerOrEqualValue(toHotelDay)) |
          (tbl.hotelDayKey.isNull() &
              tbl.withdrawDate.isSmallerOrEqualValue(toHotelDay)),
    );

  if (employeeId != null) {
    query = query..where((tbl) => tbl.employeeId.equals(employeeId));
  }

  final rows = await query.get();
  return rows
      .map((sw) => _ReportRow(amount: sw.amount, reason: sw.reason))
      .toList();
}

Future<int> insertEmployee(AppDatabase db) {
  final now = Time.nowEpoch();
  return db
      .into(db.employees)
      .insert(
        EmployeesCompanion(
          localUuid: Value(IdGen.uuid()),
          name: const Value('موظف تقرير السحبيات'),
          basicSalary: const Value(1500.0),
          status: const Value('نشط'),
          createdAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
        ),
      );
}

/// سحوبة قديمة غير مرتبطة (شكل الإصدارات السابقة: بلا أي ربط)
Future<int> insertLegacyOrphanWithdrawal(
  AppDatabase db, {
  required int employeeId,
  required double amount,
  required String date,
  required String? hotelDayKey,
}) async {
  final now = Time.nowEpoch();
  final id = await db
      .into(db.salaryWithdrawals)
      .insert(
        SalaryWithdrawalsCompanion(
          localUuid: Value(IdGen.uuid()),
          employeeId: Value(employeeId),
          amount: Value(amount),
          withdrawDate: Value(date),
          reason: const Value(null),
          hotelDayKey: Value(hotelDayKey),
          withdrawalType: const Value('سحب راتب'),
          createdAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
        ),
      );
  return id;
}

/// مصروف راتب + سحوبته المرتبطة — نفس مسار شاشة المصروفات
Future<int> createSalaryExpensePair(
  AppDatabase db, {
  required ExpensesRepository expensesRepo,
  required SalaryWithdrawalsRepository salaryRepo,
  required int employeeId,
  required double amount,
  required String date,
}) async {
  final expenseId = await expensesRepo.create(
    expenseType: 'سحب راتب',
    relatedId: employeeId,
    description: 'سحب راتب',
    amount: amount,
    date: date,
    hotelDayKey: date,
    employeeUuid: null,
  );
  await salaryRepo.saveFromExpense(
    expenseId: expenseId,
    employeeId: employeeId,
    action: 'سحب راتب',
    amount: amount,
    date: date,
    note: 'سحب راتب',
    hotelDayKey: date,
  );
  return expenseId;
}

/// مسار التعديل الكامل من expenses_list (تنظيف ← تحديث ← حفظ)
Future<void> editExpenseViaScreenPath(
  AppDatabase db, {
  required ExpensesRepository expensesRepo,
  required SalaryWithdrawalsRepository salaryRepo,
  required int expenseId,
  required int employeeId,
  required double amount,
  required String date,
  bool runCleanup = true,
}) async {
  final existing = await (db.select(
    db.expenses,
  )..where((t) => t.id.equals(expenseId))).getSingle();

  if (runCleanup) {
    await salaryRepo.softDeleteUnlinkedDuplicatesForExpense(
      expenseId: existing.id,
      relatedEmployeeId: existing.relatedId,
      oldAmountAbs: existing.amount,
      oldDate: existing.date,
      oldHotelDayKey: existing.hotelDayKey,
    );
  }

  await expensesRepo.update(
    existing.id,
    expenseType: 'سحب راتب',
    relatedId: employeeId,
    description: 'سحب راتب (معدّل)',
    amount: amount,
    date: date,
    hotelDayKey: date,
    employeeUuid: null,
  );

  await salaryRepo.saveFromExpense(
    expenseId: expenseId,
    employeeId: employeeId,
    action: 'سحب راتب',
    amount: amount,
    date: date,
    note: 'سحب راتب (معدّل)',
    hotelDayKey: date,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ExpensesRepository expensesRepo;
  late SalaryWithdrawalsRepository salaryRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expensesRepo = ExpensesRepository(db);
    salaryRepo = SalaryWithdrawalsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'السيناريو المُبلَّغ: تعديل بلا تغيير مبلغ — التقرير يعرض سحوبة واحدة لا صفّين متطابقين',
    () async {
      final employeeId = await insertEmployee(db);

      final expenseId = await createSalaryExpensePair(
        db,
        expensesRepo: expensesRepo,
        salaryRepo: salaryRepo,
        employeeId: employeeId,
        amount: 100,
        date: '2026-09-25',
      );

      // سحوبة قديمة غير مرتبطة بنفس الموظف/المبلغ/اليوم
      final orphanId = await insertLegacyOrphanWithdrawal(
        db,
        employeeId: employeeId,
        amount: 100,
        date: '2026-09-25',
        hotelDayKey: '2026-09-25',
      );
      final orphan = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.id.equals(orphanId))).getSingle();

      // قبل التعديل: صفّان حيّان بنفس المبلغ — عين المستخدم تراهما مكررين
      final before = await salaryReportRows(
        db,
        fromHotelDay: '2026-09-25',
        toHotelDay: '2026-09-25',
        employeeId: employeeId,
      );
      expect(before, hasLength(2), reason: 'الحالة المُبلَّغة قبل الإصلاح');

      // تعديل الوصف/النوع دون تغيير المبلغ (نفس مسار الشاشة)
      await editExpenseViaScreenPath(
        db,
        expensesRepo: expensesRepo,
        salaryRepo: salaryRepo,
        expenseId: expenseId,
        employeeId: employeeId,
        amount: 100,
        date: '2026-09-25',
      );

      // بعد التعديل: سحوبة واحدة حية فقط
      final after = await salaryReportRows(
        db,
        fromHotelDay: '2026-09-25',
        toHotelDay: '2026-09-25',
        employeeId: employeeId,
      );
      expect(
        after,
        hasLength(1),
        reason: 'السحوبة اليتيمة نُظفت عند التعديل — التقرير يعرض صفاً واحداً',
      );
      expect(after.single.reason, 'exp_$expenseId');

      // حذف اليتيمة ناعم مزامَن عبر outbox (op=update يحمل deletedAt)
      final orphanAfter = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.id.equals(orphanId))).getSingle();
      expect(orphanAfter.deletedAt, isNotNull);

      final outboxRows = await (db.select(
        db.outbox,
      )..where((t) => t.entity.equals('salary_withdrawals'))).get();
      final orphanDeletes = outboxRows.where((o) {
        if (o.localUuid != orphan.localUuid || o.op != 'update') {
          return false;
        }
        final payload = jsonDecode(o.payload) as Map<String, dynamic>;
        return payload['deletedAt'] != null;
      }).toList();
      expect(
        orphanDeletes,
        hasLength(1),
        reason: 'الحذف الناعم يجب أن يصل لبقية الأجهزة عبر outbox',
      );
    },
  );

  test(
    'تعديل المبلغ 100 → 250: التقرير يعرض سحوبة واحدة بالمبلغ الجديد',
    () async {
      final employeeId = await insertEmployee(db);

      final expenseId = await createSalaryExpensePair(
        db,
        expensesRepo: expensesRepo,
        salaryRepo: salaryRepo,
        employeeId: employeeId,
        amount: 100,
        date: '2026-09-25',
      );
      await insertLegacyOrphanWithdrawal(
        db,
        employeeId: employeeId,
        amount: 100,
        date: '2026-09-25',
        hotelDayKey: '2026-09-25',
      );

      await editExpenseViaScreenPath(
        db,
        expensesRepo: expensesRepo,
        salaryRepo: salaryRepo,
        expenseId: expenseId,
        employeeId: employeeId,
        amount: 250,
        date: '2026-09-25',
      );

      final after = await salaryReportRows(
        db,
        fromHotelDay: '2026-09-25',
        toHotelDay: '2026-09-25',
        employeeId: employeeId,
      );
      expect(after, hasLength(1));
      expect(after.single.amount, 250);
      expect(after.single.reason, 'exp_$expenseId');
    },
  );

  test(
    'انحدار معكوس: بلا نداء التنظيف يتكرر الصف في التقرير (يُعيد إنتاج العَرَض المُبلَّغ)',
    () async {
      final employeeId = await insertEmployee(db);

      final expenseId = await createSalaryExpensePair(
        db,
        expensesRepo: expensesRepo,
        salaryRepo: salaryRepo,
        employeeId: employeeId,
        amount: 100,
        date: '2026-09-25',
      );
      await insertLegacyOrphanWithdrawal(
        db,
        employeeId: employeeId,
        amount: 100,
        date: '2026-09-25',
        hotelDayKey: '2026-09-25',
      );

      // نفس مسار الشاشة لكن بلا نداء softDeleteUnlinkedDuplicatesForExpense
      // (سلوك البناء المنشور قبل الإصلاح)
      await editExpenseViaScreenPath(
        db,
        expensesRepo: expensesRepo,
        salaryRepo: salaryRepo,
        expenseId: expenseId,
        employeeId: employeeId,
        amount: 250,
        date: '2026-09-25',
        runCleanup: false,
      );

      final after = await salaryReportRows(
        db,
        fromHotelDay: '2026-09-25',
        toHotelDay: '2026-09-25',
        employeeId: employeeId,
      );
      expect(
        after,
        hasLength(2),
        reason:
            'بلا التنظيف: سحوبة قديمة 100 + سحوبة مربوطة جديدة 250 — '
            'التكرار المُبلَّغ في تقرير سحبيات الرواتب',
      );
      final amounts = after.map((r) => r.amount).toSet();
      expect(amounts, containsAll(<double>[100, 250]));
    },
  );

  test(
    'الشكل القديم الأقدم (hotel_day_key فارغ): التنظيف بالتاريخ والفلتر يعمل بـ fallback withdraw_date',
    () async {
      final employeeId = await insertEmployee(db);

      final expenseId = await createSalaryExpensePair(
        db,
        expensesRepo: expensesRepo,
        salaryRepo: salaryRepo,
        employeeId: employeeId,
        amount: 100,
        date: '2026-09-25',
      );
      await insertLegacyOrphanWithdrawal(
        db,
        employeeId: employeeId,
        amount: 100,
        date: '2026-09-25',
        hotelDayKey: null, // أقدم إصدار — بلا مفتاح يوم فندقي
      );

      await editExpenseViaScreenPath(
        db,
        expensesRepo: expensesRepo,
        salaryRepo: salaryRepo,
        expenseId: expenseId,
        employeeId: employeeId,
        amount: 250,
        date: '2026-09-25',
      );

      final after = await salaryReportRows(
        db,
        fromHotelDay: '2026-09-25',
        toHotelDay: '2026-09-25',
        employeeId: employeeId,
      );
      expect(
        after,
        hasLength(1),
        reason: 'اليتيمة القديمة بلا مفتاح يوم تُطابق بالتاريخ وتُنظّف',
      );
      expect(after.single.amount, 250);
    },
  );
}
