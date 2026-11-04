// اختبارات PR-1/PR-2 من وثيقة الربط والمزامنة الموحدة:
//  · مخطط الربط UUID-first (expense_kind + pending_links + الفهارس)
//  · تعبئة آمنة بلا outbox/version/lastModified
//  · LocalLinkResolver: UUID ⇒ رقم محلي بلا fallback إلى أرقام Appwrite
//  · السجل غير المحلول يبقى محفوظاً وقابلاً لإعادة المحاولة ولا يُحذف

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/local_link_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late LocalLinkResolver resolver;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    resolver = LocalLinkResolver(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertEmployee(String uuid, {String name = 'موظف'}) {
    return db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            name: name,
            basicSalary: 50000,
            status: 'active',
            localUuid: uuid,
            createdAt: 1,
            updatedAt: 1,
            lastModified: 1,
          ),
        );
  }

  Future<int> insertExpense({
    required String uuid,
    String expenseType = 'سحب راتب',
    int? relatedId,
    String? employeeUuid,
    int? deletedAt,
  }) {
    return db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            localUuid: uuid,
            expenseType: expenseType,
            amount: 1000,
            date: '2026-10-01',
            description: 'اختبار',
            relatedId: Value(relatedId),
            employeeUuid: Value(employeeUuid),
            deletedAt: Value(deletedAt),
            createdAt: 1,
            updatedAt: 1,
            lastModified: 1,
          ),
        );
  }

  Future<int> insertWithdrawal({
    required String uuid,
    required int employeeId,
    String? employeeUuid,
    int? expenseId,
    String? reason,
  }) {
    return db
        .into(db.salaryWithdrawals)
        .insert(
          SalaryWithdrawalsCompanion.insert(
            localUuid: uuid,
            employeeId: employeeId,
            amount: 1000,
            withdrawDate: '2026-10-01',
            employeeUuid: Value(employeeUuid),
            expenseId: Value(expenseId),
            reason: Value(reason),
            createdAt: 1,
            updatedAt: 1,
            lastModified: 1,
          ),
        );
  }

  group('مخطط الربط (migration 75)', () {
    test('expenses.expense_kind موجود', () async {
      expect(await resolver.columnExists('expenses', 'expense_kind'), isTrue);
    });

    test('جدول pending_links موجود بأعمدته الأساسية', () async {
      final cols = await db
          .customSelect("SELECT name FROM pragma_table_info('pending_links')")
          .get();
      final names = cols.map((r) => '${r.data['name']}').toSet();
      expect(
        names,
        containsAll(<String>{
          'entity',
          'local_uuid',
          'missing_kind',
          'missing_uuid',
          'attempts',
          'last_error',
          'created_at',
          'updated_at',
        }),
      );
    });

    test(
      'القيد الفريد للمرآة موجود أصلاً بالاسم الفعلي (لا قيد ثانٍ)',
      () async {
        // §4.1 يطلب قيداً فريداً للمرآة النشطة — وهو موجود في المخطط الفعلي
        // باسم `ux_salary_withdrawals_expense_uuid_active` (تعريف
        // @TableIndex.sql + migration 69/70). إضافة قيد ثانٍ بشرط مختلف تكسر
        // البيانات المشروعة (السلسلة الفارغة ليست رابطاً) — أثبته CI.
        final names = (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'index' "
                  'AND tbl_name = \'salary_withdrawals\'',
                )
                .get())
            .map((r) => '${r.data['name']}')
            .toSet();

        expect(names, contains('ux_salary_withdrawals_expense_uuid_active'));
        expect(
          names.contains('ux_sw_expense_uuid_active'),
          isFalse,
          reason: 'لا نضيف قيداً مكرراً بشرط مختلف',
        );
      },
    );

    test('المرآة الثانية النشطة لنفس expense_uuid يمنعها القيد', () async {
      final empId = await insertEmployee('emp-dup');
      await insertWithdrawal(
        uuid: 'w-dup-1',
        employeeId: empId,
        employeeUuid: 'emp-dup',
      );
      await db.customStatement(
        "UPDATE salary_withdrawals SET expense_uuid = 'exp-shared' "
        "WHERE local_uuid = 'w-dup-1'",
      );
      await insertWithdrawal(
        uuid: 'w-dup-2',
        employeeId: empId,
        employeeUuid: 'emp-dup',
      );

      await expectLater(
        db.customStatement(
          "UPDATE salary_withdrawals SET expense_uuid = 'exp-shared' "
          "WHERE local_uuid = 'w-dup-2'",
        ),
        throwsA(anything),
        reason: 'قيد ux_salary_withdrawals_expense_uuid_active يحمي 1:1',
      );
      final counts = await db.uuidLinkHealthCounts();
      expect(counts['duplicateActiveMirrors'], 0);
    });

    test('السلسلة الفارغة ليست رابطاً: لا يُعدّها التقرير تكراراً', () async {
      final empId = await insertEmployee('emp-empty');
      await insertWithdrawal(
        uuid: 'w-empty-1',
        employeeId: empId,
        employeeUuid: 'emp-empty',
      );
      await insertWithdrawal(
        uuid: 'w-empty-2',
        employeeId: empId,
        employeeUuid: 'emp-empty',
      );
      // '' ليست expense_uuid صالحاً ⇒ قيد الفهرس الجزئي لا ينطبق عليها
      await db.customStatement(
        "UPDATE salary_withdrawals SET expense_uuid = '' "
        "WHERE local_uuid IN ('w-empty-1','w-empty-2')",
      );

      final counts = await db.uuidLinkHealthCounts();
      expect(counts['duplicateActiveMirrors'], 0);
      expect(counts['orphanMirrors'], 0);
    });

    test('تعبئة expense_kind من المصنّف النصي مرة واحدة', () async {
      await insertExpense(uuid: 'e-withdraw', expenseType: 'سحب راتب');
      await insertExpense(uuid: 'e-deduct', expenseType: 'خصم من الراتب');
      await insertExpense(uuid: 'e-advance', expenseType: 'سلفة');
      await insertExpense(uuid: 'e-payroll', expenseType: 'رواتب');
      await insertExpense(uuid: 'e-general', expenseType: 'كهرباء');

      await db.backfillUuidLinksForTesting();

      Future<String?> kindOf(String uuid) async {
        final rows = await db
            .customSelect(
              'SELECT expense_kind FROM expenses WHERE local_uuid = ?',
              variables: [Variable.withString(uuid)],
            )
            .get();
        return rows.isEmpty ? null : rows.first.data['expense_kind'] as String?;
      }

      expect(await kindOf('e-withdraw'), 'salary_withdrawal');
      expect(await kindOf('e-deduct'), 'salary_deduction');
      expect(await kindOf('e-advance'), 'advance');
      expect(await kindOf('e-payroll'), 'payroll');
      expect(await kindOf('e-general'), 'general');
    });

    test('تعبئة expense_uuid من expense_id المحلي فقط لنفس الموظف', () async {
      final empA = await insertEmployee('emp-a', name: 'أ');
      final empB = await insertEmployee('emp-b', name: 'ب');
      final expA = await insertExpense(
        uuid: 'exp-a',
        relatedId: empA,
        employeeUuid: 'emp-a',
      );
      final expB = await insertExpense(
        uuid: 'exp-b',
        relatedId: empB,
        employeeUuid: 'emp-b',
      );

      await insertWithdrawal(
        uuid: 'w-good',
        employeeId: empA,
        employeeUuid: 'emp-a',
        expenseId: expA,
      );
      // مرآة تشير إلى مصروف موظف آخر ⇒ لا يجوز ربطها (حارس §4.2)
      await insertWithdrawal(
        uuid: 'w-cross',
        employeeId: empB,
        employeeUuid: 'emp-b',
        expenseId: expA,
      );

      await db.backfillUuidLinksForTesting();

      Future<String?> expenseUuidOf(String uuid) async {
        final rows = await db
            .customSelect(
              'SELECT expense_uuid FROM salary_withdrawals '
              'WHERE local_uuid = ?',
              variables: [Variable.withString(uuid)],
            )
            .get();
        if (rows.isEmpty) return null;
        return rows.first.data['expense_uuid'] as String?;
      }

      expect(await expenseUuidOf('w-good'), 'exp-a');
      expect(
        await expenseUuidOf('w-cross'),
        isNull,
        reason: 'الربط الرقمي يشير لمصروف موظف آخر — يجب ألا يُنسب',
      );
      expect(expB, isNot(equals(expA)));
    });

    test('التعبئة لا ترفع version ولا lastModified ولا تمس outbox', () async {
      final empId = await insertEmployee('emp-v');
      final expId = await insertExpense(
        uuid: 'exp-v',
        relatedId: empId,
        employeeUuid: 'emp-v',
      );
      await insertWithdrawal(
        uuid: 'w-v',
        employeeId: empId,
        employeeUuid: 'emp-v',
        expenseId: expId,
      );

      Future<Map<String, Object?>> snapshot(String table, String uuid) async {
        final rows = await db
            .customSelect(
              'SELECT version, last_modified, expense_uuid FROM $table '
              'WHERE local_uuid = ?',
              variables: [Variable.withString(uuid)],
            )
            .get();
        return rows.first.data;
      }

      final outboxBefore = await db
          .customSelect('SELECT COUNT(*) AS c FROM outbox')
          .get();
      final before = await snapshot('salary_withdrawals', 'w-v');

      await db.backfillUuidLinksForTesting();

      final after = await snapshot('salary_withdrawals', 'w-v');
      final outboxAfter = await db
          .customSelect('SELECT COUNT(*) AS c FROM outbox')
          .get();

      expect(after['version'], before['version']);
      expect(after['last_modified'], before['last_modified']);
      expect(after['expense_uuid'], 'exp-v');
      expect(outboxAfter.first.data['c'], outboxBefore.first.data['c']);
    });
  });

  group('LocalLinkResolver — حل الهوية', () {
    test('employeeUuid ⇒ employees.id بلا اعتماد على أرقام بعيدة', () async {
      final id = await insertEmployee('uuid-employee-1');
      expect(await resolver.employeeIdForUuid('uuid-employee-1'), id);
      expect(await resolver.employeeIdForUuid('uuid-unknown'), isNull);
      expect(await resolver.employeeIdForUuid(null), isNull);
      expect(await resolver.employeeIdForUuid(''), isNull);
    });

    test('الموظف المحذوف منطقياً لا يُحل', () async {
      final id = await insertEmployee('uuid-deleted-employee');
      await (db.update(db.employees)..where((e) => e.id.equals(id))).write(
        const EmployeesCompanion(deletedAt: Value(99)),
      );
      expect(await resolver.employeeIdForUuid('uuid-deleted-employee'), isNull);
    });

    test('expenseUuid ⇒ expenses.id', () async {
      final id = await insertExpense(uuid: 'uuid-expense-1');
      expect(await resolver.expenseIdForUuid('uuid-expense-1'), id);
      expect(await resolver.expenseIdForUuid('uuid-missing'), isNull);
    });

    test('حل دفعة UUIDs في استعلام واحد', () async {
      final a = await insertEmployee('emp-1');
      final b = await insertEmployee('emp-2');
      final map = await resolver.employeeIdsForUuids([
        'emp-1',
        'emp-2',
        'emp-missing',
      ]);
      expect(map['emp-1'], a);
      expect(map['emp-2'], b);
      expect(map.containsKey('emp-missing'), isFalse);
    });
  });

  group('LocalLinkResolver — pending_links', () {
    test('السجل غير المحلول يُحفظ ولا يُنسب لأي موظف', () async {
      await resolver.recordPendingLink(
        entity: 'salary_withdrawal',
        localUuid: 'w-orphan',
        missingKind: 'employee_uuid',
        missingUuid: 'emp-late',
        lastError: 'الأب لم يصل',
      );

      expect(await resolver.pendingLinksCount(), 1);
      final rows = await resolver.pendingLinks();
      expect(rows.single.missingUuid, 'emp-late');
      expect(rows.single.entity, 'salary_withdrawal');
    });

    test('التسجيل المكرر لا يُنشئ صفاً ثانياً ويزيد المحاولات', () async {
      for (var i = 0; i < 3; i++) {
        await resolver.recordPendingLink(
          entity: 'salary_withdrawal',
          localUuid: 'w-dup',
          missingKind: 'employee_uuid',
          missingUuid: 'emp-late',
        );
      }
      expect(await resolver.pendingLinksCount(), 1);
      expect((await resolver.pendingLinks()).single.attempts, greaterThan(1));
    });

    test(
      'بعد وصول الأب: يُحل الرابط ويُحدَّث الرقم المحلي ويُحذف الصف',
      () async {
        final empId = await insertEmployee('emp-late');
        await insertWithdrawal(
          uuid: 'w-waiting',
          employeeId: empId,
          employeeUuid: null,
        );
        await resolver.recordPendingLink(
          entity: 'salary_withdrawal',
          localUuid: 'w-waiting',
          missingKind: 'employee_uuid',
          missingUuid: 'emp-late',
        );

        // الأب موجود بالفعل ⇒ تُحل في أول محاولة
        final resolved = await resolver.retryPendingLinks();
        expect(resolved, 1);
        expect(await resolver.pendingLinksCount(), 0);

        final rows = await db
            .customSelect(
              'SELECT employee_id FROM salary_withdrawals '
              "WHERE local_uuid = 'w-waiting'",
            )
            .get();
        expect(rows.first.data['employee_id'], empId);
      },
    );

    test('الأب الغائб: الصف يبقى وتزيد المحاولات ولا يُحذف أي سجل', () async {
      final empId = await insertEmployee('emp-present');
      await insertWithdrawal(
        uuid: 'w-still-waiting',
        employeeId: empId,
        employeeUuid: 'emp-present',
      );
      await resolver.recordPendingLink(
        entity: 'salary_withdrawal',
        localUuid: 'w-still-waiting',
        missingKind: 'employee_uuid',
        missingUuid: 'emp-absent',
      );

      final resolved = await resolver.retryPendingLinks();
      expect(resolved, 0);
      expect(await resolver.pendingLinksCount(), 1);

      final row = (await resolver.pendingLinks()).single;
      expect(row.attempts, greaterThan(1));
      expect(row.lastError, isNotNull);

      // السجل نفسه ما زال موجوداً (لا حذف مقابل عدم الحل)
      final rows = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM salary_withdrawals '
            "WHERE local_uuid = 'w-still-waiting'",
          )
          .get();
      expect(rows.first.data['c'], 1);
    });

    test('نوع ربط غير معروف لا يكتب شيئاً بدل التخمين', () async {
      final empId = await insertEmployee('emp-x');
      await insertWithdrawal(
        uuid: 'w-unknown-kind',
        employeeId: empId,
        employeeUuid: 'emp-x',
      );
      await resolver.recordPendingLink(
        entity: 'unknown_entity',
        localUuid: 'w-unknown-kind',
        missingKind: 'employee_uuid',
        missingUuid: 'emp-x',
      );

      expect(await resolver.retryPendingLinks(), 0);
      expect(await resolver.pendingLinksCount(), 1);

      final rows = await db
          .customSelect(
            'SELECT employee_id FROM salary_withdrawals '
            "WHERE local_uuid = 'w-unknown-kind'",
          )
          .get();
      expect(rows.first.data['employee_id'], empId);
    });

    test('ربط المصروف بسحبته عبر expense_uuid', () async {
      final empId = await insertEmployee('emp-mirror');
      final expId = await insertExpense(uuid: 'exp-mirror');
      await insertWithdrawal(
        uuid: 'w-mirror',
        employeeId: empId,
        employeeUuid: 'emp-mirror',
        expenseId: null,
      );
      await resolver.recordPendingLink(
        entity: 'salary_withdrawal',
        localUuid: 'w-mirror',
        missingKind: 'expense_uuid',
        missingUuid: 'exp-mirror',
      );

      expect(await resolver.retryPendingLinks(), 1);

      final rows = await db
          .customSelect(
            'SELECT expense_id FROM salary_withdrawals '
            "WHERE local_uuid = 'w-mirror'",
          )
          .get();
      expect(rows.first.data['expense_id'], expId);
    });
  });

  group('تقرير سلامة الروابط', () {
    test('عدّادات القراءة فقط تُرجع المفاتيح المطلوبة', () async {
      final counts = await db.uuidLinkHealthCounts();
      expect(
        counts.keys,
        containsAll(<String>[
          'withdrawalsMissingEmployeeUuid',
          'withdrawalsMissingExpenseUuid',
          'salaryExpensesMissingEmployeeUuid',
          'orphanMirrors',
          'duplicateActiveMirrors',
          'pendingLinks',
          'unclassifiedExpenses',
        ]),
      );
    });

    test('المرآة اليتيمة تُعدّ ولا تُحذف', () async {
      final empId = await insertEmployee('emp-orphan');
      await insertWithdrawal(
        uuid: 'w-orphan-mirror',
        employeeId: empId,
        employeeUuid: 'emp-orphan',
      );
      await db.customStatement(
        "UPDATE salary_withdrawals SET expense_uuid = 'exp-does-not-exist' "
        "WHERE local_uuid = 'w-orphan-mirror'",
      );

      final counts = await db.uuidLinkHealthCounts();
      expect(counts['orphanMirrors'], 1);

      final rows = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM salary_withdrawals '
            "WHERE local_uuid = 'w-orphan-mirror'",
          )
          .get();
      expect(rows.first.data['c'], 1, reason: 'تقرير تشخيصي لا يحذف');
    });
  });
}
