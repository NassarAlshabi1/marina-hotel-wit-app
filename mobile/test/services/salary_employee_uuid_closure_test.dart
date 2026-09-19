// ignore_for_file: lines_longer_than_80_chars
// ═══════════════════════════════════════════════════════════════
//  salary_employee_uuid_closure_test.dart — 2026-09-19
//  عقد إغلاق فجوة employee_uuid (توجيه المستخدم):
//  «اضف الحقل المفقود employee_uuid الى الجداول لا اريد فقدان
//  البيانات نهائياً والاستعلامات والتقارير سليمة وصحيحة»
//
//  الفجوة المُشخَّصة على D1 الإنتاجي:
//   * salary_withdrawals: 620/620 صفًا حياً بلا employee_uuid — الحمولات
//     لا تحمل المفتاح المستقر (employee_id رقم محلي لا يحل عبر الأجهزة)
//   * salary_cycles / salary_payments: العمود غير موجود أصلاً
//
//  العقد هنا (migration 68 محلياً + migration 0007 على D1):
//   1. العمود موجود في الجداول الثلاثة (nullable — لا فقدان بيانات)
//   2. الردم المحلي: FK المحلي الصالح → employees.local_uuid، واليتيم
//      يبقى NULL محفوظاً (لا حذف ولا تخمين)
//   3. toJson يرسل employee_uuid في كل مصادر المزامنة (السلك)
//   4. fromJson يخزن القادم من الحمولة ويستكمل من الموظف المحلول
// ═══════════════════════════════════════════════════════════════
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/adapters/salary_cycles_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/salary_payments_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/salary_withdrawals_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/id_resolver.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/sync/payload_normalizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late IdResolver resolver;
  late SalaryWithdrawalsRepository swRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    resolver = IdResolver(db);
    swRepo = SalaryWithdrawalsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedEmployee(String uuid) async {
    return db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            name: 'موظف $uuid',
            localUuid: uuid,
            basicSalary: 500,
            status: 'active',
            createdAt: 1700000000,
            updatedAt: 1700000000,
            lastModified: 1700000000,
          ),
        );
  }

  // ═══════════════════════════════════════════════════════════
  //  1) العمود موجود في المخطط المحلي (migration 68)
  // ═══════════════════════════════════════════════════════════
  test('الجداول الثلاثة تحمل عمود employee_uuid القابل للفراغ', () async {
    for (final table in [
      'salary_withdrawals',
      'salary_cycles',
      'salary_payments',
    ]) {
      final cols = await db.customSelect('PRAGMA table_info($table)').get();
      final names = cols.map((r) => r.data['name'] as String).toSet();
      expect(
        names.contains('employee_uuid'),
        true,
        reason: '$table.employee_uuid يجب أن يكون موجوداً (migration 68)',
      );
    }
  });

  // ═══════════════════════════════════════════════════════════
  //  2) الردم المحلي — نفس جُمل migration 68 حرفياً
  // ═══════════════════════════════════════════════════════════
  test('الردم المحلي يصل السحوبات والدورات والدفعات بلا فقدان', () async {
    final empA = await seedEmployee('uuid-aaaa');
    final empB = await seedEmployee('uuid-bbbb');

    // صفوف ما قبل الترقية: موظف صالح + يتيم مقصود (employee_id=999)
    final wdA = await db
        .into(db.salaryWithdrawals)
        .insert(
          SalaryWithdrawalsCompanion.insert(
            employeeId: empA,
            amount: 100,
            withdrawDate: '2026-09-01',
            localUuid: 'wd-a',
            createdAt: 1700000000,
            updatedAt: 1700000000,
            lastModified: 1700000000,
          ),
        );
    final wdOrphan = -1;
    // يتيم مقصود (employee_id=999) — FK المحلي يمنعه عبر ORM، فيُحاكى
    // كصف ما قبل الترقية عبر SQL خام مع تعطيل FK مؤقتاً (نفس وضع
    // قواعد الإنتاج المتقادمة التي أُنشئت قبل تشديد القيود)
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement(
      "INSERT INTO salary_withdrawals (employee_id, amount, withdraw_date, "
      "local_uuid, created_at, updated_at, last_modified, version, origin, vector_clock, device_id) "
      "VALUES (999, 50, '2026-09-02', 'wd-orphan', 1700000000, 1700000000, 1700000000, 1, 'local', '{}', '')",
    );
    await db.customStatement('PRAGMA foreign_keys = ON');
    final cycleB = await db
        .into(db.salaryCycles)
        .insert(
          SalaryCyclesCompanion.insert(
            employeeId: empB,
            cycleKey: 'cy-b',
            localUuid: 'cy-b',
            createdAt: 1700000000,
            updatedAt: 1700000000,
            lastModified: 1700000000,
          ),
        );
    await db
        .into(db.salaryPayments)
        .insert(
          SalaryPaymentsCompanion.insert(
            cycleId: cycleB,
            paymentDateIso: '2026-09-10',
            localUuid: 'sp-b',
            createdAt: 1700000000,
            updatedAt: 1700000000,
            lastModified: 1700000000,
          ),
        );
    // عدّ ما قبل الردم — إثبات بقاء الصف اليتيم (لا فقدان بيانات)
    final wdOrphanBefore = await db
        .customSelect(
          "SELECT COUNT(*) AS n FROM salary_withdrawals WHERE local_uuid = 'wd-orphan'",
        )
        .getSingle();

    // ─── نفس جُمل ردم migration 68 (نصياً) ───
    await db.customStatement('''
      UPDATE salary_withdrawals SET employee_uuid = (
        SELECT e.local_uuid FROM employees e
        WHERE e.id = salary_withdrawals.employee_id)
      WHERE employee_uuid IS NULL AND employee_id IS NOT NULL
    ''');
    await db.customStatement('''
      UPDATE salary_cycles SET employee_uuid = (
        SELECT e.local_uuid FROM employees e
        WHERE e.id = salary_cycles.employee_id)
      WHERE employee_uuid IS NULL AND employee_id IS NOT NULL
    ''');
    await db.customStatement('''
      UPDATE salary_payments SET employee_uuid = (
        SELECT sc.employee_uuid FROM salary_cycles sc
        WHERE sc.id = salary_payments.cycle_id)
      WHERE employee_uuid IS NULL AND cycle_id IS NOT NULL
    ''');

    final wdAFTER = await db
        .customSelect(
          'SELECT local_uuid, employee_uuid FROM salary_withdrawals',
        )
        .get();
    final wdMap = {
      for (final r in wdAFTER)
        r.read<String>('local_uuid'): r.readNullable<String>('employee_uuid'),
    };
    expect(wdMap['wd-a'], 'uuid-aaaa'); // مُرْدَم من FK المحلي
    expect(wdMap['wd-orphan'], isNull); // يتيم — محفوظ بلا تخمين
    expect(wdMap.length, 2); // لا حذف — كل الصفوف باقية
    expect(wdOrphanBefore.read<int>('n'), 1);

    final cyRow = await db
        .customSelect(
          "SELECT employee_uuid FROM salary_cycles WHERE local_uuid = 'cy-b'",
        )
        .getSingle();
    expect(cyRow.readNullable<String>('employee_uuid'), 'uuid-bbbb');

    final spRow = await db
        .customSelect(
          "SELECT employee_uuid FROM salary_payments WHERE local_uuid = 'sp-b'",
        )
        .getSingle();
    expect(
      spRow.readNullable<String>('employee_uuid'),
      'uuid-bbbb',
    ); // عبر دورتها
  });

  // ═══════════════════════════════════════════════════════════
  //  3) toJson يرسل المفتاح المستقر (كل الجداول الثلاثة)
  // ═══════════════════════════════════════════════════════════
  test('toJson يحمل employee_uuid على السلك للجداول الثلاثة', () async {
    final empA = await seedEmployee('uuid-aaaa');

    // سحوبة عبر المستودع (المسار الإنتاجي الحقيقي)
    await swRepo.createFromExpense(
      expenseId: 1,
      employeeId: empA,
      reason: 'exp_1',
      amount: 70,
      date: '2026-09-19',
    );
    // localUuid يُولَّد — ابحث بالموظف
    final wdByEmp = await (db.select(
      db.salaryWithdrawals,
    )..where((t) => t.employeeId.equals(empA))).getSingle();
    expect(
      wdByEmp.employeeUuid,
      'uuid-aaaa',
      reason: 'العمود المحلي يُملأ عند الإنشاء (migration 68 + المستودع)',
    );

    final wdAdapter = SalaryWithdrawalsAdapter(resolver);
    final wdJson = wdAdapter.toJson(wdByEmp, src: Source.appwrite);
    expect(wdJson['employeeUuid'], 'uuid-aaaa');
    final wdJsonDrive = wdAdapter.toJson(wdByEmp, src: Source.drive);
    expect(wdJsonDrive['employee_uuid'], 'uuid-aaaa');

    // دورة
    final cycleId = await db
        .into(db.salaryCycles)
        .insert(
          SalaryCyclesCompanion.insert(
            employeeId: empA,
            cycleKey: 'cy-1',
            localUuid: 'cy-1',
            createdAt: 1700000000,
            updatedAt: 1700000000,
            lastModified: 1700000000,
            employeeUuid: const d.Value('uuid-aaaa'),
          ),
        );
    final cyRow = await db.select(db.salaryCycles).getSingle();
    final cyAdapter = SalaryCyclesAdapter(resolver);
    expect(
      cyAdapter.toJson(cyRow, src: Source.appwrite)['employeeUuid'],
      'uuid-aaaa',
    );
    expect(
      cyAdapter.toJson(cyRow, src: Source.drive)['employee_uuid'],
      'uuid-aaaa',
    );

    // دفعة
    await db
        .into(db.salaryPayments)
        .insert(
          SalaryPaymentsCompanion.insert(
            cycleId: cycleId,
            paymentDateIso: '2026-09-19',
            localUuid: 'sp-1',
            createdAt: 1700000000,
            updatedAt: 1700000000,
            lastModified: 1700000000,
            employeeUuid: const d.Value('uuid-aaaa'),
          ),
        );
    final spRow = await db.select(db.salaryPayments).getSingle();
    final spAdapter = SalaryPaymentsAdapter(resolver);
    expect(
      spAdapter.toJson(spRow, src: Source.appwrite)['employeeUuid'],
      'uuid-aaaa',
    );
    expect(
      spAdapter.toJson(spRow, src: Source.drive)['employee_uuid'],
      'uuid-aaaa',
    );
  });

  // ═══════════════════════════════════════════════════════════
  //  4) fromJson يخزن القادم ويستكمل من الموظف المحلول
  // ═══════════════════════════════════════════════════════════
  test(
    'fromJson: الحمولة تحمل uuid → يُخزن؛ لا تحمله → من الموظف المحلول',
    () async {
      final empA = await seedEmployee('uuid-aaaa');
      // الحمولة البعيدة تحمل employeeId = serverId الموظف (دلالة جهاز
      // المصدر — نفس عقد resolveRefs) وليس id المحلي
      await (db.update(db.employees)..where((t) => t.id.equals(empA))).write(
        const EmployeesCompanion(serverId: d.Value(77)),
      );
      final adapter = SalaryWithdrawalsAdapter(resolver);

      // (أ) الحمولة تحمل المفتاح صراحة
      final refsA = await adapter.resolveRefs(db, {
        'localUuid': 'wd-x',
        'employeeUuid': 'uuid-aaaa',
        'amount': 10,
        'withdrawDate': '2026-09-19',
      }, src: Source.appwrite);
      final compA = adapter.fromJson(
        {
          'localUuid': 'wd-x',
          'employeeUuid': 'uuid-aaaa',
          'employeeId': empA,
          'amount': 10,
          'withdrawDate': '2026-09-19',
        },
        src: Source.appwrite,
        refs: refsA,
      );
      expect(compA.employeeUuid.value, 'uuid-aaaa');

      // (ب) الحمولة بلا مفتاح — يُستكمل من الموظف المحلول محلياً
      final payloadB = {
        'localUuid': 'wd-y',
        'employeeId': 77,
        'amount': 20,
        'withdrawDate': '2026-09-19',
      };
      final refsB = await adapter.resolveRefs(
        db,
        payloadB,
        src: Source.appwrite,
      );
      final compB = adapter.fromJson(
        payloadB,
        src: Source.appwrite,
        refs: refsB,
      );
      expect(
        compB.employeeUuid.value,
        'uuid-aaaa',
        reason: 'resolveRefs ينبش uuid الموظف المحلي عند غيابه من الحمولة',
      );

      // (ج) PayloadNormalizer: employeeUuid → employee_uuid (عقد سلك D1)
      final wire = PayloadNormalizer.normalize({
        'employeeUuid': 'uuid-aaaa',
        'localUuid': 'wd-z',
        'withdrawDate': '2026-09-19',
      });
      expect(wire['employee_uuid'], 'uuid-aaaa');
      expect(wire.containsKey('employeeUuid'), false);
    },
  );

  // ═══════════════════════════════════════════════════════════
  //  5) الدورة والدفعة: الاستنباط من الدورة عند السحب
  // ═══════════════════════════════════════════════════════════
  test(
    'salary_payments: fromJson يستنبط uuid الموظف من دورته المحلولة',
    () async {
      final empA = await seedEmployee('uuid-aaaa');
      final cycleId = await db
          .into(db.salaryCycles)
          .insert(
            SalaryCyclesCompanion.insert(
              employeeId: empA,
              cycleKey: 'cy-1',
              localUuid: 'cy-1',
              createdAt: 1700000000,
              updatedAt: 1700000000,
              lastModified: 1700000000,
              employeeUuid: const d.Value('uuid-aaaa'),
            ),
          );
      // الحمولة البعيدة تحمل cycleId = serverId الدورة (دلالة جهاز المصدر)
      await (db.update(db.salaryCycles)..where((t) => t.id.equals(cycleId)))
          .write(const SalaryCyclesCompanion(serverId: d.Value(88)));

      final adapter = SalaryPaymentsAdapter(resolver);
      final payload = {
        'localUuid': 'sp-x',
        'cycleId': 88,
        'amount': 30,
        'paymentDateIso': '2026-09-19',
      };
      final refs = await adapter.resolveRefs(db, payload, src: Source.appwrite);
      final comp = adapter.fromJson(payload, src: Source.appwrite, refs: refs);
      expect(
        comp.employeeUuid.value,
        'uuid-aaaa',
        reason: 'الدفعة ترث uuid موظف دورتها — عقد migration 68',
      );
    },
  );
}
