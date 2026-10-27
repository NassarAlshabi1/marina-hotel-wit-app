// ✅ (migration 68) اختبارات رابط المرآة الدائم سحبة↔مصروف.
//
// تغطي:
// 1. عمودا expense_uuid / withdrawal_uuid يعملان عبر ORM في مخطط جديد.
// 2. حراس الـ backfill الحتمي: نفس الموظف + المبلغ + اليوم ±1 — ورفض
//    الربط العابر للموظف (تصادم معرفات الأجهزة) والربط الخاطئ.
// 3. محولات المزامنة: expenseUuid/withdrawalUuid round-trip.
// 4. حزم الدفع: salaryWithdrawalToRemote/expenseToRemote تختم الحقول.
// 5. قوائم الحقول المسموحة (filterPayloadForCollection) لا تُسقطها.
// 6. مواصفات مدقق المخطط تتضمن الخصائص السحابية الجديدة.
//
// الخلفية: salary_withdrawals.expense_id يحمل معرّف جهاز المصدر المحلي —
// لا يقابل أي صف على الأجهزة الأخرى (حالة «الاورمو محمد» 2026-09-14،
// وتقرير التدقيق: 643/688 زوجاً خاطئاً على السحابة). نفس عائلة
// employee_uuid (PR #601) و cycle_uuid (PR #609).
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/appwrite_config.dart';
import 'package:marina_hotel_mobile/services/appwrite_schema_verifier.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_utils.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/adapters/expenses_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/id_resolver.dart';
import 'package:marina_hotel_mobile/services/adapters/resolve_result.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/adapters/salary_withdrawals_adapter.dart';
import 'package:marina_hotel_mobile/services/sync/payload_mapper.dart';

const _now = 1760000000; // epoch ثابت للاختبار

AppDatabase _db() {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  return db;
}

Future<int> _insertEmployee(
  AppDatabase db, {
  required String localUuid,
  required String name,
}) {
  return db
      .into(db.employees)
      .insert(
        EmployeesCompanion.insert(
          localUuid: localUuid,
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
          name: name,
          basicSalary: 0,
          status: 'active',
        ),
      );
}

Future<int> _insertExpense(
  AppDatabase db, {
  required String localUuid,
  required String expenseType,
  required double amount,
  required String date,
  String? employeeUuid,
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
          employeeUuid: d.Value(employeeUuid),
        ),
      );
}

Future<int> _insertWithdrawal(
  AppDatabase db, {
  required int employeeId,
  required String localUuid,
  required double amount,
  required String withdrawDate,
  int? expenseId,
  String? expenseUuid,
  String? employeeUuid,
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
          amount: amount,
          withdrawDate: withdrawDate,
          expenseId: d.Value(expenseId),
          expenseUuid: d.Value(expenseUuid),
          employeeUuid: d.Value(employeeUuid),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('migration 68: schema & backfill', () {
    test('1. عمودا الرابط الدائم يعملان عبر ORM في مخطط جديد', () async {
      final db = _db();
      addTearDown(db.close);

      final empId = await _insertEmployee(
        db,
        localUuid: 'emp-uuid-1',
        name: 'م',
      );
      final expenseId = await _insertExpense(
        db,
        localUuid: 'exp-uuid-1',
        expenseType: 'سحب راتب',
        amount: 6000,
        date: '2026-10-01',
        employeeUuid: 'emp-uuid-1',
      );
      final swId = await _insertWithdrawal(
        db,
        employeeId: empId,
        localUuid: 'sw-uuid-1',
        amount: 6000,
        withdrawDate: '2026-10-01',
        expenseId: expenseId,
        expenseUuid: 'exp-uuid-1',
      );
      await db.customStatement(
        'UPDATE expenses SET withdrawal_uuid = ? WHERE id = ?',
        ['sw-uuid-1', expenseId],
      );

      final sw = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.id.equals(swId))).getSingle();
      expect(sw.expenseUuid, 'exp-uuid-1');
      final exp = await (db.select(
        db.expenses,
      )..where((t) => t.id.equals(expenseId))).getSingle();
      expect(exp.withdrawalUuid, 'sw-uuid-1');
    });

    test(
      '2. حراس الـ backfill يمنعون الربط العابر للموظف (تصادم أجهزة)',
      () async {
        final db = _db();
        addTearDown(db.close);

        await _insertEmployee(db, localUuid: 'emp-uuid-A', name: 'أ');
        await _insertEmployee(db, localUuid: 'emp-uuid-B', name: 'ب');

        // مصروف موظف أ + مصروف موظف ب بنفس المبلغ واليوم. سحبة موظف ب
        // تحمل expense_id يشير رقمياً إلى مصروف موظف أ — الخلل التاريخي
        // عند تصادم autoincrement بين جهازين.
        await _insertExpense(
          db,
          localUuid: 'exp-uuid-A',
          expenseType: 'سحب راتب',
          amount: 6000,
          date: '2026-10-01',
          employeeUuid: 'emp-uuid-A',
        );
        await _insertExpense(
          db,
          localUuid: 'exp-uuid-B',
          expenseType: 'سحب راتب',
          amount: 6000,
          date: '2026-10-01',
          employeeUuid: 'emp-uuid-B',
        );
        final swId = await _insertWithdrawal(
          db,
          employeeId: 2,
          localUuid: 'sw-uuid-B',
          amount: 6000,
          withdrawDate: '2026-10-01',
          expenseId: 1, // مصروف موظف أ!
        );

        await db.customStatement(_migration68SwBackfillSql);
        await db.customStatement(_migration68ExpBackfillSql);

        // حرس الموظف يمنع الربط الخاطئ: expense_uuid يبقى NULL
        // (لا نؤسس رابطاً عابراً للموظف حتى لو طابق المبلغ واليوم).
        final sw = await (db.select(
          db.salaryWithdrawals,
        )..where((t) => t.id.equals(swId))).getSingle();
        expect(sw.expenseUuid, isNull);
      },
    );

    test(
      '3. الـ backfill يربط المرآة الصحيحة (نفس الموظف/المبلغ/±1 يوم)',
      () async {
        final db = _db();
        addTearDown(db.close);

        final empId = await _insertEmployee(
          db,
          localUuid: 'emp-uuid-A',
          name: 'أ',
        );
        final expenseId = await _insertExpense(
          db,
          localUuid: 'exp-uuid-A',
          expenseType: 'سحب راتب',
          amount: 6000,
          date: '2026-10-01',
          employeeUuid: 'emp-uuid-A',
        );
        final swId = await _insertWithdrawal(
          db,
          employeeId: empId,
          localUuid: 'sw-uuid-A',
          amount: 6000,
          withdrawDate: '2026-10-01', // نفس اليوم بالضبط (دلالة L3)
          expenseId: expenseId,
          employeeUuid: 'emp-uuid-A',
        );

        await db.customStatement(_migration68SwBackfillSql);
        await db.customStatement(_migration68ExpBackfillSql);

        final sw = await (db.select(
          db.salaryWithdrawals,
        )..where((t) => t.id.equals(swId))).getSingle();
        expect(sw.expenseUuid, 'exp-uuid-A');
        final exp = await (db.select(
          db.expenses,
        )..where((t) => t.id.equals(expenseId))).getSingle();
        expect(exp.withdrawalUuid, 'sw-uuid-A');
      },
    );

    test('3-أ. يوم ±1 مختلف لا يُربط (لا تسامح زمني — L3 حرفياً)', () async {
      final db = _db();
      addTearDown(db.close);

      final empId = await _insertEmployee(
        db,
        localUuid: 'emp-uuid-A',
        name: 'أ',
      );
      final expenseId = await _insertExpense(
        db,
        localUuid: 'exp-uuid-A2',
        expenseType: 'سحب راتب',
        amount: 6000,
        date: '2026-10-01',
        employeeUuid: 'emp-uuid-A',
      );
      final swId = await _insertWithdrawal(
        db,
        employeeId: empId,
        localUuid: 'sw-uuid-A2',
        amount: 6000,
        withdrawDate: '2026-10-02', // ±1 يوم فقط — لا يُكتب رابط غير مؤكد
        expenseId: expenseId,
        employeeUuid: 'emp-uuid-A',
      );

      await db.customStatement(_migration68SwBackfillSql);
      await db.customStatement(_migration68ExpBackfillSql);

      final sw = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.id.equals(swId))).getSingle();
      expect(sw.expenseUuid, isNull);
      final exp = await (db.select(
        db.expenses,
      )..where((t) => t.id.equals(expenseId))).getSingle();
      expect(exp.withdrawalUuid, isNull);
    });

    test('3-ب. غير العائلة الراتبية لا يأخذ رابطاً عكسياً', () async {
      final db = _db();
      addTearDown(db.close);

      final empId = await _insertEmployee(
        db,
        localUuid: 'emp-uuid-A',
        name: 'أ',
      );
      // مصروف أغذية عادي — بهوية موظف مؤكدة (السحوبات في الإنتاج تحمل
      // employee_uuid بعد ترحيلات family-61 قبل وصول ترحيل 68)
      final expenseId = await _insertExpense(
        db,
        localUuid: 'exp-uuid-food',
        expenseType: 'أغذية',
        amount: 6000,
        date: '2026-10-01',
        employeeUuid: 'emp-uuid-A',
      );
      await _insertWithdrawal(
        db,
        employeeId: empId,
        localUuid: 'sw-uuid-A',
        amount: 6000,
        withdrawDate: '2026-10-01',
        expenseId: expenseId,
        employeeUuid: 'emp-uuid-A',
      );

      await db.customStatement(_migration68SwBackfillSql);
      await db.customStatement(_migration68ExpBackfillSql);

      final exp = await (db.select(
        db.expenses,
      )..where((t) => t.id.equals(expenseId))).getSingle();
      // السحبة تُربط بالمصروف (نفس الجهاز — الربط صحيح)، لكن المصروف
      // العادي (غير الراتبي) لا يأخذ withdrawal_uuid حفاظاً على دلالة
      // expense_id للمصروفات الأخرى.
      final exp2 = await (db.select(
        db.expenses,
      )..where((t) => t.id.equals(expenseId))).getSingle();
      expect(exp2.withdrawalUuid, isNull);
      // والتأكيد الأول: الرابط الأمامي على السحبة تم
      final sw = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.localUuid.equals('sw-uuid-A'))).getSingle();
      expect(sw.expenseUuid, 'exp-uuid-food');
      expect(exp.id, expenseId); // صحة القراءة
    });

    test(
      '10. الطرفان بلا هوية موظف (NULL) ⇒ لا رابط — حرس صارم بلا IS',
      () async {
        final db = _db();
        addTearDown(db.close);

        final empId = await _insertEmployee(
          db,
          localUuid: 'emp-uuid-orphan',
          name: 'يتيم',
        );
        // زوج مرآة حقيقي (نفس الجهاز — expense_id صحيح) لكن employee_uuid
        // NULL على الطرفين (الهوية لم تُحل بعد) — نفس المبلغ واليوم.
        // الصيغة المتسامحة القديمة (NULL IS NULL = صحيح) كانت ستُربطهما
        // عبر المبلغ واليوم وحدهما = خطر العبور بين الموظفين.
        final expenseId = await _insertExpense(
          db,
          localUuid: 'exp-uuid-orphan',
          expenseType: 'سحب راتب',
          amount: 2000,
          date: '2026-07-06',
          // employeeUuid: null
        );
        final swId = await _insertWithdrawal(
          db,
          employeeId: empId, // صف موجود (FK) لكن uuidه غير مكتوب بعد
          localUuid: 'sw-uuid-orphan',
          amount: 2000,
          withdrawDate: '2026-07-06',
          expenseId: expenseId,
          // employeeUuid: null
        );

        await db.customStatement(_migration68SwBackfillSql);
        await db.customStatement(_migration68ExpBackfillSql);

        final sw = await (db.select(
          db.salaryWithdrawals,
        )..where((t) => t.id.equals(swId))).getSingle();
        final exp = await (db.select(
          db.expenses,
        )..where((t) => t.id.equals(expenseId))).getSingle();
        // المنهجية المحافظة: بلا هوية موظف مؤكدة ⇒ بلا رابط (لا نخمّن).
        // الختم الزمني يعيد كتابة الرابط لاحقاً عند أول تعديل عبر
        // saveFromExpense/createFromExpense بعد أن تُملأ الهوية.
        expect(sw.expenseUuid, isNull);
        expect(exp.withdrawalUuid, isNull);
      },
    );
  });

  group('migration 68: adapters & payloads', () {
    test('4. mapper السحبات يختم expenseUuid والـ adapter يقرؤه', () async {
      final db = _db();
      addTearDown(db.close);
      final sw = SalaryWithdrawal(
        id: 1,
        localUuid: 'sw-uuid-1',
        employeeId: 2,
        employeeUuid: 'emp-uuid-1',
        amount: 6000,
        withdrawDate: '2026-10-01',
        reason: 'exp_5',
        expenseId: 5,
        expenseUuid: 'exp-uuid-5',
        createdAt: _now,
        updatedAt: _now,
        lastModified: _now,
        createdAtEpoch: _now,
        lastModifiedEpoch: _now,
        version: 1,
        origin: 'local',
        vectorClock: '{}',
        deviceId: '',
        syncTimestamp: _now,
      );
      final remote = PayloadMapper().salaryWithdrawalToRemote(sw);
      expect(remote['expenseUuid'], 'exp-uuid-5');

      final adapter = SalaryWithdrawalsAdapter(IdResolver(db));
      final companion = adapter.fromJson(
        {
          'localUuid': 'sw-remote-1',
          'employeeId': 2,
          'amount': 6000,
          'withdrawDate': '2026-10-01',
          'expenseId': 9,
          'expenseUuid': 'exp-uuid-9',
        },
        src: Source.appwrite,
        refs: ResolveResult.empty,
      );
      expect(companion.expenseUuid.present, isTrue);
      expect(companion.expenseUuid.value, 'exp-uuid-9');
    });

    test(
      '5. mapper المصروفات يختم withdrawalUuid والـ adapter يقرؤه',
      () async {
        final db = _db();
        addTearDown(db.close);
        final expense = Expense(
          id: 5,
          localUuid: 'exp-uuid-5',
          expenseType: 'سحب راتب',
          description: 'مرآة',
          amount: 6000,
          date: '2026-10-01',
          isAutoGenerated: true,
          withdrawalUuid: 'sw-uuid-1',
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
          createdAtEpoch: _now,
          lastModifiedEpoch: _now,
          version: 1,
          origin: 'local',
          vectorClock: '{}',
          deviceId: '',
          syncTimestamp: _now,
        );
        final remote = PayloadMapper().expenseToRemote(expense);
        expect(remote['withdrawalUuid'], 'sw-uuid-1');

        final adapter = ExpensesAdapter(IdResolver(db));
        final companion = adapter.fromJson(
          {
            'localUuid': 'exp-remote-1',
            'expenseType': 'سحب راتب',
            'description': 'مرآة',
            'amount': 6000.0,
            'date': '2026-10-01',
            'withdrawalUuid': 'sw-remote-1',
          },
          src: Source.appwrite,
          refs: ResolveResult.empty,
        );
        expect(companion.withdrawalUuid.present, isTrue);
        expect(companion.withdrawalUuid.value, 'sw-remote-1');
      },
    );

    test('6. القوائم المسموحة لا تُسقط الحقول الجديدة', () {
      final expensesFiltered = AppwriteSyncUtils.filterPayloadForCollection(
        AppwriteConfig.expensesCollectionId,
        {'withdrawalUuid': 'sw-uuid-1', 'bogus': 1},
      );
      expect(expensesFiltered['withdrawalUuid'], 'sw-uuid-1');
      expect(expensesFiltered.containsKey('bogus'), isFalse);

      final swFiltered = AppwriteSyncUtils.filterPayloadForCollection(
        AppwriteConfig.salaryWithdrawalsCollectionId,
        {'expenseUuid': 'exp-uuid-5', 'bogus': 1},
      );
      expect(swFiltered['expenseUuid'], 'exp-uuid-5');
      expect(swFiltered.containsKey('bogus'), isFalse);
    });

    test('7. مواصفات مدقق المخطط تضم الخصائص السحابية الجديدة', () {
      final expensesSpec =
          AppwriteSchemaVerifier.requiredCollections['expenses']!;
      final expensesAttrs = (expensesSpec['attributes']! as List)
          .cast<Map>()
          .map((a) => a['key'])
          .toList();
      expect(expensesAttrs, contains('withdrawalUuid'));

      final swSpec =
          AppwriteSchemaVerifier.requiredCollections['salary_withdrawals']!;
      final swAttrs = (swSpec['attributes']! as List)
          .cast<Map>()
          .map((a) => a['key'])
          .toList();
      expect(swAttrs, contains('expenseUuid'));
    });
  });
}

// ── مصدر الحقيقة: نفس عبارات SQL المستخدمة في onUpgrade (from < 68) ──
const String _migration68SwBackfillSql = '''
UPDATE salary_withdrawals SET expense_uuid = (
  SELECT e.local_uuid FROM expenses e
  WHERE e.id = salary_withdrawals.expense_id
    AND e.deleted_at IS NULL
    AND e.employee_uuid IS NOT NULL
    AND salary_withdrawals.employee_uuid IS NOT NULL
    AND e.employee_uuid = salary_withdrawals.employee_uuid
    AND ABS(e.amount - salary_withdrawals.amount) < 0.005
    AND (
      (e.hotel_day_key IS NOT NULL AND e.hotel_day_key != ''
        AND e.hotel_day_key = salary_withdrawals.hotel_day_key)
      OR (e.date IS NOT NULL AND salary_withdrawals.withdraw_date IS NOT NULL
        AND julianday(e.date) IS NOT NULL
        AND e.date = salary_withdrawals.withdraw_date)
    )
    AND (SELECT COUNT(*) FROM expenses e3
      WHERE e3.id = salary_withdrawals.expense_id
        AND e3.deleted_at IS NULL
        AND e3.employee_uuid IS NOT NULL
        AND salary_withdrawals.employee_uuid IS NOT NULL
        AND e3.employee_uuid = salary_withdrawals.employee_uuid
        AND ABS(e3.amount - salary_withdrawals.amount) < 0.005
        AND (
          (e3.hotel_day_key IS NOT NULL AND e3.hotel_day_key != ''
            AND e3.hotel_day_key = salary_withdrawals.hotel_day_key)
          OR (e3.date IS NOT NULL AND salary_withdrawals.withdraw_date IS NOT NULL
            AND julianday(e3.date) IS NOT NULL
            AND e3.date = salary_withdrawals.withdraw_date)
        )
    ) = 1
) WHERE expense_uuid IS NULL AND expense_id IS NOT NULL
''';

const String _migration68ExpBackfillSql = '''
UPDATE expenses SET withdrawal_uuid = (
  SELECT w.local_uuid FROM salary_withdrawals w
  WHERE w.expense_id = expenses.id
    AND w.deleted_at IS NULL
    AND w.employee_uuid IS NOT NULL
    AND expenses.employee_uuid IS NOT NULL
    AND w.employee_uuid = expenses.employee_uuid
    AND ABS(w.amount - expenses.amount) < 0.005
    AND (
      (w.hotel_day_key IS NOT NULL AND w.hotel_day_key != ''
        AND w.hotel_day_key = expenses.hotel_day_key)
      OR (w.withdraw_date IS NOT NULL AND expenses.date IS NOT NULL
        AND julianday(w.withdraw_date) IS NOT NULL
        AND w.withdraw_date = expenses.date)
    )
    AND (SELECT COUNT(*) FROM salary_withdrawals w3
      WHERE w3.expense_id = expenses.id
        AND w3.deleted_at IS NULL
        AND w3.employee_uuid IS NOT NULL
        AND expenses.employee_uuid IS NOT NULL
        AND w3.employee_uuid = expenses.employee_uuid
        AND ABS(w3.amount - expenses.amount) < 0.005
        AND (
          (w3.hotel_day_key IS NOT NULL AND w3.hotel_day_key != ''
            AND w3.hotel_day_key = expenses.hotel_day_key)
          OR (w3.withdraw_date IS NOT NULL AND expenses.date IS NOT NULL
            AND julianday(w3.withdraw_date) IS NOT NULL
            AND w3.withdraw_date = expenses.date)
        )
    ) = 1
) WHERE withdrawal_uuid IS NULL
 AND TRIM(expense_type) IN
 ('سحب راتب','خصم راتب','سحب من الراتب','خصم من الراتب','سلفة','رواتب')
''';
