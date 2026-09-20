// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// local_db.dart exports ExpensesCompanion, EmployeesCompanion, etc.
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/employees_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/utils/status_utils.dart';

/// ✅ اختبارات حارس حذف الموظفين (سياسة الفصل 2026-09-21):
/// «إنهاء الخدمة» (تغيير حالة فقط) هو مسار الفصل — الحذف يتيّم التاريخ
/// المالي على بقية الأجهزة. قبل الحذف نعرض عدد السجلات المالية المرتبطة
/// للموظف (مصروفات رواتب/سلف + سحوبات غير مكررة).
///
/// تغطية:
/// 1. موظف بلا سجلات مالية → 0 (الحذف آمن)
/// 2. زوج مصروف↔سحب مرتبط (expense_id) يُعدّ مرة واحدة — لا عدّ مزدوج
/// 3. سحب غير مرتبط بمصروف يُعدّ سجلاً مستقلاً
/// 4. الربط عبر UUID فقط (جهاز آخر حيث يختلف id الرقمي) يُلتقط
/// 5. السجلات المحذوفة منطقياً (deletedAt) لا تُعدّ
/// 6. موظف منتهية خدمته تُعدّ سجلاته — الحارس يعمل بعد الإنهاء
/// 7. موظف غير موجود → 0 (لا استثناء)
/// 8. المسار الإنتاجي الفعلي: مصروف + createFromExpense → 1
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late EmployeesRepository empRepo;
  late SalaryWithdrawalsRepository swRepo;

  const now = 1758412800; // ثابت — لا حاجة لوقت حقيقي

  // عدادات لتوليد localUuid فريد داخل نفس الاختبار (العمود unique)
  int seedExpenseCounter = 0;
  int seedWithdrawalCounter = 0;

  setUp(() {
    // ✅ تهيئة SharedPreferences بـ mock لمنع أخطاء AutoBackupManager
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    empRepo = EmployeesRepository(db);
    swRepo = SalaryWithdrawalsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// إنشاء موظف وإرجاع الصف الكامل (id + localUuid)
  Future<Employee> seedEmployee(String name, {String status = 'active'}) async {
    final id = await empRepo.create(
      name: name,
      basicSalary: 50000,
      status: status,
    );
    return (db.select(db.employees)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  /// إدخال مصروف رواتب مرتبط بموظف
  Future<int> seedExpense(
    Employee emp, {
    bool byUuidOnly = false,
    String? uuid,
  }) async {
    return db.into(db.expenses).insert(
          ExpensesCompanion(
            expenseType: const d.Value('رواتب'),
            description: const d.Value('راتب شهر'),
            amount: const d.Value(50000.0),
            date: const d.Value('2026-09-01'),
            relatedId: byUuidOnly ? const d.Value(null) : d.Value(emp.id),
            employeeUuid: d.Value(emp.localUuid),
            localUuid: d.Value(uuid ?? 'exp-${emp.id}-${now}-${seedExpenseCounter++}'),
            createdAt: const d.Value(now),
            updatedAt: const d.Value(now),
            lastModified: const d.Value(now),
          ),
        );
  }

  /// إدخال سحب راتب مرتبط بموظف
  Future<int> seedWithdrawal(
    Employee emp, {
    int? expenseId,
    String? uuid,
  }) async {
    return db.into(db.salaryWithdrawals).insert(
          SalaryWithdrawalsCompanion(
            employeeId: d.Value(emp.id),
            employeeUuid: d.Value(emp.localUuid),
            amount: const d.Value(10000.0),
            withdrawDate: const d.Value('2026-09-01'),
            expenseId: d.Value(expenseId),
            localUuid: d.Value(uuid ?? 'sw-${emp.id}-${now}-${seedWithdrawalCounter++}'),
            createdAt: const d.Value(now),
            updatedAt: const d.Value(now),
            lastModified: const d.Value(now),
          ),
        );
  }

  group('حارس حذف الموظفين — عدّ السجلات المالية', () {
    test('موظف بلا سجلات مالية → 0', () async {
      final emp = await seedEmployee('أحمد');
      final count = await empRepo.financialRecordsCount(emp.id);
      expect(count, 0, reason: 'لا سجلات مرتبطة — الحذف آمن');
    });

    test('زوج مصروف↔سحب مرتبط (expense_id) يُعدّ مرة واحدة', () async {
      final emp = await seedEmployee('سالم');
      final expId = await seedExpense(emp);
      await seedWithdrawal(emp, expenseId: expId);

      final count = await empRepo.financialRecordsCount(emp.id);
      expect(
        count,
        1,
        reason: 'السحب مرتبط بالمصروف عبر expense_id — حدث مالي واحد',
      );
    });

    test('سحب غير مرتبط بمصروف يُعدّ سجلاً مستقلاً', () async {
      final emp = await seedEmployee('خالد');
      await seedExpense(emp);
      await seedWithdrawal(emp, expenseId: null);

      final count = await empRepo.financialRecordsCount(emp.id);
      expect(count, 2, reason: 'مصروف واحد + سحب مستقل = 2');
    });

    test('الربط عبر UUID فقط (id رقمي مختلف) يُلتقط', () async {
      final emp = await seedEmployee('منير');
      // مصروف وصل من جهاز آخر: relatedId=null والربط عبر employeeUuid فقط
      await seedExpense(emp, byUuidOnly: true);

      final count = await empRepo.financialRecordsCount(emp.id);
      expect(
        count,
        1,
        reason: 'العدّ عبر employeeUuid يلتقط السجلات العابرة للأجهزة',
      );
    });

    test('سحب عبر UUID فقط (employeeId مختلف) يُلتقط', () async {
      final emp = await seedEmployee('نبيل');
      // سحب يتيم من جهاز آخر: employeeId يشير لمعرف غير موجود — حالة
      // واقعية من قواعد مُستعادة (مسار الاستعادة يطفئ FK ثم يعيده،
      // انظر local_db.dart: PRAGMA foreign_keys = OFF أثناء الاستيراد).
      // نحاكي نفس مسار الإنتاج هنا.
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db.into(db.salaryWithdrawals).insert(
            SalaryWithdrawalsCompanion(
              employeeId: const d.Value(9999),
              employeeUuid: d.Value(emp.localUuid),
              amount: const d.Value(5000.0),
              withdrawDate: const d.Value('2026-09-01'),
              localUuid: const d.Value('sw-foreign-1'),
              createdAt: const d.Value(now),
              updatedAt: const d.Value(now),
              lastModified: const d.Value(now),
            ),
          );
      await db.customStatement('PRAGMA foreign_keys = ON');

      final count = await empRepo.financialRecordsCount(emp.id);
      expect(
        count,
        1,
        reason: 'الربط عبر UUID ينقذ العدّ رغم اختلاف المعرف الرقمي',
      );
    });

    test('السجلات المحذوفة منطقياً (deletedAt) لا تُعدّ', () async {
      final emp = await seedEmployee('علي');
      final expId = await seedExpense(emp);
      final swId = await seedWithdrawal(emp, expenseId: expId);

      await (db.update(db.expenses)..where((t) => t.id.equals(expId))).write(
        ExpensesCompanion(
          deletedAt: const d.Value(now),
          updatedAt: const d.Value(now),
          lastModified: const d.Value(now),
        ),
      );
      await (db.update(db.salaryWithdrawals)..where((t) => t.id.equals(swId)))
          .write(
        SalaryWithdrawalsCompanion(
          deletedAt: const d.Value(now),
          updatedAt: const d.Value(now),
          lastModified: const d.Value(now),
        ),
      );

      final count = await empRepo.financialRecordsCount(emp.id);
      expect(count, 0, reason: 'السجلات المحذوفة منطقياً خارج العدّ');
    });

    test('موظف منتهية خدمته تُعدّ سجلاته — الحارس يعمل بعد الإنهاء', () async {
      final emp = await seedEmployee('راشد');
      await seedExpense(emp);
      await seedWithdrawal(emp, expenseId: null);

      // إنهاء الخدمة (تغيير حالة فقط) — التاريخ المالي يبقى
      await empRepo.terminate(
        id: emp.id,
        terminationType: 'مفصول',
        terminationDate: '2026-09-21',
        terminationReason: 'اختبار',
      );

      final after = await (db.select(
        db.employees,
      )..where((t) => t.id.equals(emp.id))).getSingle();
      expect(StatusUtils.isEmployeeTerminated(after.status), isTrue);
      expect(after.deletedAt, isNull, reason: 'الإنهاء لا يحذف — حالة فقط');

      final count = await empRepo.financialRecordsCount(emp.id);
      expect(
        count,
        2,
        reason: 'إنهاء الخدمة يحفظ التاريخ المالي — الحارس يجده كاملاً',
      );
    });

    test('موظف غير موجود → 0 بلا استثناء', () async {
      final count = await empRepo.financialRecordsCount(424242);
      expect(count, 0);
    });

    test('المسار الإنتاجي: مصروف + createFromExpense → حدث واحد', () async {
      final emp = await seedEmployee('فؤاد');
      final expId = await db.into(db.expenses).insert(
            ExpensesCompanion(
              expenseType: const d.Value('رواتب'),
              description: const d.Value('سلفة'),
              amount: const d.Value(10000.0),
              date: const d.Value('2026-09-01'),
              relatedId: d.Value(emp.id),
              employeeUuid: d.Value(emp.localUuid),
              localUuid: const d.Value('exp-prod-1'),
              createdAt: const d.Value(now),
              updatedAt: const d.Value(now),
              lastModified: const d.Value(now),
            ),
          );
      await swRepo.createFromExpense(
        expenseId: expId,
        employeeId: emp.id,
        reason: 'سلفة',
        amount: 10000,
        date: '2026-09-01',
        withdrawalType: 'سلفة',
      );

      final count = await empRepo.financialRecordsCount(emp.id);
      expect(
        count,
        1,
        reason: 'createFromExpense يربط السحب بالمصروف — لا عدّ مزدوج',
      );
    });

    test('سجلات موظف آخر لا تُنسب له', () async {
      final empA = await seedEmployee('موظف أ');
      final empB = await seedEmployee('موظف ب');
      await seedExpense(empB);
      await seedWithdrawal(empB, expenseId: null);

      final countA = await empRepo.financialRecordsCount(empA.id);
      expect(countA, 0, reason: 'العدّ دقيق — لا تسريب بين الموظفين');
    });
  });
}
