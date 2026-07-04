// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/database_fixer.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/salary_fix_helper.dart';

/// ✅ اختبارات وظيفية للإصلاح المرة واحدة لمصروفات الرواتب اليتيمة.
///
/// تغطي السيناريوهات:
/// 1. مصروف راتب يتيم (UUID فارغ + relatedId غير صالح) مع سحب مرتبط
///    → يجب إعادة ربطه عبر salary_withdrawals
/// 2. مصروف راتب يتيم مع employeeUuid موجود
///    → يجب إعادة ربطه عبر UUID
/// 3. مصروف راتب يتيم بدون أي سحب مرتبط
///    → يجب تركه دون تصفير relatedId
/// 4. مصروف غير راتب يتيم → يجب تصفيره (سلوك 'employee'/'booking' القديم)
/// 5. SharedPreferences flag يمنع التكرار
/// 6. التأجيل عندما لا يوجد موظفون
/// 7. تحديث lastModified + updatedAt + outbox merge بعد الإصلاح
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ExpensesRepository expensesRepo;
  late SalaryWithdrawalsRepository salaryRepo;
  late DatabaseFixer fixer;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expensesRepo = ExpensesRepository(db);
    salaryRepo = SalaryWithdrawalsRepository(db);
    fixer = DatabaseFixer(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // مساعدات الاختبار
  // ═══════════════════════════════════════════════════════════════════════

  /// إنشاء موظف اختبار وإرجاع id.
  Future<int> createEmployee({
    String name = 'أحمد محمد',
    String localUuid = 'emp-uuid-001',
  }) async {
    final id = await db.into(db.employees).insert(
          EmployeesCompanion(
            name: d.Value(name),
            basicSalary: const d.Value(50000),
            position: const d.Value('موظف'),
            status: const d.Value('active'),
            localUuid: d.Value(localUuid),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
            createdAtEpoch: const d.Value(1000),
            lastModifiedEpoch: const d.Value(1000),
            version: const d.Value(1),
            origin: const d.Value('local'),
            vectorClock: const d.Value('{}'),
          ),
        );
    return id;
  }

  /// إنشاء مصروف راتب يتيم مباشرة (يتجاوز repo لتمثيل البيانات القديمة).
  Future<int> createOrphanSalaryExpense({
    required String expenseType,
    int? relatedId,
    String? employeeUuid,
    String localUuid = 'exp-uuid-orphan',
  }) async {
    final id = await db.into(db.expenses).insert(
          ExpensesCompanion(
            expenseType: d.Value(expenseType),
            relatedId: relatedId == null ? const d.Value.absent() : d.Value(relatedId),
            description: const d.Value('سحب راتب قديم'),
            amount: const d.Value(10000),
            date: const d.Value('2026-06-01'),
            hotelDayKey: const d.Value('2026-06-01'),
            employeeUuid: employeeUuid == null
                ? const d.Value.absent()
                : d.Value(employeeUuid),
            localUuid: d.Value(localUuid),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
            createdAtEpoch: const d.Value(1000),
            lastModifiedEpoch: const d.Value(1000),
            version: const d.Value(1),
            origin: const d.Value('local'),
            vectorClock: const d.Value('{}'),
          ),
        );
    return id;
  }

  /// إنشاء سحب راتب مرتبط بمصروف.
  Future<int> createSalaryWithdrawal({
    required int expenseId,
    required int employeeId,
  }) async {
    final id = await db.into(db.salaryWithdrawals).insert(
          SalaryWithdrawalsCompanion(
            employeeId: d.Value(employeeId),
            amount: const d.Value(10000),
            withdrawDate: const d.Value('2026-06-01'),
            reason: d.Value('exp_$expenseId'),
            hotelDayKey: const d.Value('2026-06-01'),
            localUuid: const d.Value('sw-uuid-001'),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
            createdAtEpoch: const d.Value(1000),
            lastModifiedEpoch: const d.Value(1000),
            version: const d.Value(1),
            origin: const d.Value('local'),
            vectorClock: const d.Value('{}'),
          ),
        );
    // كتابة expense_id في العمود الخام (مثل ما يفعل repository)
    await db.customStatement(
      'UPDATE salary_withdrawals SET expense_id = ? WHERE id = ?',
      [expenseId, id],
    );
    return id;
  }

  /// جلب مصروف بالـ id.
  Future<Expense?> getExpense(int id) async {
    return (db.select(db.expenses)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// جلب عدد عناصر outbox لمصروف معين.
  Future<int> outboxCountForExpense(String localUuid) async {
    final result = await db.customSelect(
      'SELECT COUNT(*) as count FROM outbox WHERE local_uuid = ?',
      variables: [d.Variable.withString(localUuid)],
      readsFrom: {db.outbox},
    ).getSingle();
    return result.read<int>('count');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 1. السيناريو الرئيسي: إعادة ربط عبر salary_withdrawals
  // ═══════════════════════════════════════════════════════════════════════

  group('SalaryFixHelper — إعادة الربط عبر salary_withdrawals', () {
    test('يُصلح مصروف راتب يتيم له سحب مرتبط', () async {
      // ترتيب: موظف + مصروف راتب يتيم + سحب مرتبط
      final empId = await createEmployee();
      final expenseId = await createOrphanSalaryExpense(
        expenseType: 'سحب من الراتب',
        relatedId: 999, // معرّف غير صالح (موظف غير موجود)
        employeeUuid: null, // UUID فارغ (بيانات قديمة)
      );
      await createSalaryWithdrawal(
        expenseId: expenseId,
        employeeId: empId,
      );

      // فعل: استدعاء الإصلاح مباشرة
      final helper = SalaryFixHelper(db);
      final fixedCount = await helper.fixOrphanSalaryExpensesForTest();

      // تحقق: تم إصلاح مصروف واحد
      expect(fixedCount, 1, reason: 'يجب إصلاح مصروف واحد');

      final fixed = await getExpense(expenseId);
      expect(fixed, isNotNull);
      expect(fixed!.relatedId, empId, reason: 'relatedId يجب أن يشير للموظف الصحيح');
      expect(fixed.employeeUuid, 'emp-uuid-001', reason: 'employeeUuid يجب أن يُملأ');
      expect(fixed.lastModified, greaterThan(1000), reason: 'lastModified يجب أن يُحدّث');
      expect(fixed.updatedAt, greaterThan(1000), reason: 'updatedAt يجب أن يُحدّث');
      expect(fixed.version, 2, reason: 'version يجب أن يُزاد');
    });

    test('يُصلح مصروف راتب يتيم له سحب مرتبط عبر reason (pre-migration 40)', () async {
      // ترتيب: موظف + مصروف + سحب بـ reason فقط (بدون expense_id)
      final empId = await createEmployee();
      final expenseId = await createOrphanSalaryExpense(
        expenseType: 'خصم من الراتب',
        relatedId: null,
        employeeUuid: null,
      );
      // إنشاء سحب بـ reason فقط (محاكاة pre-migration 40)
      final swId = await db.into(db.salaryWithdrawals).insert(
            SalaryWithdrawalsCompanion(
              employeeId: d.Value(empId),
              amount: const d.Value(5000),
              withdrawDate: const d.Value('2026-06-01'),
              reason: d.Value('exp_$expenseId'),
              localUuid: const d.Value('sw-reason-001'),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
              createdAtEpoch: const d.Value(1000),
              lastModifiedEpoch: const d.Value(1000),
              version: const d.Value(1),
              origin: const d.Value('local'),
              vectorClock: const d.Value('{}'),
            ),
          );
      // ملاحظة: لا نكتب expense_id (محاكاة DB قديمة)

      final helper = SalaryFixHelper(db);
      final fixedCount = await helper.fixOrphanSalaryExpensesForTest();

      expect(fixedCount, 1);
      final fixed = await getExpense(expenseId);
      expect(fixed!.relatedId, empId);
      expect(fixed.employeeUuid, 'emp-uuid-001');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2. إعادة الربط عبر employeeUuid
  // ═══════════════════════════════════════════════════════════════════════

  group('SalaryFixHelper — إعادة الربط عبر employeeUuid', () {
    test('يُصلح مصروف راتب يتيم له employeeUuid صالح', () async {
      final empId = await createEmployee(localUuid: 'emp-known-uuid');
      final expenseId = await createOrphanSalaryExpense(
        expenseType: 'سحب راتب',
        relatedId: 999, // غير صالح
        employeeUuid: 'emp-known-uuid', // UUID صالح موجود
      );

      final helper = SalaryFixHelper(db);
      final fixedCount = await helper.fixOrphanSalaryExpensesForTest();

      expect(fixedCount, 1);
      final fixed = await getExpense(expenseId);
      expect(fixed!.relatedId, empId);
      expect(fixed.employeeUuid, 'emp-known-uuid');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 3. السيناريو الآمن: لا يُصفّر عند تعذّر الحل
  // ═══════════════════════════════════════════════════════════════════════

  group('SalaryFixHelper — الأمان (لا تصفير)', () {
    test('يترك مصروف راتب يتيم دون سحب مرتبط دون تصفير', () async {
      await createEmployee();
      final expenseId = await createOrphanSalaryExpense(
        expenseType: 'رواتب',
        relatedId: 999, // غير صالح
        employeeUuid: null, // لا UUID
      );
      // لا سحب مرتبط

      final helper = SalaryFixHelper(db);
      final fixedCount = await helper.fixOrphanSalaryExpensesForTest();

      expect(fixedCount, 0, reason: 'لا يجب إصلاح شيء بدون سحب مرتبط');
      final unchanged = await getExpense(expenseId);
      expect(unchanged!.relatedId, 999, reason: 'relatedId يجب أن يبقى كما هو (لا تصفير)');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 4. outbox merge (للرفع التلقائي)
  // ═══════════════════════════════════════════════════════════════════════

  group('SalaryFixHelper — outbox merge للرفع', () {
    test('يُضيف الإصلاح للـ outbox للرفع للسحاب', () async {
      final empId = await createEmployee(localUuid: 'emp-outbox-test');
      final expenseId = await createOrphanSalaryExpense(
        expenseType: 'سحب من الراتب',
        relatedId: 999,
        employeeUuid: null,
        // localUuid فريد لهذا الاختبار
      );
      // تحديث localUuid للمصروف ليكون فريداً
      await db.customUpdate(
        'UPDATE expenses SET local_uuid = ? WHERE id = ?',
        variables: [
          d.Variable.withString('exp-outbox-test-001'),
          d.Variable.withInt(expenseId),
        ],
        updates: {db.expenses},
      );
      await createSalaryWithdrawal(expenseId: expenseId, employeeId: empId);

      final helper = SalaryFixHelper(db);
      await helper.fixOrphanSalaryExpensesForTest();

      // تحقق: outbox يحتوي على عملية update للمصروف
      final count = await outboxCountForExpense('exp-outbox-test-001');
      expect(count, greaterThan(0), reason: 'يجب إضافة عملية للـ outbox للرفع');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 5. SharedPreferences flag (مرة واحدة)
  // ═══════════════════════════════════════════════════════════════════════

  group('SalaryFixHelper — التشغيل مرة واحدة', () {
    test('runOnceAfterFirstPull لا يتكرر بعد ضبط flag', () async {
      await createEmployee();
      final expenseId = await createOrphanSalaryExpense(
        expenseType: 'سحب من الراتب',
        relatedId: 999,
        employeeUuid: null,
      );
      await createSalaryWithdrawal(
        expenseId: expenseId,
        employeeId: 1, // empId = 1 (أول موظف)
      );

      final helper = SalaryFixHelper(db);

      // أول تشغيل: يجب أن يُصلح
      await helper.runOnceAfterFirstPull();
      final fixed1 = await getExpense(expenseId);
      expect(fixed1!.relatedId, 1, reason: 'الإصلاح الأول يجب أن يعمل');

      // إعادة المصروف لحالة يتيمة لمحاكاة تكرار الإصلاح
      await db.customUpdate(
        'UPDATE expenses SET related_id = 999, employee_uuid = NULL WHERE id = ?',
        variables: [d.Variable.withInt(expenseId)],
        updates: {db.expenses},
      );

      // ثاني تشغيل: يجب أن يتخطى (flag مُضبوط)
      await helper.runOnceAfterFirstPull();
      final fixed2 = await getExpense(expenseId);
      expect(fixed2!.relatedId, 999,
          reason: 'الإصلاح الثاني يجب أن يتخطى (flag مُضبوط)');
    });

    test('runOnceAfterFirstPull يتأجل عندما لا يوجد موظفون', () async {
      // لا موظفين
      final expenseId = await createOrphanSalaryExpense(
        expenseType: 'سحب من الراتب',
        relatedId: 999,
        employeeUuid: null,
      );

      final helper = SalaryFixHelper(db);
      await helper.runOnceAfterFirstPull();

      // يجب أن يبقى المصروف دون إصلاح (التأجيل)
      final unchanged = await getExpense(expenseId);
      expect(unchanged!.relatedId, 999, reason: 'يجب التأجيل حتى وصول الموظفين');

      // flag يجب أن لا يُضبط (لإعادة المحاولة لاحقاً)
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('salary_fix_v1_done'), isNull,
          reason: 'flag يجب أن لا يُضبط عند التأجيل');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 6. database_fixer — منع تصفير الرواتب
  // ═══════════════════════════════════════════════════════════════════════

  group('DatabaseFixer._fixOrphanExpenses — فرع الرواتب', () {
    test('لا يُصفّر relatedId لمصروف راتب يتيم', () async {
      await createEmployee();
      final expenseId = await createOrphanSalaryExpense(
        expenseType: 'سحب من الراتب',
        relatedId: 999, // غير صالح
        employeeUuid: null,
      );

      await fixer.fixAllIssues();

      final after = await getExpense(expenseId);
      // يجب أن لا يُصفّر relatedId (يبقى 999 أو يُعاد ربطه إن وُجد سحب)
      expect(after!.relatedId, isNot(null),
          reason: 'relatedId يجب أن لا يُصفّر لمصروف راتب');
    });

    test('يُصفّر relatedId لمصروف نوعه employee (سلوك قديم)', () async {
      // مصروف نوعه 'employee' (ليس راتب) بـ relatedId غير صالح
      final expenseId = await db.into(db.expenses).insert(
            ExpensesCompanion(
              expenseType: const d.Value('employee'),
              relatedId: const d.Value(999),
              description: const d.Value('مصروف موظف قديم'),
              amount: const d.Value(1000),
              date: const d.Value('2026-06-01'),
              localUuid: const d.Value('exp-employee-001'),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
              createdAtEpoch: const d.Value(1000),
              lastModifiedEpoch: const d.Value(1000),
              version: const d.Value(1),
              origin: const d.Value('local'),
              vectorClock: const d.Value('{}'),
            ),
          );

      await fixer.fixAllIssues();

      final after = await getExpense(expenseId);
      expect(after!.relatedId, isNull,
          reason: 'relatedId يجب أن يُصفّر لمصروف employee (سلوك قديم)');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 7. تكامل: سيناريو شامل متعدد المصروفات
  // ═══════════════════════════════════════════════════════════════════════

  group('تكامل شامل', () {
    test('يُصلح مصروفات راتب متعددة بطرق مختلفة', () async {
      final emp1 = await createEmployee(name: 'موظف 1', localUuid: 'emp-1');
      final emp2Id = await db.into(db.employees).insert(
            EmployeesCompanion(
              name: const d.Value('موظف 2'),
              basicSalary: const d.Value(60000),
              position: const d.Value('موظف'),
              status: const d.Value('active'),
              localUuid: const d.Value('emp-2'),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
              createdAtEpoch: const d.Value(1000),
              lastModifiedEpoch: const d.Value(1000),
              version: const d.Value(1),
              origin: const d.Value('local'),
              vectorClock: const d.Value('{}'),
            ),
          );

      // مصروف 1: يُصلح عبر salary_withdrawals
      final exp1 = await createOrphanSalaryExpense(
        expenseType: 'سحب من الراتب',
        relatedId: 999,
        employeeUuid: null,
        localUuid: 'exp-int-1',
      );
      await createSalaryWithdrawal(expenseId: exp1, employeeId: emp1);

      // مصروف 2: يُصلح عبر employeeUuid
      final exp2 = await db.into(db.expenses).insert(
            ExpensesCompanion(
              expenseType: const d.Value('خصم راتب'),
              relatedId: const d.Value(999),
              description: const d.Value('خصم قديم'),
              amount: const d.Value(2000),
              date: const d.Value('2026-06-02'),
              localUuid: const d.Value('exp-int-2'),
              employeeUuid: const d.Value('emp-2'),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
              createdAtEpoch: const d.Value(1000),
              lastModifiedEpoch: const d.Value(1000),
              version: const d.Value(1),
              origin: const d.Value('local'),
              vectorClock: const d.Value('{}'),
            ),
          );

      // مصروف 3: غير قابل للإصلاح (لا سحب ولا UUID)
      final exp3 = await createOrphanSalaryExpense(
        expenseType: 'رواتب',
        relatedId: 999,
        employeeUuid: null,
        localUuid: 'exp-int-3',
      );

      final helper = SalaryFixHelper(db);
      final fixedCount = await helper.fixOrphanSalaryExpensesForTest();

      expect(fixedCount, 2, reason: 'يجب إصلاح مصروفين (exp1 + exp2)');

      // exp1 → emp1
      final f1 = await getExpense(exp1);
      expect(f1!.relatedId, emp1);
      expect(f1.employeeUuid, 'emp-1');

      // exp2 → emp2
      final f2 = await getExpense(exp2);
      expect(f2!.relatedId, emp2Id);
      expect(f2.employeeUuid, 'emp-2');

      // exp3 unchanged (لا تصفير)
      final f3 = await getExpense(exp3);
      expect(f3!.relatedId, 999, reason: 'exp3 يجب أن يبقى دون تصفير');
    });
  });
}
