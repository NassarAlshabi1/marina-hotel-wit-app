// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/employees_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// عقد «تعديل الموظف يحدّث الجدول والجداول المرتبطة — لا سجلات يتيمة»:
///
/// كل تعديل موظف (update / updateByLocalUuid) يجب أن يُبقي كل مصروف
/// مرتبط به متفقاً فيه (related_id = id) مع (employee_uuid = localUuid):
/// 1. مصروف يحمل localUuid الموظف لكن related_id قديم/فارغ → يُعاد ربطه.
/// 2. مصروف تابع عبر related_id لكن بلا uuid → تُرحَّل إليه الهوية المحمولة.
/// 3. حمايات: مصروفات الحجوزات (related_id متعدد الدلالة) لا تُمس،
///    ومصروف يحمل uuid موظف آخر لا يُمس هنا.
/// 4. التصحيحات تُكتب في outbox لتتزامن مع السحابة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late EmployeesRepository empRepo;
  late ExpensesRepository expensesRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    empRepo = EmployeesRepository(db);
    expensesRepo = ExpensesRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Employee> createEmployee(String name) async {
    final id = await empRepo.create(
      name: name,
      basicSalary: 3000,
      status: 'نشط',
    );
    return (db.select(
      db.employees,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> createExpense({
    required String type,
    int? relatedId,
    String? employeeUuid,
    double amount = 100,
  }) => expensesRepo.create(
    expenseType: type,
    relatedId: relatedId,
    description: 'اختبار',
    amount: amount,
    date: '2026-09-14',
    employeeUuid: employeeUuid,
  );

  Future<Expense> expense(int id) => (db.select(
    db.expenses,
  )..where((t) => t.id.equals(id))).getSingle();

  group('تسوية ما بعد تعديل الموظف — لا سجلات يتيمة', () {
    test(
      '1) مصروف يحمل localUuid الموظف بـ related_id قديم → يُعاد ربطه',
      () async {
        final a = await createEmployee('موظف أ');
        // سيناريو الانفكاك: المصروف سُحب بـ uuid قبل وصول الموظف/انزياح id
        final expId = await createExpense(
          type: 'سحب راتب',
          relatedId: 99999,
          employeeUuid: a.localUuid,
        );

        final rows = await empRepo.updateByLocalUuid(
          a.localUuid,
          name: 'أ معدل',
        );
        expect(rows, 1);

        final exp = await expense(expId);
        expect(
          exp.relatedId,
          a.id,
          reason: 'الهوية المحمولة (uuid) تفوز — related_id يُصحح',
        );
        expect(exp.employeeUuid, a.localUuid);
      },
    );

    test(
      '2) مصروف تابع عبر related_id بلا uuid → تُرحَّل إليه الهوية المحمولة',
      () async {
        final a = await createEmployee('موظف ب');
        final expId = await createExpense(type: 'سلفة', relatedId: a.id);

        await empRepo.updateByLocalUuid(a.localUuid, phone: '777000111');

        final exp = await expense(expId);
        expect(
          exp.employeeUuid,
          a.localUuid,
          reason: 'سجلات قديمة تكتسب هوية محمولة',
        );
        expect(exp.relatedId, a.id);
      },
    );

    test('3) حماية: مصروف «حجز» يصادف related_id رقمياً → لا يُمس', () async {
      final a = await createEmployee('موظف ج');
      final expId = await createExpense(
        type: 'booking',
        relatedId: a.id, // تصادف رقمي بحت — ليس ملك هذا الموظف
      );

      await empRepo.updateByLocalUuid(a.localUuid, name: 'ج معدل');

      final exp = await expense(expId);
      expect(
        exp.employeeUuid,
        isNull,
        reason: 'related_id متعدد الدلالة — لا يُربط بموظف خطأً',
      );
      expect(exp.relatedId, a.id);
    });

    test(
      '4) حماية: مصروف يحمل uuid موظف آخر → لا يُمس عند تعديل موظفنا',
      () async {
        final a = await createEmployee('موظف د');
        final b = await createEmployee('موظف هـ');
        final expId = await createExpense(
          type: 'خصم من الراتب',
          relatedId: a.id, // تصادم رقمي — الهوية (uuid) تقول موظف آخر
          employeeUuid: b.localUuid,
        );

        await empRepo.updateByLocalUuid(a.localUuid, name: 'د معدل');

        final exp = await expense(expId);
        expect(
          exp.employeeUuid,
          b.localUuid,
          reason: 'uuid صاحب المصروف هو الفيصل — تعديل صاحبه هو من يصلحه',
        );
      },
    );

    test('5) التصحيحات تُكتب في outbox لتتزامن مع السحابة', () async {
      final a = await createEmployee('موظف و');
      final expId = await createExpense(
        type: 'غياب',
        relatedId: 88888,
        employeeUuid: a.localUuid,
      );
      final exp = await expense(expId);

      await empRepo.updateByLocalUuid(a.localUuid, name: 'و معدل');

      // ✅ OutboxDao.merge يدمج في الصف المعلق نفسه (entity+localUuid) —
      // فالعقد الصحيح: الحمولة المعلقة تحمل القيمة المصححة للرفع
      final rows =
          await (db.select(db.outbox)
                ..where((o) => o.entity.equals('expenses'))
                ..where((o) => o.localUuid.equals(exp.localUuid)))
              .get();
      expect(rows, isNotEmpty, reason: 'الإصلاح يجب أن يُرفع للسحابة');
      final payload = jsonDecode(rows.first.payload) as Map<String, dynamic>;
      expect(
        payload['relatedId'],
        a.id,
        reason:
            'الحمولة المعلقة تحمل related_id المصحح — جهاز آخر لن يعيد كسر الربط',
      );
    });

    test('6) التسوية idempotent — تعديل ثانٍ بلا فوضى', () async {
      final a = await createEmployee('موظف ز');
      await createExpense(
        type: 'سحب راتب',
        relatedId: 77777,
        employeeUuid: a.localUuid,
      );
      await empRepo.updateByLocalUuid(a.localUuid, name: 'ز 1');

      await empRepo.updateByLocalUuid(a.localUuid, name: 'ز 2');

      // ✅ التعديل الثاني: لا شيء يُصلح → لا استدعاءات update → الحمولة
      // المعلقة تبقى كما هي (لا إعادة رفع بلا داعٍ)
      // (التغير الوحيد المسموح: صف الموظف نفسه في outbox)
      final expRows = await (db.select(
        db.outbox,
      )..where((o) => o.entity.equals('expenses'))).get();
      final expPayloads = expRows.map((r) => r.payload).toSet();
      expect(
        expPayloads.length,
        1,
        reason:
            'مصروف واحد فقط في outbox — التعديل الثاني لم يولّد تحديثاً جديداً للمصروف',
      );
    });

    test('7) مسار update(id) يُسوّي أيضاً', () async {
      final a = await createEmployee('موظف ح');
      final expId = await createExpense(
        type: 'رواتب',
        relatedId: 66666,
        employeeUuid: a.localUuid,
      );

      final rows = await empRepo.update(a.id, name: 'ح معدل');
      expect(rows, 1);

      final exp = await expense(expId);
      expect(exp.relatedId, a.id);
    });

    test(
      '8) تعديل localUuid غير موجود → 0 بلا استثناء (واجهة صادقة)',
      () async {
        final rows = await empRepo.updateByLocalUuid(
          '00000000-0000-0000-0000-000000000000',
          name: 'لا أحد',
        );
        expect(rows, 0);
      },
    );

    test('9) كل حقول الموظف تُحدَّث + بيانات المزامنة تتراكم', () async {
      final a = await createEmployee('موظف ط');
      final versionBefore = a.version;

      await empRepo.updateByLocalUuid(
        a.localUuid,
        name: 'ط معدل',
        position: 'مدير',
        salary: 4500,
        phone: '777123123',
        hireDate: '2025-01-01',
        status: 'غير نشط',
      );

      final after = await (db.select(
        db.employees,
      )..where((t) => t.id.equals(a.id))).getSingle();
      expect(after.name, 'ط معدل');
      expect(after.position, 'مدير');
      expect(after.basicSalary, 4500);
      expect(after.phone, '777123123');
      expect(after.hireDate, '2025-01-01');
      expect(
        after.status,
        isNot('غير نشط'),
        reason: 'الحالة تُطبّع عبر StatusUtils',
      );
      expect(
        after.localUuid,
        a.localUuid,
        reason: 'الهوية لا تتغير — لا أطفال يتيمون',
      );
      expect(after.version, greaterThan(versionBefore));
    });

    test('10) الخصوم بأنواع خدمة الاستحقاق كلها تدخل نطاق الترحيل', () async {
      final a = await createEmployee('موظف ي');
      final types = ['خصم راتب', 'خصم', 'غياب', 'خصم من الراتب'];
      final ids = <int>[];
      for (final t in types) {
        ids.add(await createExpense(type: t, relatedId: a.id));
      }

      await empRepo.updateByLocalUuid(a.localUuid, name: 'ي معدل');

      for (final id in ids) {
        final exp = await expense(id);
        expect(
          exp.employeeUuid,
          a.localUuid,
          reason:
              'نوع ${exp.expenseType} تقرأه خدمة الاستحقاق عبر related_id — يجب أن يكتسب هوية محمولة',
        );
      }
    });
  });
}
