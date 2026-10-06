// test/unit/financial_links_g1_g2_test.dart
//
// ✅ (G-1 / G-2 / P1-3 / P2-7 — 2026-10-06): إثبات المخاطر المتبقية.
//
//   • G-1: `salary_payments.cycle_uuid` — رابط دورة **دائم** يُكتب من دليل
//     (UUID ورد في الحمولة أو مفتاح أجنبي محلي سليم)، ويُستخدم عند الرفع
//     بدل الاعتماد على وجود صف الدورة لحظة الرفع.
//   • G-2: `salary_carry_over_logs.from_cycle_id/to_cycle_id` — رابطتا
//     الدورتين بمطابقة حتمية واحدة فقط (صفر أو أكثر ⇒ لا كتابة).
//   • P1-3: ازدواج مرشّحي الرقم البعيد ⇒ **لا ربط** (مراجعة بشرية) بدل
//     اختيار «الأول» بصمت.
//   • P2-7: تصنيف المرايا بحسب مستوى الإثبات + منع الربط الرقمي بلا إثبات
//     نفس الجهاز الكاتب.
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/adapters/id_resolver.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/salary_mirror_matcher.dart';
import 'package:marina_hotel_mobile/services/sync_core/financial_link_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  const now = 1700000000;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // نفس ما يفعله beforeOpen في القاعدة الحقيقية (عمود إضافي بترحيل خام).
    await db.customStatement(
      'ALTER TABLE salary_payments ADD COLUMN cycle_uuid TEXT',
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> employee(String uuid) => db
      .into(db.employees)
      .insert(
        EmployeesCompanion.insert(
          localUuid: uuid,
          createdAt: now,
          updatedAt: now,
          lastModified: now,
          name: 'موظف $uuid',
          basicSalary: 100,
          status: 'active',
        ),
      );

  Future<int> cycle({
    required int empId,
    required String uuid,
    required String key,
    String? start,
  }) => db
      .into(db.salaryCycles)
      .insert(
        SalaryCyclesCompanion.insert(
          localUuid: uuid,
          createdAt: now,
          updatedAt: now,
          lastModified: now,
          employeeId: empId,
          cycleKey: key,
          hotelDayStart: d.Value(start),
          employeeUuid: d.Value('emp-1'),
        ),
      );

  Future<int> payment({
    required int cycleId,
    required String uuid,
    String? cycleUuid,
  }) async {
    final id = await db
        .into(db.salaryPayments)
        .insert(
          SalaryPaymentsCompanion.insert(
            localUuid: uuid,
            createdAt: now,
            updatedAt: now,
            lastModified: now,
            cycleId: cycleId,
            amount: const d.Value(500),
            paymentDateIso: '2026-10-01',
          ),
        );
    if (cycleUuid != null) {
      await db.customStatement(
        'UPDATE salary_payments SET cycle_uuid = ? WHERE id = ?',
        [cycleUuid, id],
      );
    }
    return id;
  }

  Future<String?> storedCycleUuid(String paymentUuid) async {
    final row = await db
        .customSelect(
          'SELECT cycle_uuid AS c FROM salary_payments WHERE local_uuid = ?',
          variables: [d.Variable.withString(paymentUuid)],
        )
        .getSingle();
    return row.data['c'] as String?;
  }

  group('G-1 — رابط الدفعة ↔ الدورة دائم', () {
    test('يُثبّت من المفتاح الأجنبي المحلي ويكتب مرة واحدة', () async {
      final emp = await employee('emp-1');
      final c = await cycle(empId: emp, uuid: 'cyc-A', key: '2026-10');
      await payment(cycleId: c, uuid: 'pay-A');

      final links = FinancialLinkStore(db);
      final resolved = await links.stampPaymentCycleIfMissing(
        paymentLocalUuid: 'pay-A',
        fallbackCycleLocalId: c,
      );

      expect(resolved, 'cyc-A');
      expect(await storedCycleUuid('pay-A'), 'cyc-A');

      // إعادة الاستدعاء لا تُغيّر القيمة (لا دهس بقيمة أضعف).
      final again = await links.stampPaymentCycleIfMissing(
        paymentLocalUuid: 'pay-A',
        preferredCycleUuid: 'cyc-OTHER',
      );
      expect(again, 'cyc-A');
      expect(await storedCycleUuid('pay-A'), 'cyc-A');
    });

    test('UUID الوارد في الحمولة (هوية معلنة) يتقدّم على المفتاح الرقمي',
        () async {
      final emp = await employee('emp-1');
      final c = await cycle(empId: emp, uuid: 'cyc-local', key: '2026-10');
      await payment(cycleId: c, uuid: 'pay-B');

      final links = FinancialLinkStore(db);
      final resolved = await links.stampPaymentCycleIfMissing(
        paymentLocalUuid: 'pay-B',
        preferredCycleUuid: 'cyc-from-payload',
        fallbackCycleLocalId: c,
      );
      expect(resolved, 'cyc-from-payload');
    });

    test('لا دليل ⇒ لا كتابة (يبقى فارغاً ويظهر في المراجعة)', () async {
      final emp = await employee('emp-1');
      final c = await cycle(empId: emp, uuid: 'cyc-A', key: '2026-10');
      await payment(cycleId: c, uuid: 'pay-C');

      final links = FinancialLinkStore(db);
      final resolved = await links.stampPaymentCycleIfMissing(
        paymentLocalUuid: 'pay-C',
      );
      expect(resolved, isNull);
      expect(await storedCycleUuid('pay-C'), isNull);
    });

    test('المشي المحدود يثبّت كل رابط مُثبت بـ FK ويعدّ الملخص', () async {
      final emp = await employee('emp-1');
      final c1 = await cycle(empId: emp, uuid: 'cyc-A', key: '2026-10');
      final c2 = await cycle(empId: emp, uuid: 'cyc-B', key: '2026-11');
      await payment(cycleId: c1, uuid: 'pay-1');
      await payment(cycleId: c2, uuid: 'pay-2');
      await payment(cycleId: c1, uuid: 'pay-3', cycleUuid: 'cyc-A');

      final links = FinancialLinkStore(db);
      final stamped = await links.stampProvablePaymentCycles();

      expect(stamped, 2);
      expect(await storedCycleUuid('pay-1'), 'cyc-A');
      expect(await storedCycleUuid('pay-2'), 'cyc-B');

      final summary = await links.paymentCycleLinkSummary();
      expect(summary['payments_total'], 3);
      expect(summary['payments_cycle_linked'], 3);
      expect(summary['payments_cycle_unlinked'], 0);
    });
  });

  group('G-2 — رابطتا دورتَي سجل الترحيل', () {
    test('مطابقة واحدة ببداية اليوم الفندقي ⇒ UUID الدورة', () async {
      final emp = await employee('emp-1');
      await cycle(
        empId: emp,
        uuid: 'cyc-prev',
        key: '2026-09',
        start: '2026-09-05',
      );
      final links = FinancialLinkStore(db);
      expect(
        await links.cycleUuidForPeriod(
          employeeId: emp,
          cycleStartIsoDate: '2026-09-05',
          monthKey: '2026-09',
        ),
        'cyc-prev',
      );
    });

    test('غياب بداية اليوم ⇒ مطابقة مفتاح الشهر (حين تكون فريدة)', () async {
      final emp = await employee('emp-1');
      await cycle(empId: emp, uuid: 'cyc-oct', key: '2026-10');
      final links = FinancialLinkStore(db);
      expect(
        await links.cycleUuidForPeriod(
          employeeId: emp,
          cycleStartIsoDate: '2026-10-05',
          monthKey: '2026-10',
        ),
        'cyc-oct',
      );
    });

    test('أكثر من مرشّح ⇒ لا ربط (لا تخمين — البند 12)', () async {
      final emp = await employee('emp-1');
      // مفتاح الشهر فريد لكل موظف (UNIQUE employee_id+cycle_key)، فالازدواج
      // الواقعي يقع على بداية اليوم الفندقي — درسان مختلفان بنفس البداية.
      await cycle(
        empId: emp,
        uuid: 'cyc-a',
        key: '2026-10',
        start: '2026-10-05',
      );
      await cycle(
        empId: emp,
        uuid: 'cyc-b',
        key: '2026-10-b',
        start: '2026-10-05',
      );
      final links = FinancialLinkStore(db);
      expect(
        await links.cycleUuidForPeriod(
          employeeId: emp,
          cycleStartIsoDate: '2026-10-05',
          monthKey: '2026-10',
        ),
        isNull,
      );
    });

    test('صفر مرشّح ⇒ لا ربط', () async {
      final emp = await employee('emp-1');
      final links = FinancialLinkStore(db);
      expect(
        await links.cycleUuidForPeriod(
          employeeId: emp,
          cycleStartIsoDate: '2026-10-05',
          monthKey: '2026-10',
        ),
        isNull,
      );
    });
  });

  group('P1-3 — ازدواج الرقم البعيد ⇒ مراجعة لا اختيار', () {
    test('موظفان بنفس serverId ونفس الجهاز ⇒ لا ربط من السحابة', () async {
      for (final uuid in ['emp-x1', 'emp-x2']) {
        final id = await employee(uuid);
        await db.customStatement(
          "UPDATE employees SET server_id = 7, device_id = 'devA' WHERE id = ?",
          [id],
        );
      }

      final resolver = IdResolver(db);
      final resolved = await resolver.resolveEmployee(
        uuid: null,
        serverId: 7,
        localId: null,
        fromRemote: true,
        sourceDeviceId: 'devA',
      );
      expect(
        resolved,
        isNull,
        reason: 'ازدواج المرشّحين ⇒ لا ربط (يُعلَّق السجل للمراجعة)',
      );

      // المطابقة المحلية (ليست من السحابة) تبقى حتمية كما كانت.
      final local = await resolver.resolveEmployee(
        uuid: null,
        serverId: 7,
        localId: null,
        fromRemote: false,
      );
      expect(local, isNotNull);
    });
  });

  group('P2-7 — تصنيف المرايا بالدليل', () {
    const candidateBase = MirrorExpenseCandidate(
      id: 51,
      serverId: 962,
      expenseType: 'سحب راتب',
      amount: 5000,
      date: '2026-08-02',
      hotelDayKey: '2026-08-02',
      relatedId: 9,
      localUuid: 'exp-uuid-51',
      deviceId: 'devB',
    );

    test('رابط الهوية ⇒ identity (حاسم)', () {
      expect(
        SalaryMirrorMatcher.classify(
          expenseUuid: 'exp-uuid-51',
          expenseId: null,
          reason: null,
          amount: 5000,
          hotelDayKey: '2026-08-02',
          withdrawDate: '2026-08-02',
          employeeId: 9,
          expenses: const [candidateBase],
        ),
        MirrorMatchLevel.identity,
      );
    });

    test('الرقم البعيد بلا إثبات الجهاز ⇒ لا ربط رقمي (يسقط للمطابقة)', () {
      final level = SalaryMirrorMatcher.classify(
        expenseId: null,
        reason: 'exp_962',
        amount: 5000,
        hotelDayKey: '2026-08-02',
        withdrawDate: '2026-08-02',
        employeeId: 9,
        expenses: const [candidateBase],
        // لا sourceDeviceId ⇒ لا إثبات
      );
      expect(level, MirrorMatchLevel.dataMatch);
      expect(level.isHeuristic, isTrue, reason: 'يجب أن يُعلَّم كحُكمي');
    });

    test('الرقم البعيد مع نفس الجهاز الكاتب ⇒ provenNumeric', () {
      expect(
        SalaryMirrorMatcher.classify(
          expenseId: null,
          reason: 'exp_962',
          amount: 5000,
          hotelDayKey: '2026-08-02',
          withdrawDate: '2026-08-02',
          employeeId: 9,
          expenses: const [candidateBase],
          sourceDeviceId: 'devB',
        ),
        MirrorMatchLevel.provenNumeric,
      );
    });

    test('جهاز مختلف ⇒ لا ربط رقمي (ولا يُربط بمصروف جهاز آخر)', () {
      final level = SalaryMirrorMatcher.classify(
        expenseId: null,
        reason: 'exp_962',
        amount: 5000,
        hotelDayKey: '2026-08-02',
        withdrawDate: '2026-08-02',
        employeeId: 9,
        expenses: const [candidateBase],
        sourceDeviceId: 'devA',
      );
      expect(level.isMirror, isTrue);
      expect(level, MirrorMatchLevel.dataMatch);
    });

    test('السحب المباشر ليس مرآة أبداً', () {
      expect(
        SalaryMirrorMatcher.classify(
          expenseId: 51,
          reason: 'direct_withdrawal_emp-1',
          amount: 5000,
          hotelDayKey: '2026-08-02',
          withdrawDate: '2026-08-02',
          employeeId: 9,
          expenses: const [candidateBase],
        ),
        MirrorMatchLevel.none,
      );
    });

    test('resolveLinkedExpenseId يحترم إثبات الجهاز', () {
      expect(
        SalaryMirrorMatcher.resolveLinkedExpenseId(
          expenseId: null,
          reason: 'exp_962',
          expenses: const [candidateBase],
          sourceDeviceId: 'devB',
        ),
        51,
      );
      expect(
        SalaryMirrorMatcher.resolveLinkedExpenseId(
          expenseId: null,
          reason: 'exp_962',
          expenses: const [candidateBase],
          sourceDeviceId: 'devA',
        ),
        isNull,
      );
    });
  });
}
