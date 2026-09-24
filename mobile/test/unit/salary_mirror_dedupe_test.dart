// ═══════════════════════════════════════════════════════════════
//  salary_mirror_dedupe_test.dart — (2026-09-25)
//
//  تغطية استخراج منطق المطابقة الموجود إلى SalaryMirrorMatcher
//  (resolveLinkedExpenseId + hasMirrorMarker) ووظيفة التنظيف
//  dedupeMirrorDuplicates في تقرير سحبيات الرواتب:
//
//   • السحوبات التي تُحلّ لنفس مصروف حقيقي واحد → تُدمج
//     (تبقى الأحدث تحديثاً فقط) مع حذف ناعم + مزامنة outbox.
//   • المرايا اليتيمة (رابط أجنبي مكسور) المطابقة لمصروف واحد
//     مُرسّى بالفعل لنفس الموظف/اليوم/النوع → حذف كمكرر مؤكد.
//   • الحماية: بلا علامة ربط / مطابقة غامضة / مصروف غير مُرسّى /
//     السحوبات المباشرة → لا حذف إطلاقاً (لا تخمين مالياً).
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/reports/salary_withdrawals_report_screen.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/salary_mirror_matcher.dart';
import 'package:marina_hotel_mobile/utils/id.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

const String _dayKey = '2026-09-20';
const String _fromDay = '2026-09-01';
const String _toDay = '2026-09-30';

Future<int> _insertEmployee(AppDatabase db) {
  final now = Time.nowEpoch();
  return db
      .into(db.employees)
      .insert(
        EmployeesCompanion(
          localUuid: Value(IdGen.uuid()),
          name: const Value('موظف مرايا السحوبات'),
          basicSalary: const Value(1500.0),
          status: const Value('نشط'),
          createdAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
        ),
      );
}

/// مصروف راتب حي (salary type) بموظف/يوم محددين.
Future<int> _insertSalaryExpense(
  AppDatabase db, {
  required int employeeId,
  required double amount,
  String expenseType = 'سحب راتب',
  String? hotelDayKey = _dayKey,
  String? date,
  int updatedAt = 1000,
}) async {
  final now = Time.nowEpoch();
  return db
      .into(db.expenses)
      .insert(
        ExpensesCompanion(
          localUuid: Value(IdGen.uuid()),
          expenseType: Value(expenseType),
          relatedId: Value(employeeId),
          description: const Value('سحب راتب'),
          amount: Value(amount),
          date: Value(date ?? _dayKey),
          hotelDayKey: Value(hotelDayKey),
          createdAt: Value(now),
          updatedAt: Value(updatedAt),
          lastModified: Value(now),
        ),
      );
}

/// سحوبة بتحكم كامل في حقول الرابط والتواريخ.
Future<int> _insertWithdrawal(
  AppDatabase db, {
  required int employeeId,
  required double amount,
  int? expenseId,
  String? reason,
  String? hotelDayKey = _dayKey,
  String withdrawDate = '$_dayKey 10:00',
  int updatedAt = 1000,
  int? deletedAt,
}) async {
  final now = Time.nowEpoch();
  return db
      .into(db.salaryWithdrawals)
      .insert(
        SalaryWithdrawalsCompanion(
          localUuid: Value(IdGen.uuid()),
          employeeId: Value(employeeId),
          amount: Value(amount),
          withdrawDate: Value(withdrawDate),
          reason: Value(reason),
          hotelDayKey: Value(hotelDayKey),
          withdrawalType: const Value('سحب راتب'),
          expenseId: expenseId == null
              ? const Value.absent()
              : Value(expenseId),
          createdAt: Value(now),
          updatedAt: Value(updatedAt),
          lastModified: Value(now),
          deletedAt: deletedAt == null ? const Value(null) : Value(deletedAt),
        ),
      );
}

Future<SalaryWithdrawal?> _loadWithdrawal(AppDatabase db, int id) async {
  return (db.select(
    db.salaryWithdrawals,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
}

/// استعلام التقرير نفسه (نطاق + deleted_at IS NULL) لقياس ما يعرضه.
Future<List<SalaryWithdrawal>> _reportRows(
  AppDatabase db, {
  required String fromDay,
  required String toDay,
}) async {
  var query = db.select(db.salaryWithdrawals)
    ..where((tbl) => tbl.deletedAt.isNull());
  query = query
    ..where(
      (tbl) =>
          (tbl.hotelDayKey.isNotNull() &
              tbl.hotelDayKey.isBiggerOrEqualValue(fromDay)) |
          (tbl.hotelDayKey.isNull() &
              tbl.withdrawDate.isBiggerOrEqualValue(fromDay)),
    );
  query = query
    ..where(
      (tbl) =>
          (tbl.hotelDayKey.isNotNull() &
              tbl.hotelDayKey.isSmallerOrEqualValue(toDay)) |
          (tbl.hotelDayKey.isNull() &
              tbl.withdrawDate.isSmallerOrEqualValue(toDay)),
    );
  return query.get();
}

Future<MirrorDedupeResult> _runDedupe(
  AppDatabase db,
  List<SalaryWithdrawal> rows,
) => dedupeMirrorDuplicates(
  db,
  withdrawals: rows,
  fromHotelDay: _fromDay,
  toHotelDay: _toDay,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  group('SalaryMirrorMatcher.hasMirrorMarker', () {
    test('العمود الخام expense_id = علامة', () {
      final sw = SalaryWithdrawal(
        localUuid: 'u1',
        createdAt: 0,
        updatedAt: 0,
        lastModified: 0,
        createdAtEpoch: 0,
        lastModifiedEpoch: 0,
        version: 1,
        origin: 'local',
        vectorClock: '{}',
        deviceId: '',
        syncTimestamp: 0,
        id: 1,
        employeeId: 1,
        amount: 100,
        withdrawDate: _dayKey,
        reason: null,
        hotelDayKey: null,
        withdrawalType: null,
        description: null,
        expenseId: 5,
      );
      expect(SalaryMirrorMatcher.hasMirrorMarker(sw), isTrue);
    });

    test('reason بعلامة exp_<رقم> = علامة حتى بلا عمود', () {
      final sw = SalaryWithdrawal(
        localUuid: 'u2',
        createdAt: 0,
        updatedAt: 0,
        lastModified: 0,
        createdAtEpoch: 0,
        lastModifiedEpoch: 0,
        version: 1,
        origin: 'local',
        vectorClock: '{}',
        deviceId: '',
        syncTimestamp: 0,
        id: 2,
        employeeId: 1,
        amount: 100,
        withdrawDate: _dayKey,
        reason: 'سحب مرتبط exp_12',
        hotelDayKey: null,
        withdrawalType: null,
        description: null,
        expenseId: null,
      );
      expect(SalaryMirrorMatcher.hasMirrorMarker(sw), isTrue);
    });

    test('بلا أي ربط / سبب يدوي / سحب مباشر / exp_ بلا رقم = لا علامة', () {
      SalaryWithdrawal build({String? reason, int? expenseId}) =>
          SalaryWithdrawal(
            localUuid: 'u3',
            createdAt: 0,
            updatedAt: 0,
            lastModified: 0,
            createdAtEpoch: 0,
            lastModifiedEpoch: 0,
            version: 1,
            origin: 'local',
            vectorClock: '{}',
            deviceId: '',
            syncTimestamp: 0,
            id: 3,
            employeeId: 1,
            amount: 100,
            withdrawDate: _dayKey,
            reason: reason,
            hotelDayKey: null,
            withdrawalType: null,
            description: null,
            expenseId: expenseId,
          );

      expect(SalaryMirrorMatcher.hasMirrorMarker(build()), isFalse);
      expect(
        SalaryMirrorMatcher.hasMirrorMarker(build(reason: 'سحب نقدي عادي')),
        isFalse,
      );
      expect(
        SalaryMirrorMatcher.hasMirrorMarker(
          build(reason: 'direct_withdrawal_abc-123-abc'),
        ),
        isFalse,
      );
      expect(
        SalaryMirrorMatcher.hasMirrorMarker(build(reason: 'exp_ بلا رقم')),
        isFalse,
      );
    });
  });

  group('SalaryMirrorMatcher.resolveLinkedExpenseId', () {
    test('Level 1: العمود الخام إلى مصروف حي يُعاد فوراً', () async {
      final empId = await _insertEmployee(db);
      final expenseId = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 100,
      );
      final swId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 100,
        expenseId: expenseId,
      );
      final sw = await _loadWithdrawal(db, swId);
      expect(
        await SalaryMirrorMatcher.resolveLinkedExpenseId(db, sw!),
        expenseId,
      );
    });

    test('Level 1 له الأولوية على Level 2 عند نجاحهما معاً', () async {
      final empId = await _insertEmployee(db);
      final expenseA = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 100,
      );
      final expenseB = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 200,
      );
      final swId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 100,
        expenseId: expenseA,
        reason: 'exp_$expenseB',
      );
      final sw = await _loadWithdrawal(db, swId);
      expect(
        await SalaryMirrorMatcher.resolveLinkedExpenseId(db, sw!),
        expenseA,
      );
    });

    test('Level 1 مكسور → fallback إلى Level 2 عبر reason', () async {
      final empId = await _insertEmployee(db);
      final expenseLive = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 100,
      );
      final swId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 100,
        expenseId: 999999, // هدف غير موجود — رابط مكسور
        reason: 'exp_$expenseLive',
      );
      final sw = await _loadWithdrawal(db, swId);
      expect(
        await SalaryMirrorMatcher.resolveLinkedExpenseId(db, sw!),
        expenseLive,
      );
    });

    test('هدف محذوف ناعماً = رابط مكسور → null (لا مصروف غير حقيقي)', () async {
      final empId = await _insertEmployee(db);
      final expenseId = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 100,
      );
      // حذف ناعم للمصروف
      await (db.update(
        db.expenses,
      )..where((t) => t.id.equals(expenseId))).write(
        ExpensesCompanion(deletedAt: Value(Time.nowEpoch())),
      );
      final swId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 100,
        expenseId: expenseId,
      );
      final sw = await _loadWithdrawal(db, swId);
      expect(await SalaryMirrorMatcher.resolveLinkedExpenseId(db, sw!), isNull);
    });

    test('مرجعان حيّان في reason = غموض → null', () async {
      final empId = await _insertEmployee(db);
      final expenseA = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 100,
      );
      final expenseB = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 200,
      );
      final swId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 100,
        reason: 'exp_$expenseA و exp_$expenseB',
      );
      final sw = await _loadWithdrawal(db, swId);
      expect(await SalaryMirrorMatcher.resolveLinkedExpenseId(db, sw!), isNull);
    });
  });

  group('dedupeMirrorDuplicates — الدمج', () {
    test(
      'سحوبتان تحلّان لنفس المصروف الحقيقي → تبقى الأحدث تحديثاً فقط',
      () async {
        final empId = await _insertEmployee(db);
        final expenseId = await _insertSalaryExpense(
          db,
          employeeId: empId,
          amount: 300,
        );
        final olderId = await _insertWithdrawal(
          db,
          employeeId: empId,
          amount: 300,
          expenseId: expenseId,
          updatedAt: 1000,
        );
        final newerId = await _insertWithdrawal(
          db,
          employeeId: empId,
          amount: 300,
          reason: 'exp_$expenseId',
          updatedAt: 2000,
        );

        final rows = await _reportRows(db, fromDay: _fromDay, toDay: _toDay);
        expect(rows.length, 2); // قبل التنظيف: التكرار ظاهر
        final result = await _runDedupe(db, rows);

        expect(result.mergedAway, 1);
        expect(result.orphansDeleted, 0);
        expect(result.kept.length, 1);
        expect(result.kept.single.id, newerId); // الأحدث تحديثاً

        final older = await _loadWithdrawal(db, olderId);
        final newer = await _loadWithdrawal(db, newerId);
        expect(older!.deletedAt, isNotNull); // حذف ناعم
        expect(older.version, 2); // bump version
        expect(newer!.deletedAt, isNull);

        expect(
          (await _reportRows(db, fromDay: _fromDay, toDay: _toDay)).length,
          1,
        );
      },
    );

    test('ترتيب الإدراج لا يخلط بين الأحدث تحديثاً والأقدم', () async {
      final empId = await _insertEmployee(db);
      final expenseId = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 300,
      );
      // يُدرج لاحقاً (id أكبر) لكنه الأقدم تحديثاً — يجب أن يُحذف
      final laterInsertedId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 300,
        expenseId: expenseId,
        updatedAt: 1000,
      );
      final earlierInsertedId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 300,
        reason: 'exp_$expenseId',
        updatedAt: 5000,
      );

      final rows = await _reportRows(db, fromDay: _fromDay, toDay: _toDay);
      final result = await _runDedupe(db, rows);

      expect(result.kept.single.id, earlierInsertedId);
      final loser = await _loadWithdrawal(db, laterInsertedId);
      expect(loser!.deletedAt, isNotNull);
    });

    test('الحذف الناعم يزامَن عبر outbox (ذرية مالية)', () async {
      final empId = await _insertEmployee(db);
      final expenseId = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 300,
      );
      final loserId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 300,
        expenseId: expenseId,
        updatedAt: 1000,
      );
      await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 300,
        reason: 'exp_$expenseId',
        updatedAt: 2000,
      );

      final rows = await _reportRows(db, fromDay: _fromDay, toDay: _toDay);
      await _runDedupe(db, rows);

      final loser = await _loadWithdrawal(db, loserId);
      final outboxRows = await (db.select(
        db.outbox,
      )..where((t) => t.localUuid.equals(loser!.localUuid))).get();
      expect(outboxRows, isNotEmpty);
      final syncRow = outboxRows.firstWhere((r) => r.op == 'update');
      expect(syncRow.entity, 'salary_withdrawals');
      final payload = jsonDecode(syncRow.payload) as Map<String, dynamic>;
      expect(payload['deletedAt'], isNotNull); // الحذف يُرفع للخادم
    });
  });

  group('dedupeMirrorDuplicates — المرايا اليتيمة', () {
    test('يتيمة برابط مكسور تطابق مصروفاً واحداً مُرسّى → تُحذف', () async {
      final empId = await _insertEmployee(db);
      final expenseId = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 200,
      );
      // السحوبة المُرسية للمصروف (حية وتحلّ إليه)
      final anchorId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 200,
        expenseId: expenseId,
        updatedAt: 2000,
      );
      // يتيمة: علامة exp_ إلى هدف غير موجود + نفس الموظف/اليوم/النوع
      final orphanId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 999, // مبلغ مختلف عمداً — النوع/اليوم/الموظف وحدها هي المفتاح
        reason: 'exp_987654',
        updatedAt: 1000,
      );

      final rows = await _reportRows(db, fromDay: _fromDay, toDay: _toDay);
      expect(rows.length, 2);
      final result = await _runDedupe(db, rows);

      expect(result.orphansDeleted, 1);
      expect(result.mergedAway, 0);
      expect(result.kept.single.id, anchorId);
      final orphan = await _loadWithdrawal(db, orphanId);
      expect(orphan!.deletedAt, isNotNull);
      final anchor = await _loadWithdrawal(db, anchorId);
      expect(anchor!.deletedAt, isNull);
    });

    test(
      'المصروف غير المُرسّى → اليتيمة تبقى (قد تكون مرآته الوحيدة)',
      () async {
        final empId = await _insertEmployee(db);
        await _insertSalaryExpense(db, employeeId: empId, amount: 200);
        // لا سحوبة مرسية للمصروف — اليتيمة وحدها تعبّر عن الحدث المالي
        final orphanId = await _insertWithdrawal(
          db,
          employeeId: empId,
          amount: 200,
          reason: 'exp_987654',
        );

        final rows = await _reportRows(db, fromDay: _fromDay, toDay: _toDay);
        final result = await _runDedupe(db, rows);

        expect(result.orphansDeleted, 0);
        expect(result.kept.single.id, orphanId);
        final orphan = await _loadWithdrawal(db, orphanId);
        expect(orphan!.deletedAt, isNull);
      },
    );

    test('مرشحان لنفس الموظف/اليوم/النوع = غموض → اليتيمة تبقى', () async {
      final empId = await _insertEmployee(db);
      final expenseA = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 200,
      );
      final expenseB = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 250,
      );
      // مصروف مرسٍ واحد فقط (A) لكن مرشحان للمطابقة → غموض
      await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 200,
        expenseId: expenseA,
        updatedAt: 2000,
      );
      final orphanId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 999,
        reason: 'exp_987654',
      );
      expect(expenseB, greaterThan(0));

      final rows = await _reportRows(db, fromDay: _fromDay, toDay: _toDay);
      final result = await _runDedupe(db, rows);

      expect(result.orphansDeleted, 0);
      final orphan = await _loadWithdrawal(db, orphanId);
      expect(orphan!.deletedAt, isNull);
    });

    test('يوم مختلف → لا مرشح → اليتيمة تبقى', () async {
      final empId = await _insertEmployee(db);
      final expenseId = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 200,
      );
      await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 200,
        expenseId: expenseId,
        updatedAt: 2000,
      );
      final orphanId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 999,
        reason: 'exp_987654',
        hotelDayKey: '2026-09-21', // يوم آخر خارج المطابقة
        withdrawDate: '2026-09-21 10:00',
      );

      final rows = await _reportRows(db, fromDay: _fromDay, toDay: _toDay);
      final result = await _runDedupe(db, rows);

      expect(result.orphansDeleted, 0);
      final orphan = await _loadWithdrawal(db, orphanId);
      expect(orphan!.deletedAt, isNull);
    });
  });

  group('dedupeMirrorDuplicates — الحماية المالية', () {
    test('سحوبة قديمة بلا أي علامة ربط لا تُلمس أبداً', () async {
      final empId = await _insertEmployee(db);
      final expenseId = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 200,
      );
      await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 200,
        expenseId: expenseId,
        updatedAt: 2000,
      );
      // legacy: بلا expense_id وبلا exp_ — ملكية تنظيفها عند التعديل فقط
      final legacyId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 200,
        reason: null,
      );

      final rows = await _reportRows(db, fromDay: _fromDay, toDay: _toDay);
      final result = await _runDedupe(db, rows);

      expect(result.changed, isFalse);
      final legacy = await _loadWithdrawal(db, legacyId);
      expect(legacy!.deletedAt, isNull);
    });

    test('السحوبة المباشرة كيان مستقل — لا تُحذف', () async {
      final empId = await _insertEmployee(db);
      final expenseId = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 200,
      );
      await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 200,
        expenseId: expenseId,
        updatedAt: 2000,
      );
      final directId = await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 150,
        reason: 'direct_withdrawal_${IdGen.uuid()}',
      );

      final rows = await _reportRows(db, fromDay: _fromDay, toDay: _toDay);
      final result = await _runDedupe(db, rows);

      expect(result.changed, isFalse);
      final direct = await _loadWithdrawal(db, directId);
      expect(direct!.deletedAt, isNull);
    });

    test('التنظيف idempotent — التشغيل الثاني لا يغيّر شيئاً', () async {
      final empId = await _insertEmployee(db);
      final expenseId = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 300,
      );
      await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 300,
        expenseId: expenseId,
        updatedAt: 1000,
      );
      await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 300,
        reason: 'exp_$expenseId',
        updatedAt: 2000,
      );

      final first = await _runDedupe(
        db,
        await _reportRows(db, fromDay: _fromDay, toDay: _toDay),
      );
      expect(first.changed, isTrue);

      final second = await _runDedupe(
        db,
        await _reportRows(db, fromDay: _fromDay, toDay: _toDay),
      );
      expect(second.changed, isFalse);
      expect(second.kept.length, 1);
    });

    test('عدسة التقرير: صفّان لحدث واحد → صف واحد بعد التنظيف', () async {
      final empId = await _insertEmployee(db);
      final expenseId = await _insertSalaryExpense(
        db,
        employeeId: empId,
        amount: 500,
      );
      // تكرار مرآة كامل عبر مسارين الرابطين
      await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 500,
        reason: 'exp_$expenseId',
        updatedAt: 1000,
      );
      await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 500,
        expenseId: expenseId,
        reason: 'exp_$expenseId',
        updatedAt: 2000,
      );
      // يتيمة مكسورة مطابقة للمصروف المُرسّى
      await _insertWithdrawal(
        db,
        employeeId: empId,
        amount: 123,
        reason: 'exp_987654',
        updatedAt: 500,
      );

      final before = await _reportRows(db, fromDay: _fromDay, toDay: _toDay);
      expect(before.length, 3);
      final beforeTotal = before.fold<double>(0, (s, r) => s + r.amount);
      expect(beforeTotal, 1123); // المجموع مضاعف خطأً

      final result = await _runDedupe(
        db,
        await _reportRows(db, fromDay: _fromDay, toDay: _toDay),
      );
      expect(result.mergedAway, 1);
      expect(result.orphansDeleted, 1);

      final after = await _reportRows(db, fromDay: _fromDay, toDay: _toDay);
      expect(after.length, 1);
      expect(after.single.amount, 500);
    });
  });
}
