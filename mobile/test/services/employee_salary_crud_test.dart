// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// local_db.dart exports ExpensesCompanion, EmployeesCompanion, etc.
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/employees_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/salary_entitlement_service.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/utils/status_utils.dart';

/// اختبارات تكاملية فعلية لـ:
/// 1. إضافة/تعديل/حذف الموظفين
/// 2. إنشاء/تعديل/حذف سحوبات الرواتب (المصدر الأساسي للاستحقاقات)
/// 3. حساب الاستحقاقات بعد كل عملية
/// 4. التحقق من كتابة outbox للمزامنة
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late EmployeesRepository empRepo;
  late SalaryWithdrawalsRepository swRepo;
  late SalaryEntitlementService entService;
  late OutboxDao outboxDao;

  setUp(() {
    // ✅ تهيئة SharedPreferences بـ mock لمنع أخطاء AutoBackupManager
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    empRepo = EmployeesRepository(db);
    swRepo = SalaryWithdrawalsRepository(db);
    entService = SalaryEntitlementService(db);
    outboxDao = OutboxDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 1. موظفين — CRUD
  // ═══════════════════════════════════════════════════════════════════════

  group('موظفين — CRUD', () {
    test('إضافة موظف جديد', () async {
      final id = await empRepo.create(
        name: 'أحمد محمد',
        basicSalary: 50000,
        position: 'موظف استقبال',
        phone: '777123456',
        status: 'active',
      );
      expect(id, greaterThan(0), reason: 'يجب أن يُرجع id صالح');

      // تحقق من حفظ البيانات
      final emp = await (db.select(db.employees)..where((t) => t.id.equals(id))).getSingle();
      expect(emp.name, 'أحمد محمد');
      expect(emp.basicSalary, 50000);
      expect(emp.position, 'موظف استقبال');
      expect(emp.phone, '777123456');
      expect(emp.status, 'active');
      expect(emp.localUuid, isNotEmpty, reason: 'localUuid يجب أن يُولّد');
      expect(emp.origin, 'local');
      expect(emp.version, 1);

      // تحقق من كتابة outbox
      final pending = await outboxDao.count(sources: const ['local']);
      expect(pending, greaterThan(0), reason: 'outbox يجب أن يحتوي على عملية create');
    });

    test('تعديل موظف', () async {
      final id = await empRepo.create(name: 'سالم علي', basicSalary: 40000, position: 'موظف', status: 'active');

      // عدّل البيانات
      final rows = await empRepo.update(id, name: 'سالم علي أحمد', salary: 45000, position: 'مدير', phone: '777999888');
      expect(rows, 1, reason: 'يجب تحديث سجل واحد');

      final emp = await (db.select(db.employees)..where((t) => t.id.equals(id))).getSingle();
      expect(emp.name, 'سالم علي أحمد');
      expect(emp.basicSalary, 45000);
      expect(emp.position, 'مدير');
      expect(emp.phone, '777999888');
      expect(emp.version, 2, reason: 'version يجب أن يزداد');
    });

    test('تعديل موظف بـ localUuid', () async {
      final id = await empRepo.create(name: 'خالد سعيد', basicSalary: 30000, position: 'عامل', status: 'active');
      final emp = await (db.select(db.employees)..where((t) => t.id.equals(id))).getSingle();
      final uuid = emp.localUuid;

      await empRepo.updateByLocalUuid(uuid, name: 'خالد سعيد محمد', salary: 35000);

      final updated = await (db.select(db.employees)..where((t) => t.localUuid.equals(uuid))).getSingle();
      expect(updated.name, 'خالد سعيد محمد');
      expect(updated.basicSalary, 35000);
      expect(updated.version, 2);
    });

    test('حذف موظف (soft delete)', () async {
      final id = await empRepo.create(name: 'محمد علي', basicSalary: 25000, position: 'حارس', status: 'active');

      final rows = await empRepo.delete(id);
      expect(rows, 1, reason: 'يجب حذف سجل واحد');

      final emp = await (db.select(db.employees)..where((t) => t.id.equals(id))).getSingle();
      expect(emp.deletedAt, isNotNull, reason: 'deletedAt يجب أن يُضبط');
      expect(emp.deletedAt! > 0, true);

      // تحقق أن watchAll (الذي يفلتر deletedAt) لا يُرجعه
      final all = await db.select(db.employees).get();
      final active = all.where((e) => e.deletedAt == null).toList();
      expect(active.where((e) => e.id == id), isEmpty, reason: 'الموظف المحذوف لا يجب أن يظهر في القائمة النشطة');
    });

    test('إنهاء خدمة موظف (terminate)', () async {
      final id = await empRepo.create(name: 'عبدالله أحمد', basicSalary: 40000, position: 'محاسب', status: 'active');

      await empRepo.terminate(
        id: id,
        terminationType: 'مفصول',
        terminationDate: '2026-06-15',
        terminationReason: 'استقالة',
      );

      final emp = await (db.select(db.employees)..where((t) => t.id.equals(id))).getSingle();
      expect(emp.status, StatusUtils.canonicalEmployeeStatus('مفصول'));
      expect(emp.terminationDate, '2026-06-15');
      expect(emp.terminationReason, 'استقالة');
    });

    test('إعادة تفعيل موظف (reactivate)', () async {
      final id = await empRepo.create(name: 'فهد ناصر', basicSalary: 35000, position: 'موظف', status: 'مفصول');

      await empRepo.reactivate(id: id);

      final emp = await (db.select(db.employees)..where((t) => t.id.equals(id))).getSingle();
      expect(emp.status, 'active');
      expect(emp.terminationDate, isNull);
      expect(emp.terminationReason, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2. سحوبات الرواتب — CRUD (مصدر الاستحقاقات)
  // ═══════════════════════════════════════════════════════════════════════

  group('سحوبات الرواتب — CRUD', () {
    test('إنشاء سحب راتب من مصروف', () async {
      // أنشئ موظف أولاً
      final empId = await empRepo.create(name: 'موظف اختبار', basicSalary: 50000, position: 'موظف', status: 'active');

      // أنشئ سحب راتب
      final swId = await swRepo.createFromExpense(
        expenseId: 1,
        employeeId: empId,
        reason: 'exp_1',
        amount: 10000,
        date: '2026-07-01',
        withdrawalType: 'سحب من الراتب',
      );
      expect(swId, greaterThan(0));

      final sw = await (db.select(db.salaryWithdrawals)..where((t) => t.id.equals(swId))).getSingle();
      expect(sw.employeeId, empId);
      expect(sw.amount, 10000);
      expect(sw.withdrawDate, '2026-07-01');
      expect(sw.localUuid, isNotEmpty);
      expect(sw.version, 1);
      expect(sw.deletedAt, isNull);

      // تحقق من outbox
      final pending = await outboxDao.count(sources: const ['local']);
      expect(pending, greaterThan(0));
    });

    test('حفظ/تحديث سحب راتب (saveFromExpense upsert)', () async {
      final empId = await empRepo.create(name: 'موظف اختبار 2', basicSalary: 60000, position: 'موظف', status: 'active');

      // أنشئ سحب راتب
      await swRepo.saveFromExpense(
        expenseId: 100,
        employeeId: empId,
        action: 'سحب من الراتب',
        amount: 5000,
        date: '2026-07-02',
        note: 'سحب راتب يوليو',
      );

      // تحقق من الإنشاء
      final created = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.reason.like('%exp_100%') & t.deletedAt.isNull())).get();
      expect(created.length, 1);
      expect(created.first.amount, 5000);

      // عدّل المبلغ
      await swRepo.saveFromExpense(
        expenseId: 100,
        employeeId: empId,
        action: 'سحب من الراتب',
        amount: 8000,
        date: '2026-07-02',
        note: 'سحب راتب يوليو (معدّل)',
      );

      // تحقق من التحديث (وليس إنشاء سجل جديد)
      final after = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.reason.like('%exp_100%') & t.deletedAt.isNull())).get();
      expect(after.length, 1, reason: 'يجب تحديث السجل الموجود وليس إنشاء جديد');
      expect(after.first.amount, 8000);
      expect(after.first.version, 2, reason: 'version يجب أن يزداد');
    });

    test('حذف سحب راتب (soft delete)', () async {
      final empId = await empRepo.create(name: 'موظف اختبار 3', basicSalary: 40000, position: 'موظف', status: 'active');

      await swRepo.saveFromExpense(
        expenseId: 200,
        employeeId: empId,
        action: 'سحب من الراتب',
        amount: 3000,
        date: '2026-07-03',
      );

      // تحقق من وجوده
      final before = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.reason.like('%exp_200%') & t.deletedAt.isNull())).get();
      expect(before.length, 1);

      // احذف
      await swRepo.deleteByExpenseId(200);

      // تحقق من الحذف الناعم
      final after = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.reason.like('%exp_200%') & t.deletedAt.isNull())).get();
      expect(after, isEmpty, reason: 'السجل يجب أن يكون محذوف ناعماً');

      final deleted = await (db.select(db.salaryWithdrawals)..where((t) => t.reason.like('%exp_200%'))).get();
      expect(deleted.length, 1);
      expect(deleted.first.deletedAt, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 3. الاستحقاقات — حساب بعد CRUD
  // ═══════════════════════════════════════════════════════════════════════

  group('الاستحقاقات — حساب', () {
    test('حساب استحقاق موظف بدون سحوبات', () async {
      final empId = await empRepo.create(
        name: 'موظف بلا سحوبات',
        basicSalary: 50000,
        position: 'موظف',
        hireDate: '2026-01-01',
        status: 'active',
      );

      final emp = await (db.select(db.employees)..where((t) => t.id.equals(empId))).getSingle();

      final ent = await entService.calculateEmployeeEntitlement(emp);

      expect(ent.employee.id, empId);
      expect(ent.basicSalary, 50000);
      expect(ent.totalWithdrawals, 0);
      expect(ent.totalAdvances, 0);
      expect(ent.totalDeductions, 0);
      expect(ent.netEntitlement, ent.totalEntitlement, reason: 'بدون سحوبات، المتبقي = إجمالي الاستحقاق');
    });

    test('حساب استحقاق بعد إضافة سحب راتب', () async {
      final empId = await empRepo.create(
        name: 'موظف بسحب راتب',
        basicSalary: 50000,
        position: 'موظف',
        hireDate: '2026-01-01',
        status: 'active',
      );

      // أضف مصروف "سحب راتب" مرتبط بالموظف
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              localUuid: 'test-exp-1',
              expenseType: 'سحب راتب',
              amount: 15000,
              date: '2026-07-01',
              relatedId: d.Value(empId),
              description: 'سحب راتب يوليو',
              createdAt: now,
              updatedAt: now,
              lastModified: now,
            ),
          );

      final emp = await (db.select(db.employees)..where((t) => t.id.equals(empId))).getSingle();

      final ent = await entService.calculateEmployeeEntitlement(emp);

      expect(ent.totalWithdrawals, 15000, reason: 'سحب راتب يجب أن يظهر في totalWithdrawals');
      expect(ent.netEntitlement, ent.totalEntitlement - 15000);
    });

    test('حساب استحقاق بعد حذف السحب', () async {
      final empId = await empRepo.create(
        name: 'موظف بعد حذف سحب',
        basicSalary: 50000,
        position: 'موظف',
        hireDate: '2026-01-01',
        status: 'active',
      );

      // أضف مصروف
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expId = await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              localUuid: 'test-exp-2',
              expenseType: 'سحب راتب',
              amount: 20000,
              date: '2026-07-01',
              relatedId: d.Value(empId),
              description: 'سحب راتب',
              createdAt: now,
              updatedAt: now,
              lastModified: now,
            ),
          );

      // تحقق قبل الحذف
      final emp = await (db.select(db.employees)..where((t) => t.id.equals(empId))).getSingle();
      final entBefore = await entService.calculateEmployeeEntitlement(emp);
      expect(entBefore.totalWithdrawals, 20000);

      // احذف المصروف (soft delete)
      await (db.update(db.expenses)..where((t) => t.id.equals(expId))).write(
        ExpensesCompanion(deletedAt: d.Value(now), updatedAt: d.Value(now), lastModified: d.Value(now)),
      );

      // تحقق بعد الحذف
      final entAfter = await entService.calculateEmployeeEntitlement(emp);
      expect(entAfter.totalWithdrawals, 0, reason: 'بعد حذف المصروف، totalWithdrawals يجب أن يعود لـ 0');
      expect(entAfter.netEntitlement, entAfter.totalEntitlement);
    });

    test('حساب استحقاق لكل الموظفين النشطين', () async {
      await empRepo.create(name: 'موظف 1', basicSalary: 30000, hireDate: '2026-01-01', status: 'active');
      await empRepo.create(name: 'موظف 2', basicSalary: 40000, hireDate: '2026-01-01', status: 'active');
      // موظف محذوف — يجب ألا يظهر
      final deletedId = await empRepo.create(
        name: 'موظف محذوف',
        basicSalary: 50000,
        hireDate: '2026-01-01',
        status: 'active',
      );
      await empRepo.delete(deletedId);
      // موظف مفصول — يجب ألا يظهر
      await empRepo.create(name: 'موظف مفصول', basicSalary: 60000, hireDate: '2026-01-01', status: 'مفصول');

      final entitlements = await entService.calculateAllEntitlements();

      expect(entitlements.length, 2, reason: 'فقط الموظفون النشطون (غير المحذوفين) يجب أن يظهروا');
      final names = entitlements.map((e) => e.employee.name).toSet();
      expect(names, containsAll(['موظف 1', 'موظف 2']));
      expect(names, isNot(contains('موظف محذوف')));
      expect(names, isNot(contains('موظف مفصول')));
    });
  });
}
