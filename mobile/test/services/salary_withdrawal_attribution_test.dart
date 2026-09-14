// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/utils/device_attribution.dart';

/// ✅ اختبارات إسناد سحوبات الرواتب لمسجّلها وجهازها (2026-09-14).
///
/// الخلفية — شكوى «سجل 19,000 للأورمو محمد بتاريخ 2026/09/13 ظهر في
/// التقرير مع أني لم أسجّله»:
/// - التشخيص السحابي أثبت أن السجل حقيقي أُنشئ يدوياً 22:59 مساءً من
///   جهاز BRC-NX1، لكن التقرير لم يكن يعرض أي إسناد (من/أي جهاز)
///   وكان يعرض وقتاً وهمياً 00:00 لتاريخ نصي بلا وقت.
/// - الإصلاح: وسم recorderName + deviceId عند الإنشاء، ورفعهما في حقل
///   name السحابي، وقراءتهما عائدين في المحول، وتلميح الجهاز من
///   vectorClock للسجلات القديمة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('deviceHintFromVectorClock', () {
    test('مفتاح كامل marina_model_short يُعرض model (short)', () {
      expect(
        deviceHintFromVectorClock('{"marina_HNBRC-M1_be06acca":1}'),
        'HNBRC-M1 (be06acca)',
      );
    });

    test('مفتاح بلا بادئة marina_ يُعرض كما هو مع القصور', () {
      expect(
        deviceHintFromVectorClock('{"dandelion_308df672":2}'),
        'dandelion (308df672)',
      );
    });

    test('ساعة اتجاهية فارغة/null/فاسدة → null', () {
      expect(deviceHintFromVectorClock(null), isNull);
      expect(deviceHintFromVectorClock(''), isNull);
      expect(deviceHintFromVectorClock('{}'), isNull);
      expect(deviceHintFromVectorClock('not-json'), isNull);
      expect(deviceHintFromVectorClock('[]'), isNull);
    });

    test('مفتاح بلا shortId يُرجع النموذج فقط', () {
      expect(deviceHintFromVectorClock('{"marina_baremodel":1}'), 'baremodel');
    });
  });

  group('إسناد السحوبات عند الإنشاء (createFromExpense)', () {
    late AppDatabase db;
    late SalaryWithdrawalsRepository repo;
    late int employeeId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = SalaryWithdrawalsRepository(db);
      employeeId = await db
          .into(db.employees)
          .insert(
            const EmployeesCompanion(
              name: d.Value('الاورمو محمد منظف'),
              basicSalary: d.Value(100000),
              status: d.Value('active'),
              hireDate: d.Value('2026-01-01'),
              localUuid: d.Value('4d5b6752-e6c5-4500-a2f2-d1d62f77e49e'),
              createdAt: d.Value(1000),
              updatedAt: d.Value(1000),
              lastModified: d.Value(1000),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'السحب المباشر يخزن recorderName + deviceId محلياً وin outbox',
      () async {
        final id = await repo.createFromExpense(
          expenseId: 0, // سحب مباشر
          employeeId: employeeId,
          reason: 'direct_withdrawal_4d5b6752-e6c5-4500-a2f2-d1d62f77e49e',
          amount: 19000,
          date: '2026-09-13',
          hotelDayKey: '2026-09-13',
          withdrawalType: 'سحب راتب',
          recorderName: 'المدير',
        );

        final row = await (db.select(
          db.salaryWithdrawals,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(row.recorderName, 'المدير');
        // هوية الجهاز غير مهيأة في الاختبار → سلسلة فارغة (وليس crash)
        expect(row.deviceId, '');

        // عنصر الـ outbox يحمل الإسناد ليصل للسحابة في حقل name
        final outboxRow = await (db.select(
          db.outbox,
        )..where((t) => t.localUuid.equals(row.localUuid))).getSingle();
        expect(outboxRow.entity, 'salary_withdrawals');
        expect(outboxRow.op, 'create');
        expect(outboxRow.payload, contains('recorderName'));
        expect(outboxRow.payload, contains('المدير'));
        expect(outboxRow.payload, contains('deviceId'));
      },
    );

    test('بلا recorderName → العمود null وبلا مفتاح في الحمولة', () async {
      final id = await repo.createFromExpense(
        expenseId: 0,
        employeeId: employeeId,
        reason: 'direct_withdrawal_x',
        amount: 1000,
        date: '2026-09-13',
        withdrawalType: 'سحب راتب',
      );

      final row = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.recorderName, isNull);

      final outboxRow = await (db.select(
        db.outbox,
      )..where((t) => t.localUuid.equals(row.localUuid))).getSingle();
      expect(outboxRow.payload, isNot(contains('recorderName')));
    });

    test('مرآة المصروف (saveFromExpense) تُوسم deviceId أيضاً', () async {
      await repo.saveFromExpense(
        expenseId: 77,
        employeeId: employeeId,
        action: 'سحب راتب',
        amount: 5000,
        date: '2026-09-13',
        hotelDayKey: '2026-09-13',
      );

      final row = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.reason.equals('exp_77'))).getSingle();
      expect(row.deviceId, '');
      expect(row.reason, 'exp_77');
    });
  });

  group('محوّل السحوبات (سحابة ↔ محلي)', () {
    test('fromJson يقرأ recorderName من حقل name السحابي', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      // الموظف أولاً (FK constraint)
      final employeeId = await db
          .into(db.employees)
          .insert(
            const EmployeesCompanion(
              name: d.Value('الاورمو محمد منظف'),
              basicSalary: d.Value(100000),
              status: d.Value('active'),
              hireDate: d.Value('2026-01-01'),
              localUuid: d.Value('4d5b6752-e6c5-4500-a2f2-d1d62f77e49e'),
              createdAt: d.Value(1000),
              updatedAt: d.Value(1000),
              lastModified: d.Value(1000),
            ),
          );
      // يُختبر عبر SQL مباشر: العمود موجود في المخطط بعد migration 66
      await db.customStatement(
        "INSERT INTO salary_withdrawals (local_uuid, employee_id, amount, "
        "withdraw_date, created_at, updated_at, last_modified, device_id, "
        "recorder_name) VALUES ('wd-rec-1', $employeeId, 19000, "
        "'2026-09-13', 1789329587, 1789329587, 1789329587, "
        "'marina_HNBRC-M1_be06acca', 'المدير')",
      );
      final row = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.localUuid.equals('wd-rec-1'))).getSingle();
      expect(row.recorderName, 'المدير');
      expect(row.deviceId, 'marina_HNBRC-M1_be06acca');
    });
  });
}
