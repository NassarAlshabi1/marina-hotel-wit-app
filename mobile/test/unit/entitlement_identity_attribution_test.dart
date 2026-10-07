// test/unit/entitlement_identity_attribution_test.dart
//
// ✅ (2026-10-06): إثبات ربط الموظف في شاشة «استحقاقات الرواتب».
//
// الفجوة المُثبتة في الكود: كل استعلامات `SalaryEntitlementService` كانت
// تُفلتر بالرقم المحلي وحده (`related_id = employee.id` للمصروفات،
// `employee_id` للسحوبات) ⇒ أي صف يعلن انتماءه لهوية موظف آخر (employee_uuid
// مختلف) كان يُنسب لغير صاحبه بصمت.
//
// القاعدة الجديدة (لا تخمين، ولا فقدان مال) مُختبَرة هنا:
//   • بلا هوية ⇒ النسب بالرقم (سجل قديم).
//   • الهوية تطابق ⇒ يُنسب.
//   • الهوية لموظف آخر **موجود محلياً** ⇒ يُستبعد هنا (يُحتسب عند صاحبه).
//   • الهوية لموظف **غير موجود محلياً** ⇒ يُنسب احتياطاً مع تحذير.
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/salary_entitlement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SalaryEntitlementService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = SalaryEntitlementService(db);
  });

  tearDown(() async {
    await db.close();
  });

  String padded(int n) => n.toString().padLeft(2, '0');

  /// موظف براتب 1000 منذ 12 شهراً بالضبط ⇒ استحقاق حتمي 12000.
  Future<int> createEmployee({required String uuid, String name = 'موظف'}) {
    final now = DateTime.now();
    final hire = DateTime(now.year - 1, now.month, 1);
    return db
        .into(db.employees)
        .insert(
          EmployeesCompanion(
            name: d.Value(name),
            basicSalary: const d.Value(1000),
            status: const d.Value('active'),
            hireDate: d.Value('${hire.year}-${padded(hire.month)}-01'),
            localUuid: d.Value(uuid),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );
  }

  Future<Employee> employeeById(int id) =>
      (db.select(db.employees)..where((e) => e.id.equals(id))).getSingle();

  Future<int> createExpense({
    required int relatedId,
    String? employeeUuid,
    String type = 'سحب راتب',
    double amount = 500,
    String date = '2026-01-05',
  }) => db
      .into(db.expenses)
      .insert(
        ExpensesCompanion(
          expenseType: d.Value(type),
          relatedId: d.Value(relatedId),
          employeeUuid: d.Value(employeeUuid),
          description: const d.Value('مصروف اختبار'),
          amount: d.Value(amount),
          date: d.Value(date),
          hotelDayKey: d.Value(date),
          localUuid: d.Value('exp-$relatedId-$amount-$date'),
          createdAt: const d.Value(1000),
          updatedAt: const d.Value(1000),
          lastModified: const d.Value(1000),
        ),
      );

  Future<int> createWithdrawal({
    required int employeeId,
    String? employeeUuid,
    double amount = 500,
    String date = '2026-01-05',
    String reason = 'direct_withdrawal_test',
  }) => db
      .into(db.salaryWithdrawals)
      .insert(
        SalaryWithdrawalsCompanion(
          employeeId: d.Value(employeeId),
          employeeUuid: d.Value(employeeUuid),
          amount: d.Value(amount),
          withdrawDate: d.Value(date),
          reason: d.Value(reason),
          withdrawalType: const d.Value('سحب راتب'),
          hotelDayKey: d.Value(date),
          localUuid: d.Value('sw-$employeeId-$amount-$date-$reason'),
          createdAt: const d.Value(1000),
          updatedAt: const d.Value(1000),
          lastModified: const d.Value(1000),
        ),
      );

  group('قاعدة النسب النقية shouldAttributeRow', () {
    test('بلا هوية معلنة ⇒ يُنسب (سجل قديم)', () {
      expect(
        SalaryEntitlementService.shouldAttributeRow(
          declaredUuid: '',
          ownerUuid: 'emp-A',
          declaredOwnerExistsLocally: false,
        ),
        isTrue,
      );
    });

    test('الهوية تطابق الموظف ⇒ يُنسب', () {
      expect(
        SalaryEntitlementService.shouldAttributeRow(
          declaredUuid: 'emp-A',
          ownerUuid: 'emp-A',
          declaredOwnerExistsLocally: false,
        ),
        isTrue,
      );
    });

    test('هوية موظف آخر موجود محلياً ⇒ يُستبعد (لا احتساب مزدوج)', () {
      expect(
        SalaryEntitlementService.shouldAttributeRow(
          declaredUuid: 'emp-B',
          ownerUuid: 'emp-A',
          declaredOwnerExistsLocally: true,
        ),
        isFalse,
      );
    });

    test('هوية موظف غير موجود محلياً ⇒ يُنسب احتياطاً (لا فقدان مال)', () {
      expect(
        SalaryEntitlementService.shouldAttributeRow(
          declaredUuid: 'emp-GONE',
          ownerUuid: 'emp-A',
          declaredOwnerExistsLocally: false,
        ),
        isTrue,
      );
    });
  });

  group('الاستحقاق يربط بالهوية لا بالرقم المحلي', () {
    test('مصروف يعلن موظفاً آخر موجوداً ⇒ لا يُحتسب لصاحب الرقم', () async {
      final empA = await createEmployee(uuid: 'emp-A', name: 'أ');
      final empB = await createEmployee(uuid: 'emp-B', name: 'ب');

      // ربط خاطئ: related_id يشير إلى A والهوية تعلن B.
      await createExpense(relatedId: empA, employeeUuid: 'emp-B', amount: 700);

      final a = await employeeById(empA);
      final b = await employeeById(empB);
      final entA = await service.calculateEmployeeEntitlement(a);
      final entB = await service.calculateEmployeeEntitlement(b);

      expect(
        entA.totalWithdrawals,
        0,
        reason: 'المصروف يعلن انتماءه لـ B ⇒ لا يُنسب لـ A',
      );
      expect(
        entB.totalWithdrawals,
        700,
        reason: 'يُحتسب عند صاحبه (B) ولو كان الرقم المحلي يشير لـ A',
      );
    });

    test('سحبة وصلت برقم محلي مختلف لكن بهوية هذا الموظف ⇒ تُنسب له', () async {
      final empA = await createEmployee(uuid: 'emp-A', name: 'أ');
      final empB = await createEmployee(uuid: 'emp-B', name: 'ب');

      // سحبة من جهاز آخر: رقم محلي يخص B والهوية تعلن A (حالة الجذب بالهوية).
      await createWithdrawal(
        employeeId: empB,
        employeeUuid: 'emp-A',
        amount: 300,
      );

      final a = await employeeById(empA);
      final b = await employeeById(empB);
      final entA = await service.calculateEmployeeEntitlement(a);
      final entB = await service.calculateEmployeeEntitlement(b);

      expect(entA.totalWithdrawals, 300, reason: 'الهوية الدائمة هي الحاكمة');
      expect(
        entB.totalWithdrawals,
        0,
        reason: 'لا تُحتسب مرتين عند صاحب الرقم المحلي',
      );
    });

    test(
      'سحبة بهوية موظف غير موجود محلياً ⇒ تُنسب احتياطاً بلا فقدان',
      () async {
        final empA = await createEmployee(uuid: 'emp-A');
        await createWithdrawal(
          employeeId: empA,
          employeeUuid: 'emp-DELETED-ELSEWHERE',
          amount: 250,
        );

        final a = await employeeById(empA);
        final entA = await service.calculateEmployeeEntitlement(a);
        expect(
          entA.totalWithdrawals,
          250,
          reason: 'صاحب الهوية غير موجود محلياً ⇒ لا نُسقط المال من التقارير',
        );
      },
    );

    test(
      'سجل قديم بلا هوية (employee_uuid = NULL) ⇒ النسب بالرقم كما كان',
      () async {
        final empA = await createEmployee(uuid: 'emp-A');
        await createWithdrawal(employeeId: empA, amount: 400);

        final a = await employeeById(empA);
        final entA = await service.calculateEmployeeEntitlement(a);
        expect(entA.totalWithdrawals, 400);
      },
    );

    test('السحب المباشر الصحيح يبقى 4000 ويُخصم من الاستحقاق', () async {
      final empA = await createEmployee(uuid: 'emp-A');
      await createWithdrawal(
        employeeId: empA,
        employeeUuid: 'emp-A',
        amount: 4000,
      );

      final a = await employeeById(empA);
      final entA = await service.calculateEmployeeEntitlement(a);
      expect(entA.totalEntitlement, 12000);
      expect(entA.totalWithdrawals, 4000);
      expect(entA.netEntitlement, 8000);
    });
  });
}
