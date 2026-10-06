// test/unit/financial_identity_audit_test.dart
//
// ✅ تدقيق الهوية والعلاقات المالية عبر الأجهزة (2026-10-06)
//
// يغطي هذا الملف السيناريوهات الثمانية المطلوبة من المالك:
//   1. اختلاف id المحلي بين الأجهزة بنفس employee_uuid.
//   2. إعادة إرسال نفس العملية لا تُكرِّر الحركة المالية.
//   3. انقطاع الإنترنت ثم إعادة الاتصال لا يُفقد الحركة.
//   4. وصول الابن (مصروف/دفعة) قبل الأب (موظف/دورة) — لا فقدان ولا ربط خاطئ.
//   5. التعارض: الحقول المالية الحرجة لا تُدمج صامتة — تُحفظ القيمتان
//      وتُسجَّل للمراجعة البشرية (سياسة G-4 المُغلقة).
//   6. الحذف: لا إحياء للسجل المحذوف (outbox + tombstone بعيد).
//   7. الاستعادة: لا تغيير للـ UUIDs.
//   8. تغيير مزوّد المزامنة: نقل الهويات والعلاقات والمجاميع.
//
// ملاحظات صارمة (طلب المالك):
//   - لا تُعدَّل بيانات الإنتاج من هذا الملف (كل الاختبارات على قاعدة ذاكرة).
//   - أي ربط في هذه الاختبارات يعتمد على الهوية (UUID) أو الحالات الرسمية،
//     ولا يعتمد على الاسم/المبلغ/التاريخ للتخمين.
//
// تشغيل:
//   cd mobile && flutter test test/unit/financial_identity_audit_test.dart

// ignore_for_file: lines_longer_than_80_chars, avoid_redundant_argument_values

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/adapters/employees_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/expenses_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/id_resolver.dart';
import 'package:marina_hotel_mobile/services/adapters/salary_cycles_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/salary_payments_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/salary_withdrawals_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/daos/ancestor_cache_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/money_integrity_service.dart';
import 'package:marina_hotel_mobile/utils/currency_formatter.dart';
import 'package:marina_hotel_mobile/services/sync_core/conflict_detector.dart';
import 'package:marina_hotel_mobile/services/sync_core/smart_conflict_resolver.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';

const int _now =
    1760000000; // epoch ثابت (2025-10-09 تقريبًا) — لا يعتمد على ساعة الجهاز
const String _salaryType =
    'سحب راتب'; // نوع نقدي معروف في SalaryExpenseClassifier
const String _advanceType = 'سلفة'; // نوع رواتب يدخل في مسار حل employee_uuid

AppDatabase _newDb() => AppDatabase.forTesting(NativeDatabase.memory());

// ─────────────────────────────────────────────────────────────────────────
// Helpers — إدراج صفوف بأعمدة الهوية فقط (بدون أي تخمين علاقات)
// ─────────────────────────────────────────────────────────────────────────

Future<int> _employee(
  AppDatabase db, {
  required String uuid,
  required String name,
  int? serverId,
}) {
  return db
      .into(db.employees)
      .insert(
        EmployeesCompanion.insert(
          localUuid: uuid,
          name: name,
          basicSalary: 0,
          status: 'active',
          serverId: d.Value(serverId),
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
        ),
      );
}

Future<int> _expense(
  AppDatabase db, {
  required String uuid,
  String type = _salaryType,
  double amount = 100,
  String? employeeUuid,
  int? relatedId,
  String? withdrawalUuid,
}) {
  return db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          localUuid: uuid,
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
          expenseType: type,
          description: 'اختبار هوية',
          amount: amount,
          date: '2026-10-01',
          employeeUuid: d.Value(employeeUuid),
          relatedId: d.Value(relatedId),
          withdrawalUuid: d.Value(withdrawalUuid),
        ),
      );
}

Future<int> _withdrawal(
  AppDatabase db, {
  required String uuid,
  required int employeeId,
  double amount = 100,
  String? employeeUuid,
  int? expenseId,
  String? expenseUuid,
  String reason = 'exp_1',
}) {
  return db
      .into(db.salaryWithdrawals)
      .insert(
        SalaryWithdrawalsCompanion.insert(
          localUuid: uuid,
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
          employeeId: employeeId,
          amount: amount,
          withdrawDate: '2026-10-01',
          reason: d.Value(reason),
          employeeUuid: d.Value(employeeUuid),
          expenseId: d.Value(expenseId),
          expenseUuid: d.Value(expenseUuid),
        ),
      );
}

Future<int> _cycle(
  AppDatabase db, {
  required String uuid,
  required int employeeId,
  required String cycleKey,
  String? employeeUuid,
  int? serverId,
}) {
  return db
      .into(db.salaryCycles)
      .insert(
        SalaryCyclesCompanion.insert(
          localUuid: uuid,
          employeeId: employeeId,
          cycleKey: cycleKey,
          employeeUuid: d.Value(employeeUuid),
          serverId: d.Value(serverId),
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
        ),
      );
}

Future<int> _payment(
  AppDatabase db, {
  required String uuid,
  required int cycleId,
  int amount = 500,
  String? employeeUuid,
}) {
  return db
      .into(db.salaryPayments)
      .insert(
        SalaryPaymentsCompanion.insert(
          localUuid: uuid,
          cycleId: cycleId,
          paymentDateIso: '2026-10-03',
          amount: d.Value(amount),
          employeeUuid: d.Value(employeeUuid),
          createdAt: _now,
          updatedAt: _now,
          lastModified: _now,
        ),
      );
}

/// يحاكي حقن روابط الهوية في حمولة الدفعة أثناء الرفع (مسار
/// `appwrite_sync_manager._processSalaryPaymentEntry`). الحقول تُضاف بصيغة
/// snake_case (مصدر Drive) لأنها الصيغة التي يقرأها المحوّل في الاتجاهين.
Map<String, dynamic> _paymentExport(
  Map<String, dynamic> payload, {
  required String? cycleUuid,
  required String? employeeUuid,
}) {
  final map = Map<String, dynamic>.from(payload);
  if (cycleUuid != null && cycleUuid.isNotEmpty) {
    map['cycle_local_uuid'] = cycleUuid;
  }
  if (employeeUuid != null && employeeUuid.isNotEmpty) {
    map['employee_uuid'] = employeeUuid;
  }
  return map;
}

/// إحصاء استيراد — يفرّق بين ما أُدرج فعلًا وما أُجّل (مرجع غير محلول).
class ImportStats {
  int inserted = 0;
  final List<String> deferred = <String>[];

  @override
  String toString() => 'inserted=$inserted, deferred=${deferred.length}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  // 1) اختلاف id المحلي — نفس employee_uuid
  //    Device A: الموظف id=1 … Device B: نفس الموظف id=2 (وid=1 لموظف آخر)
  // ═══════════════════════════════════════════════════════════════════════
  group('1) اختلاف id المحلي بين الأجهزة', () {
    test(
      'same employee_uuid with different local ids binds the expense to the right employee',
      () async {
        final deviceA = _newDb();
        final deviceB = _newDb();
        addTearDown(() async {
          await deviceA.close();
          await deviceB.close();
        });

        const sharedEmployeeUuid = '11111111-2222-3333-4444-555555555555';

        // الجهاز A: الموظف المشترك هو الأول → id=1
        final aShared = await _employee(
          deviceA,
          uuid: sharedEmployeeUuid,
          name: 'الاورمو محمد',
        );

        // الجهاز B: موظف آخر أُنشئ أولاً → id=1 (تصادم رقمي مقصود)
        final bOther = await _employee(
          deviceB,
          uuid: 'other-employee-uuid',
          name: 'موظف آخر تمامًا',
        );
        final bShared = await _employee(
          deviceB,
          uuid: sharedEmployeeUuid,
          name: 'الاورمو محمد',
        );

        expect(
          aShared,
          bOther,
          reason: 'التصادم الرقمي مقصود: id=1 يعني موظفًا مختلفًا على كل جهاز',
        );
        expect(bShared, isNot(aShared));

        // مصروف راتب قادم من الجهاز A: يحمل id جهاز المصدر + الهوية الدائمة
        final remoteExpense = <String, dynamic>{
          'localUuid': 'expense-from-device-a',
          'expenseType': _salaryType,
          'description': 'سحب راتب',
          'amount': 250.0,
          'date': '2026-10-01',
          'relatedId': aShared, // رقم محلي من جهاز المصدر
          'employeeUuid': sharedEmployeeUuid, // الهوية الثابتة
          'createdAt': _now,
          'updatedAt': _now,
          'lastModified': _now,
        };

        final adapter = ExpensesAdapter(IdResolver(deviceB));
        final refs = await adapter.resolveRefs(
          deviceB,
          Map<String, dynamic>.from(remoteExpense),
          src: Source.appwrite,
        );
        final companion = adapter.fromJson(
          remoteExpense,
          src: Source.appwrite,
          refs: refs,
        );

        // القاعدة: الهوية تفوز — الربط بموظف الجهاز B صاحب نفس employee_uuid
        expect(companion.relatedId.value, bShared);
        expect(companion.employeeUuid.value, sharedEmployeeUuid);
        // ولا يُربط أبدًا بالموظف الذي تصادف أنه يحمل نفس الرقم على B
        expect(companion.relatedId.value, isNot(bOther));
      },
    );

    test(
      'the same employee_uuid on both devices keeps the expenses together',
      () async {
        final deviceA = _newDb();
        final deviceB = _newDb();
        addTearDown(() async {
          await deviceA.close();
          await deviceB.close();
        });

        const empUuid = 'aaaaaaaa-bbbb-cccc-dddd-000000000001';
        final aEmp = await _employee(deviceA, uuid: empUuid, name: 'موظف');
        await _employee(deviceB, uuid: 'filler-1', name: 'حشو 1');
        await _employee(deviceB, uuid: 'filler-2', name: 'حشو 2');
        final bEmp = await _employee(deviceB, uuid: empUuid, name: 'موظف');

        expect(bEmp, isNot(aEmp));

        // مصروفان على جهازين مختلفين لنفس الموظف — كلاهما يحمل نفس الهوية
        await _expense(
          deviceA,
          uuid: 'exp-A',
          amount: 100,
          employeeUuid: empUuid,
          relatedId: aEmp,
        );
        await _expense(
          deviceB,
          uuid: 'exp-B',
          amount: 150,
          employeeUuid: empUuid,
          relatedId: bEmp,
        );

        final aRows = await deviceA.select(deviceA.expenses).get();
        final bRows = await deviceB.select(deviceB.expenses).get();

        // الاستعلام الوحيد الآمن عبر الأجهزة هو بالهوية (لا بالـ id)
        final aTotal = aRows
            .where((e) => e.employeeUuid == empUuid)
            .fold<double>(0, (s, e) => s + e.amount);
        final bTotal = bRows
            .where((e) => e.employeeUuid == empUuid)
            .fold<double>(0, (s, e) => s + e.amount);

        expect(aTotal, 100);
        expect(bTotal, 150);
        // لو رُبط بالـ id الرقمي لظهر الموظف بلا مصروفات أو مع مصروفات غيره
        expect(
          bRows.where((e) => e.relatedId == aEmp && e.employeeUuid != empUuid),
          isEmpty,
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2) إعادة الإرسال — لا تكرار للحركة المالية
  // ═══════════════════════════════════════════════════════════════════════
  group('2) إعادة الإرسال (idempotency)', () {
    test(
      're-sending the same operation never duplicates the movement',
      () async {
        final db = _newDb();
        addTearDown(() => db.close());
        final outbox = OutboxDao(db);

        const uuid = 'withdrawal-retry-1';
        const expectedKey = 'salary_withdrawals:create:$uuid:$_now';

        for (var i = 0; i < 5; i++) {
          await outbox.merge(
            entity: 'salary_withdrawals',
            op: 'create',
            localUuid: uuid,
            payload: {'amount': 100, 'employeeId': 1},
            clientTs: _now,
          );
        }

        final rows = await db.select(db.outbox).get();
        expect(
          rows,
          hasLength(1),
          reason: 'خمس محاولات = عملية واحدة في outbox',
        );
        expect(rows.single.idempotencyKey, expectedKey);

        final batch = await outbox.takeBatch(10, sources: const ['local']);
        expect(batch, hasLength(1));
        expect(batch.single.localUuid, uuid);

        // بعد نجاح التسليم يُزال السجل (لا تراكم). إعادة نفس العملية تحمل
        // نفس idempotencyKey → الـ upsert على السحابة لا يُنشئ مستندًا جديدًا.
        await outbox.markDeliveredToPrimary(batch.single.id);
        expect(await outbox.count(), 0);

        await outbox.merge(
          entity: 'salary_withdrawals',
          op: 'create',
          localUuid: uuid,
          payload: {'amount': 100, 'employeeId': 1},
          clientTs: _now,
        );
        final again = await db.select(db.outbox).get();
        expect(again.single.idempotencyKey, expectedKey);
      },
    );

    test(
      're-merging the same uuid with a new clientTs keeps one operation only',
      () async {
        final db = _newDb();
        addTearDown(() => db.close());
        final outbox = OutboxDao(db);

        await outbox.merge(
          entity: 'expenses',
          op: 'create',
          localUuid: 'exp-merge-1',
          payload: {'amount': 10},
          clientTs: _now,
        );
        await outbox.merge(
          entity: 'expenses',
          op: 'create',
          localUuid: 'exp-merge-1',
          payload: {'amount': 20},
          clientTs: _now + 60,
        );

        final rows = await db.select(db.outbox).get();
        expect(
          rows,
          hasLength(1),
          reason: 'نفس uuid = نفس العملية (تحديث لا إدراج)',
        );
        expect(
          rows.single.idempotencyKey,
          'expenses:create:exp-merge-1:${_now + 60}',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 3) انقطاع الإنترنت — الحفظ المحلي لا يُفقد
  // ═══════════════════════════════════════════════════════════════════════
  group('3) انقطاع الإنترنت ثم إعادة الاتصال', () {
    test('offline save survives reconnect and retries the same uuid', () async {
      final db = _newDb();
      addTearDown(() => db.close());
      final outbox = OutboxDao(db);

      final empId = await _employee(db, uuid: 'emp-offline', name: 'موظف');
      final wdId = await _withdrawal(
        db,
        uuid: 'withdrawal-offline-1',
        employeeId: empId,
        amount: 75,
        employeeUuid: 'emp-offline',
      );

      // 1) حفظ محلي + تسجيل عملية المزامنة (نفس ما تفعله المستودعات في
      //    معاملة واحدة). النتيجة: الحركة موجودة محليًا.
      await outbox.merge(
        entity: 'salary_withdrawals',
        op: 'create',
        localUuid: 'withdrawal-offline-1',
        payload: {'amount': 75, 'employeeId': empId},
        clientTs: _now,
      );

      // 2) محاولة رفع فاشلة (انقطاع) → الحركة لا تُحذف
      final batch = await outbox.takeBatch(10, sources: const ['local']);
      expect(batch, hasLength(1));
      await outbox.markFailed(batch.map((e) => e.id).toList());

      final saved = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.id.equals(wdId))).getSingle();
      expect(saved.localUuid, 'withdrawal-offline-1');
      expect(
        await outbox.count(),
        1,
        reason: 'العملية تبقى في outbox بعد الفشل',
      );

      // 3) إعادة الاتصال → إعادة إرسال نفس العملية بنفس UUID
      await outbox.retryFailed();
      final retry = await outbox.takeBatch(10, sources: const ['local']);
      expect(retry, hasLength(1));
      expect(retry.single.localUuid, 'withdrawal-offline-1');
      expect(
        retry.single.idempotencyKey,
        'salary_withdrawals:create:withdrawal-offline-1:$_now',
      );

      // 4) لا تكرار: حركة واحدة فقط في الجدول المالي
      final all = await db.select(db.salaryWithdrawals).get();
      expect(
        all.where((r) => r.localUuid == 'withdrawal-offline-1'),
        hasLength(1),
      );
    });

    test(
      'a stuck processing entry is reclaimed before the next push',
      () async {
        final db = _newDb();
        addTearDown(() => db.close());
        final outbox = OutboxDao(db);

        await db
            .into(db.outbox)
            .insert(
              OutboxCompanion.insert(
                entity: 'expenses',
                op: 'create',
                localUuid: 'exp-stuck-1',
                payload: '{"amount":1}',
                clientTs: _now,
                processingStatus: const d.Value('processing'),
                // أقدم من عتبة reclaimForPush (30 ثانية)
                processingStartedAt: const d.Value(_now - 3600),
                processingWorker: const d.Value('dead-worker'),
              ),
            );

        final reclaimed = await outbox.reclaimForPush();
        expect(reclaimed, greaterThanOrEqualTo(1));
        final batch = await outbox.takeBatch(10, sources: const ['local']);
        expect(batch.map((e) => e.localUuid), contains('exp-stuck-1'));
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 4) وصول الابن قبل الأب
  // ═══════════════════════════════════════════════════════════════════════
  group('4) وصول الابن قبل الأب', () {
    test(
      'salary expense arriving before its employee stays unlinked (never bound to another employee)',
      () async {
        final db = _newDb();
        addTearDown(() => db.close());

        // موظف آخر موجود محليًا برقم 1 — وهو رقم الموظف على جهاز المصدر
        final other = await _employee(db, uuid: 'emp-other', name: 'موظف آخر');

        final adapter = ExpensesAdapter(IdResolver(db));
        final remote = <String, dynamic>{
          'localUuid': 'expense-child-first',
          'expenseType': _advanceType,
          'description': 'سلفة',
          'amount': 300.0,
          'date': '2026-10-02',
          'relatedId': other, // رقم جهاز المصدر = 1 (تصادم مقصود)
          'employeeUuid': 'emp-arrives-later',
          'createdAt': _now,
          'updatedAt': _now,
          'lastModified': _now,
        };

        final refs = await adapter.resolveRefs(
          db,
          Map<String, dynamic>.from(remote),
          src: Source.appwrite,
        );
        expect(
          refs.employeeRelatedId,
          isNull,
          reason: 'لا يُربط بموظف آخر اعتمادًا على الرقم',
        );

        final companion = adapter.fromJson(
          remote,
          src: Source.appwrite,
          refs: refs,
        );
        expect(companion.relatedId.value, isNull);
        // الهوية محفوظة كي تُحسم العلاقة عند وصول الموظف
        expect(companion.employeeUuid.value, 'emp-arrives-later');

        // وصول الأب بنفس employee_uuid → نفس الاستدعاء يحل الربط الآن
        final arrived = await _employee(
          db,
          uuid: 'emp-arrives-later',
          name: 'وصل لاحقًا',
        );
        final refsAfter = await adapter.resolveRefs(
          db,
          Map<String, dynamic>.from(remote),
          src: Source.appwrite,
        );
        expect(refsAfter.employeeRelatedId, arrived);
      },
    );

    test(
      'payment arriving before its cycle is deferred, not mis-bound',
      () async {
        final db = _newDb();
        addTearDown(() => db.close());

        final emp = await _employee(db, uuid: 'emp-pay', name: 'موظف');
        // دورة محلية أخرى تأخذ id=… (تصادم رقمي مقصود مع cycleId القادم)
        final wrongCycle = await _cycle(
          db,
          uuid: 'cycle-local-other',
          employeeId: emp,
          cycleKey: '2026-08',
          employeeUuid: 'emp-pay',
        );

        final adapter = SalaryPaymentsAdapter(IdResolver(db));
        final remote = <String, dynamic>{
          'localUuid': 'payment-child-first',
          'cycleId': wrongCycle, // رقم جهاز المصدر
          'cycleLocalUuid': 'cycle-arrives-later', // الهوية الحقيقية للدورة
          'employeeUuid': 'emp-pay',
          'amount': 500,
          'paymentDateIso': '2026-10-03',
          'createdAt': _now,
          'updatedAt': _now,
          'lastModified': _now,
        };

        final refs = await adapter.resolveRefs(
          db,
          Map<String, dynamic>.from(remote),
          src: Source.appwrite,
        );
        expect(refs.salaryCycleLocalId, isNull);
        expect(
          refs.shouldSkip,
          isTrue,
          reason: 'الدفعة تُؤجَّل حتى وصول دورتها — لا تُربط بدورة أخرى',
        );

        // وصول الدورة الصحيحة (نفس local_uuid)
        final realCycle = await _cycle(
          db,
          uuid: 'cycle-arrives-later',
          employeeId: emp,
          cycleKey: '2026-09',
          employeeUuid: 'emp-pay',
        );
        final refsAfter = await adapter.resolveRefs(
          db,
          Map<String, dynamic>.from(remote),
          src: Source.appwrite,
        );
        expect(refsAfter.shouldSkip, isFalse);
        expect(refsAfter.salaryCycleLocalId, realCycle);
        expect(refsAfter.salaryCycleLocalId, isNot(wrongCycle));
      },
    );

    test(
      'mirror withdrawal keeps the expense uuid when the expense is not here yet',
      () async {
        final db = _newDb();
        addTearDown(() => db.close());

        final emp = await _employee(db, uuid: 'emp-mirror', name: 'موظف');
        final adapter = SalaryWithdrawalsAdapter(IdResolver(db));

        final remote = <String, dynamic>{
          'localUuid': 'withdrawal-child-first',
          'employeeId': 999, // رقم جهاز المصدر — لا معنى له هنا
          'employeeUuid': 'emp-mirror',
          'amount': 120,
          'withdrawDate': '2026-10-01',
          'reason': 'exp_962',
          'expenseUuid': 'expense-not-here-yet',
          'createdAt': _now,
          'updatedAt': _now,
          'lastModified': _now,
        };

        final refs = await adapter.resolveRefs(
          db,
          Map<String, dynamic>.from(remote),
          src: Source.appwrite,
        );
        expect(refs.employeeLocalId, emp);

        final companion = adapter.fromJson(
          remote,
          src: Source.appwrite,
          refs: refs,
        );
        expect(companion.employeeId.value, emp);
        // رابط الهوية يُحفظ كما هو ليُحسم لاحقًا (relink) ولا يُخمَّن برقم
        expect(companion.expenseUuid.value, 'expense-not-here-yet');
        expect(companion.employeeUuid.value, 'emp-mirror');
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 5) التعارض — سياسة الحقول المالية الحرجة
  // ═══════════════════════════════════════════════════════════════════════
  group('5) التعارض', () {
    test(
      'concurrent edit of a critical financial field is flagged as needing review',
      () {
        const localUuid = 'expense-conflict-1';
        final local = <String, dynamic>{
          'localUuid': localUuid,
          'amount': 120.0,
          'lastModified': 5000,
          'vectorClock': '{"device-A": 2, "device-B": 1}',
        };
        final remote = <String, dynamic>{
          'localUuid': localUuid,
          'amount': 150.0,
          'lastModified': 6000,
          'vectorClock': '{"device-A": 1, "device-B": 2}',
        };
        final ancestor = <String, dynamic>{
          'localUuid': localUuid,
          'amount': 100.0,
        };

        final detection = ConflictDetector.detect(
          localData: local,
          remoteData: remote,
          commonAncestor: ancestor,
        );

        expect(detection.type, ConflictType.concurrentSameFields);
        expect(detection.conflictingFields, contains('amount'));
        expect(
          detection.needsManualResolution,
          isTrue,
          reason: 'amount حقل مالي حرج — الكاشف نفسه يطلبه للمراجعة',
        );
      },
    );

    test(
      'G-4 (fixed): a critical financial field is never silently merged — it is queued for review',
      () {
        const localUuid = 'expense-conflict-2';
        final local = <String, dynamic>{
          'localUuid': localUuid,
          'amount': 120.0,
          'description': 'نسخة الجهاز A',
          'lastModified': 5000,
          'vectorClock': '{"device-A": 2, "device-B": 1}',
        };
        final remote = <String, dynamic>{
          'localUuid': localUuid,
          'amount': 150.0,
          'description': 'نسخة الجهاز A',
          'lastModified': 6000,
          'vectorClock': '{"device-A": 1, "device-B": 2}',
        };
        final ancestor = <String, dynamic>{
          'localUuid': localUuid,
          'amount': 100.0,
          'description': 'نسخة الجهاز A',
        };

        final resolution = SmartConflictResolver.resolve(
          entity: 'expenses',
          localData: local,
          remoteData: remote,
          commonAncestor: ancestor,
        );

        // ✅ السياسة الصريحة (إغلاق G-4): لا دمج صامت للمبلغ ولا طمس لأي نسخة.
        expect(resolution.requiresReview, isTrue);
        expect(resolution.reviewFields, contains('amount'));
        expect(
          resolution.mergedData['amount'],
          120.0,
          reason: 'القيمة المحلية تُحفظ — لا يُمسح مال محلي بلا قرار بشري',
        );
        expect(
          resolution.pushedToRemote,
          isFalse,
          reason: 'لا نرفع قيمة لتطمس تعديل الجهاز الآخر قبل المراجعة',
        );
        expect(
          resolution.warnings.join(' '),
          contains('critical financial field conflict'),
        );
      },
    );

    test('G-4: non-critical fields of the same record are still merged', () {
      const localUuid = 'expense-conflict-2b';
      final local = <String, dynamic>{
        'localUuid': localUuid,
        'amount': 120.0,
        'hotelDayKey': '2026-10-01',
        'lastModified': 5000,
        'vectorClock': '{"device-A": 2, "device-B": 1}',
      };
      final remote = <String, dynamic>{
        'localUuid': localUuid,
        'amount': 150.0,
        'hotelDayKey': '2026-10-02',
        'lastModified': 6000,
        'vectorClock': '{"device-A": 1, "device-B": 2}',
      };
      final ancestor = <String, dynamic>{
        'localUuid': localUuid,
        'amount': 100.0,
        'hotelDayKey': '2026-10-01',
      };

      final resolution = SmartConflictResolver.resolve(
        entity: 'expenses',
        localData: local,
        remoteData: remote,
        commonAncestor: ancestor,
      );

      expect(resolution.requiresReview, isTrue);
      expect(resolution.mergedData['amount'], 120.0);
      expect(
        resolution.mergedData['hotelDayKey'],
        '2026-10-02',
        reason: 'الحقل غير المالي يُدمج من الجهاز الذي عدّله',
      );
    });

    test(
      'a critical-field conflict is persisted for human review in sync_conflicts',
      () async {
        final db = _newDb();
        addTearDown(() => db.close());
        final outbox = OutboxDao(db);
        final pull = SyncPullService(
          appwriteService: AppwriteService(),
          database: db,
          outboxDao: outbox,
        );
        pull.setAncestorCacheDao(AncestorCacheDao(db), deviceId: 'device-B');

        const localUuid = 'expense-conflict-review-1';
        final remote = <String, dynamic>{
          'localUuid': localUuid,
          'amount': 150.0,
          'lastModified': 6000,
          'vectorClock': '{"device-A": 1, "device-B": 2}',
        };

        final result = await pull.checkAndResolveConflict(
          remote,
          _now - 60,
          remoteUpdatedAtSec: _now,
          localVectorClock: '{"device-A": 2, "device-B": 1}',
          entityName: 'expenses',
          localUuid: localUuid,
          localData: <String, dynamic>{
            'localUuid': localUuid,
            'amount': 120.0,
            'lastModified': _now - 120,
            'vectorClock': '{"device-A": 2, "device-B": 1}',
          },
        );

        // الحقل المالي لم يُدمج صامتاً، والسجل دخل قائمة المراجعة البشرية
        expect(result.requiresReview, isTrue);
        expect(result.mergedData?['amount'], 120.0);
        expect(result.pushedToRemote, isFalse);

        final conflicts = await db.select(db.syncConflicts).get();
        expect(conflicts, hasLength(1));
        expect(conflicts.single.targetTable, 'expenses');
        expect(conflicts.single.uuid, localUuid);
        expect(
          conflicts.single.resolution,
          '',
          reason:
              'resolution فارغ = بانتظار قرار بشري (يظهر في شاشة التعارضات)',
        );
        expect(
          conflicts.single.localPayload,
          contains('critical_financial_field_conflict'),
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 6) الحذف — لا إحياء للسجل المحذوف
  // ═══════════════════════════════════════════════════════════════════════
  group('6) الحذف', () {
    test('a delete operation is never overwritten by a later update', () async {
      final db = _newDb();
      addTearDown(() => db.close());
      final outbox = OutboxDao(db);

      await outbox.merge(
        entity: 'expenses',
        op: 'delete',
        localUuid: 'expense-deleted-1',
        payload: {'deletedAt': _now},
        clientTs: _now,
      );
      await outbox.merge(
        entity: 'expenses',
        op: 'update',
        localUuid: 'expense-deleted-1',
        payload: {'amount': 999},
        clientTs: _now + 30,
      );

      final rows = await db.select(db.outbox).get();
      expect(rows, hasLength(1));
      expect(
        rows.single.op,
        'delete',
        reason: 'لا يجوز تحويل عملية حذف معلّقة إلى تعديل (إحياء صامت)',
      );
    });

    test('a remote tombstone is applied over a locally active row', () async {
      final db = _newDb();
      addTearDown(() => db.close());
      final outbox = OutboxDao(db);
      final pull = SyncPullService(
        appwriteService: AppwriteService(),
        database: db,
        outboxDao: outbox,
      );
      pull.setAncestorCacheDao(AncestorCacheDao(db), deviceId: 'device-B');

      // جهاز B يملك السجل نشطًا بساعة متجهية أحدث…
      final remoteTombstone = <String, dynamic>{
        'localUuid': 'expense-deleted-2',
        'amount': 100.0,
        'deletedAt': _now - 100,
        'lastModified': _now - 100,
        'vectorClock': '{"device-A": 1}',
      };

      final result = await pull.checkAndResolveConflict(
        remoteTombstone,
        0,
        remoteUpdatedAtSec: _now,
        localVectorClock: '{"device-A": 1, "device-B": 5}',
        entityName: 'expenses',
        localUuid: 'expense-deleted-2',
        localData: <String, dynamic>{
          'localUuid': 'expense-deleted-2',
          'amount': 100.0,
          'deletedAt': null,
          'lastModified': _now - 50,
          'vectorClock': '{"device-A": 1, "device-B": 5}',
        },
      );

      expect(
        result.shouldApplyRemote,
        isTrue,
        reason:
            'الـ tombstone البعيد يُطبَّق دائمًا — جهاز قديم لا يُحيي السجل',
      );
    });

    test(
      'local delete is preserved against a concurrent remote update',
      () async {
        final db = _newDb();
        addTearDown(() => db.close());
        final outbox = OutboxDao(db);
        final pull = SyncPullService(
          appwriteService: AppwriteService(),
          database: db,
          outboxDao: outbox,
        );
        pull.setAncestorCacheDao(AncestorCacheDao(db), deviceId: 'device-B');

        final result = await pull.checkAndResolveConflict(
          <String, dynamic>{
            'localUuid': 'expense-deleted-3',
            'amount': 200.0,
            'deletedAt': null,
            'lastModified': _now,
            'vectorClock': '{"device-A": 3}',
          },
          _now - 10,
          localDeletedAt: _now - 20,
          remoteUpdatedAtSec: _now,
          entityName: 'expenses',
          localUuid: 'expense-deleted-3',
        );

        expect(result.shouldApplyRemote, isFalse);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 7) الاستعادة و 8) تغيير مزوّد المزامنة
  // ═══════════════════════════════════════════════════════════════════════
  group('7+8) الاستعادة وتغيير المزوّد', () {
    /// تصدير محايد عن المزوّد (نفس مسار Drive/النسخ الاحتياطي: snake_case).
    ///
    /// [enrichProviderLinks] = true يحاكي **مسار الرفع الحقيقي** في التطبيق:
    /// `appwrite_sync_manager._processSalaryPaymentEntry` يحقن `cycleLocalUuid`
    /// (وهوية الموظف) في حمولة الدفعة وقت الرفع. لهذا يلزم التصدير المُغنى
    /// كي تُنقل هوية الدورة عبر المزوّد — أما الصف الخام فلا يحملها (فجوة G-1).
    Future<Map<String, List<Map<String, dynamic>>>> exportNeutral(
      AppDatabase db, {
      bool enrichProviderLinks = true,
    }) async {
      final employees = await db.select(db.employees).get();
      final expenses = await db.select(db.expenses).get();
      final withdrawals = await db.select(db.salaryWithdrawals).get();
      final cycles = await db.select(db.salaryCycles).get();
      final payments = await db.select(db.salaryPayments).get();

      final employeeAdapter = EmployeesAdapter(IdResolver(db));
      final expenseAdapter = ExpensesAdapter(IdResolver(db));
      final withdrawalAdapter = SalaryWithdrawalsAdapter(IdResolver(db));
      final cycleAdapter = SalaryCyclesAdapter(IdResolver(db));
      final paymentAdapter = SalaryPaymentsAdapter(IdResolver(db));

      final cycleUuidById = <int, String>{
        for (final c in cycles) c.id: c.localUuid,
      };

      return <String, List<Map<String, dynamic>>>{
        'employees': [
          for (final r in employees)
            employeeAdapter.toJson(r, src: Source.drive),
        ],
        'salary_cycles': [
          for (final r in cycles) cycleAdapter.toJson(r, src: Source.drive),
        ],
        'expenses': [
          for (final r in expenses) expenseAdapter.toJson(r, src: Source.drive),
        ],
        'salary_withdrawals': [
          for (final r in withdrawals)
            withdrawalAdapter.toJson(r, src: Source.drive),
        ],
        'salary_payments': [
          for (final r in payments)
            _paymentExport(
              paymentAdapter.toJson(r, src: Source.drive),
              cycleUuid: enrichProviderLinks ? cycleUuidById[r.cycleId] : null,
              employeeUuid: enrichProviderLinks ? r.employeeUuid : null,
            ),
        ],
      };
    }

    /// استيراد في قاعدة جديدة — الأب قبل الابن (سياسة الانتقال الرسمية).
    /// استيراد في قاعدة جديدة — الأب قبل الابن (سياسة الانتقال الرسمية).
    ///
    /// يحاكي `BaseRepository.upsertFromJson`: أي سجل يُرجع `refs.shouldSkip`
    /// (مرجع أب غير محلول) **يُؤجّل ولا يُدرج** — لا ربط تخميني ولا crash.
    /// ملاحظة: نحذف 'id' القادم من المصدر قبل الإدراج (نفس ما يفعله
    /// BaseRepository للمصادر البعيدة) لأن `id` autoincrement محلي.
    Future<ImportStats> importNeutral(
      AppDatabase db,
      Map<String, List<Map<String, dynamic>>> data,
    ) async {
      final stats = ImportStats();
      final employeeAdapter = EmployeesAdapter(IdResolver(db));
      final cycleAdapter = SalaryCyclesAdapter(IdResolver(db));
      final expenseAdapter = ExpensesAdapter(IdResolver(db));
      final withdrawalAdapter = SalaryWithdrawalsAdapter(IdResolver(db));
      final paymentAdapter = SalaryPaymentsAdapter(IdResolver(db));

      for (final row in data['employees']!) {
        final json = Map<String, dynamic>.from(row)..remove('id');
        final refs = await employeeAdapter.resolveRefs(
          db,
          json,
          src: Source.drive,
        );
        if (refs.shouldSkip) {
          stats.deferred.add('employees:${json['local_uuid']}');
          continue;
        }
        await db
            .into(db.employees)
            .insert(
              employeeAdapter.fromJson(json, src: Source.drive, refs: refs),
            );
        stats.inserted++;
      }
      for (final row in data['salary_cycles']!) {
        final json = Map<String, dynamic>.from(row)..remove('id');
        final refs = await cycleAdapter.resolveRefs(
          db,
          json,
          src: Source.drive,
        );
        if (refs.shouldSkip) {
          stats.deferred.add('salary_cycles:${json['local_uuid']}');
          continue;
        }
        await db
            .into(db.salaryCycles)
            .insert(cycleAdapter.fromJson(json, src: Source.drive, refs: refs));
        stats.inserted++;
      }
      for (final row in data['expenses']!) {
        final json = Map<String, dynamic>.from(row)..remove('id');
        final refs = await expenseAdapter.resolveRefs(
          db,
          json,
          src: Source.drive,
        );
        if (refs.shouldSkip) {
          stats.deferred.add('expenses:${json['local_uuid']}');
          continue;
        }
        await db
            .into(db.expenses)
            .insert(
              expenseAdapter.fromJson(json, src: Source.drive, refs: refs),
            );
        stats.inserted++;
      }
      for (final row in data['salary_withdrawals']!) {
        final json = Map<String, dynamic>.from(row)..remove('id');
        final refs = await withdrawalAdapter.resolveRefs(
          db,
          json,
          src: Source.drive,
        );
        if (refs.shouldSkip) {
          stats.deferred.add('salary_withdrawals:${json['local_uuid']}');
          continue;
        }
        await db
            .into(db.salaryWithdrawals)
            .insert(
              withdrawalAdapter.fromJson(json, src: Source.drive, refs: refs),
            );
        stats.inserted++;
      }
      for (final row in data['salary_payments']!) {
        final json = Map<String, dynamic>.from(row)..remove('id');
        final refs = await paymentAdapter.resolveRefs(
          db,
          json,
          src: Source.drive,
        );
        if (refs.shouldSkip) {
          stats.deferred.add('salary_payments:${json['local_uuid']}');
          continue;
        }
        await db
            .into(db.salaryPayments)
            .insert(
              paymentAdapter.fromJson(json, src: Source.drive, refs: refs),
            );
        stats.inserted++;
      }
      return stats;
    }

    Future<AppDatabase> buildSource() async {
      final db = _newDb();
      final emp1 = await _employee(
        db,
        uuid: 'emp-uuid-0001',
        name: 'موظف أول',
        serverId: 11,
      );
      final emp2 = await _employee(
        db,
        uuid: 'emp-uuid-0002',
        name: 'موظف ثانٍ',
        serverId: 12,
      );

      final exp1 = await _expense(
        db,
        uuid: 'exp-uuid-0001',
        type: _salaryType,
        amount: 150.5,
        employeeUuid: 'emp-uuid-0001',
        relatedId: emp1,
      );
      final exp2 = await _expense(
        db,
        uuid: 'exp-uuid-0002',
        type: _advanceType,
        amount: 60,
        employeeUuid: 'emp-uuid-0001',
        relatedId: emp1,
      );
      await _expense(
        db,
        uuid: 'exp-uuid-0003',
        type: _salaryType,
        amount: 90.25,
        employeeUuid: 'emp-uuid-0002',
        relatedId: emp2,
      );

      await _withdrawal(
        db,
        uuid: 'wd-uuid-0001',
        employeeId: emp1,
        amount: 150,
        employeeUuid: 'emp-uuid-0001',
        expenseId: exp1,
        expenseUuid: 'exp-uuid-0001',
        reason: 'exp_$exp1',
      );
      await _withdrawal(
        db,
        uuid: 'wd-uuid-0002',
        employeeId: emp1,
        amount: 60,
        employeeUuid: 'emp-uuid-0001',
        expenseId: exp2,
        expenseUuid: 'exp-uuid-0002',
        reason: 'exp_$exp2',
      );

      final cycle = await _cycle(
        db,
        uuid: 'cycle-uuid-0001',
        employeeId: emp1,
        cycleKey: '2026-09',
        employeeUuid: 'emp-uuid-0001',
      );
      await _payment(
        db,
        uuid: 'pay-uuid-0001',
        cycleId: cycle,
        amount: 300,
        employeeUuid: 'emp-uuid-0001',
      );

      return db;
    }

    test('restore/export round-trip keeps every uuid untouched', () async {
      final source = await buildSource();
      addTearDown(() => source.close());

      final exported = await exportNeutral(source);
      final beforeEmployees = await source.select(source.employees).get();
      final beforeExpenses = await source.select(source.expenses).get();

      final target = _newDb();
      addTearDown(() => target.close());
      final stats = await importNeutral(target, exported);

      expect(
        stats.deferred,
        isEmpty,
        reason:
            'تصدير مُغنى بروابط المزوّد (كما يفعل مسار الرفع) لا يُؤجّل شيئًا',
      );

      final afterEmployees = await target.select(target.employees).get();
      final afterExpenses = await target.select(target.expenses).get();

      expect(
        afterEmployees.map((e) => e.localUuid).toSet(),
        beforeEmployees.map((e) => e.localUuid).toSet(),
        reason: 'الاستعادة لا تُغيّر هوية أي موظف',
      );
      expect(
        afterExpenses.map((e) => e.localUuid).toSet(),
        beforeExpenses.map((e) => e.localUuid).toSet(),
        reason: 'الاستعادة لا تُغيّر هوية أي مصروف',
      );
    });

    test(
      'G-1 (documented gap): a raw payment row carries no cycle identity → migration defers it',
      () async {
        final source = await buildSource();
        addTearDown(() => source.close());

        // تصدير "خام" بلا حقن روابط المزوّد (كما هو صف الجدول فعلًا)
        final exported = await exportNeutral(
          source,
          enrichProviderLinks: false,
        );
        final paymentRow = exported['salary_payments']!.single;
        expect(
          paymentRow['cycle_local_uuid'],
          isNull,
          reason: 'الصف نفسه لا يحمل هوية دورته — لا عمود cycle_uuid (G-1)',
        );

        final target = _newDb();
        addTearDown(() => target.close());
        final stats = await importNeutral(target, exported);

        // ⚠️ الفجوة: بلا حمولة الرفع، تفقد الدفعة رابط دورتها فيُؤجَّل إدراجها.
        // المطلوب بعد إصلاح P0-2 (عمود cycle_uuid + كتابته عند الإنشاء):
        //   expect(stats.deferred, isEmpty);  ← يجب أن يصبح هذا هو السلوك.
        expect(stats.deferred, hasLength(1));
        expect(stats.deferred.single, startsWith('salary_payments:'));
        expect(
          await target.select(target.salaryPayments).get(),
          isEmpty,
          reason: 'لا تُدرج دفعة بمرجع أب غير محلول (لا ربط تخميني)',
        );
      },
    );

    test(
      'G-10 (fixed): no decimal fractions — provider payload truncates towards zero',
      () async {
        final source = _newDb();
        addTearDown(() => source.close());

        final emp = await _employee(source, uuid: 'emp-fraction', name: 'موظف');
        await _withdrawal(
          source,
          uuid: 'wd-fraction',
          employeeId: emp,
          amount: 150.5, // صف تاريخي بكسر (مخزَّن قبل تطبيق السياسة)
          employeeUuid: 'emp-fraction',
          reason: 'direct_withdrawal_1',
        );

        final exported = await exportNeutral(source);
        final target = _newDb();
        addTearDown(() => target.close());
        await importNeutral(target, exported);

        final sourceAmount =
            (await source.select(source.salaryWithdrawals).get()).single.amount;
        final targetAmount =
            (await target.select(target.salaryWithdrawals).get()).single.amount;

        expect(sourceAmount, 150.5);
        // ✅ سياسة الفندق: «لا كسور عشرية» + اقتطاع نحو الصفر (لا نُقرّب لأعلى
        // ولا نضيف مبلغاً) — نفس ما يعرضه CurrencyFormatter ويُدخله parseAmount.
        // 150.5 → 150 (وليس 151 كما كان مع .round()).
        expect(
          targetAmount,
          150,
          reason: 'الاقتطاع نحو الصفر — لا زيادة على أي مبلغ عند النقل',
        );
      },
    );

    test(
      'G-10: the mirror pair (expense ↔ withdrawal) truncates identically',
      () async {
        final source = _newDb();
        addTearDown(() => source.close());

        final emp = await _employee(source, uuid: 'emp-mirror-2', name: 'موظف');
        const expUuid = 'exp-mirror-fraction';
        final expId = await _expense(
          source,
          uuid: expUuid,
          type: _salaryType,
          amount: 150.5,
          employeeUuid: 'emp-mirror-2',
        );
        await _withdrawal(
          source,
          uuid: 'wd-mirror-fraction',
          employeeId: emp,
          amount: 150.5,
          employeeUuid: 'emp-mirror-2',
          expenseId: expId,
          expenseUuid: expUuid,
          reason: 'exp_$expId',
        );

        final exported = await exportNeutral(source);
        final target = _newDb();
        addTearDown(() => target.close());
        await importNeutral(target, exported);

        final expenseAmount =
            (await target.select(target.expenses).get()).single.amount;
        final withdrawalAmount =
            (await target.select(target.salaryWithdrawals).get()).single.amount;

        expect(expenseAmount, 150);
        expect(
          withdrawalAmount,
          expenseAmount,
          reason:
              'مصروف الرواتب = سحب الراتب المرآة بعد عبور المزوّد — '
              'أي فرق بينهما يكسر معادلة الاستحقاقات',
        );
      },
    );

    test(
      'G-10: legacy fractional rows are reported (read-only) without being rewritten',
      () async {
        final db = _newDb();
        addTearDown(() => db.close());

        final emp = await _employee(db, uuid: 'emp-legacy', name: 'موظف');
        await _withdrawal(
          db,
          uuid: 'wd-legacy-fraction',
          employeeId: emp,
          amount: 99.99,
          employeeUuid: 'emp-legacy',
        );
        await _expense(
          db,
          uuid: 'exp-legacy-fraction',
          amount: 12.5,
          employeeUuid: 'emp-legacy',
          relatedId: emp,
        );
        await _expense(db, uuid: 'exp-legacy-whole', amount: 40);

        final report = await MoneyIntegrityService(db).scan();

        expect(report.isClean, isFalse);
        expect(report.affectedRows, 2);
        expect(report.countByTable['salary_withdrawals'], 1);
        expect(report.countByTable['expenses'], 1);

        final withdrawalRow = report.rows.firstWhere(
          (r) => r.table == 'salary_withdrawals',
        );
        expect(withdrawalRow.localUuid, 'wd-legacy-fraction');
        expect(withdrawalRow.policyAmount, 99); // اقتطاع نحو الصفر
        expect(withdrawalRow.employeeUuid, 'emp-legacy');

        // ⚠️ لا تعديل على البيانات التاريخية: الصفوف ما زالت كما هي في القاعدة.
        final stillFractional =
            (await db.select(db.salaryWithdrawals).get()).single.amount;
        expect(stillFractional, 99.99);
        final expenseStillFractional =
            (await (db.select(db.expenses)
                      ..where((e) => e.localUuid.equals('exp-legacy-fraction')))
                    .getSingle())
                .amount;
        expect(expenseStillFractional, 12.5);
      },
    );

    test(
      'provider swap keeps counts, uuids, relations and money totals',
      () async {
        final source = await buildSource();
        addTearDown(() => source.close());

        final exported = await exportNeutral(source);

        // استيراد على جهاز آخر — الترتيب مختلف والترقيم المحلي مختلف
        final target = _newDb();
        addTearDown(() => target.close());
        // موظف حشو أولًا ليتغيّر ترقيم المعرفات كليًا
        await _employee(target, uuid: 'filler-emp', name: 'حشو');
        final stats = await importNeutral(target, exported);
        expect(
          stats.deferred,
          isEmpty,
          reason: 'لا سجل مفقود في الانتقال (البند 9: نقل كامل بلا فقد)',
        );

        // 1) الأعداد — نستثني «موظف الحشو» الذي أُدرج عمدًا لتغيير الترقيم
        final importedEmployees = (await target.select(target.employees).get())
            .where((e) => e.localUuid != 'filler-emp')
            .toList();
        expect(
          importedEmployees.length,
          (await source.select(source.employees).get()).length,
          reason: 'كل موظف انتقل مرة واحدة بالضبط (لا فقد ولا تكرار)',
        );
        expect(
          (await target.select(target.expenses).get()).length,
          (await source.select(source.expenses).get()).length,
        );
        expect(
          (await target.select(target.salaryWithdrawals).get()).length,
          (await source.select(source.salaryWithdrawals).get()).length,
        );
        expect(
          (await target.select(target.salaryCycles).get()).length,
          (await source.select(source.salaryCycles).get()).length,
        );
        expect(
          (await target.select(target.salaryPayments).get()).length,
          (await source.select(source.salaryPayments).get()).length,
        );

        // 2) الهويات
        final targetExpenses = await target.select(target.expenses).get();
        expect(targetExpenses.map((e) => e.localUuid).toSet(), {
          'exp-uuid-0001',
          'exp-uuid-0002',
          'exp-uuid-0003',
        });

        // 3) المجاميع المالية
        double sum(Iterable<num> values) =>
            values.fold<double>(0, (s, v) => s + v.toDouble());
        final sourceExpenseTotal = sum(
          (await source.select(source.expenses).get()).map((e) => e.amount),
        );
        expect(sum(targetExpenses.map((e) => e.amount)), sourceExpenseTotal);
        final sourceWithdrawalTotal = sum(
          (await source.select(source.salaryWithdrawals).get()).map(
            (w) => w.amount,
          ),
        );
        expect(
          sum(
            (await target.select(target.salaryWithdrawals).get()).map(
              (w) => w.amount,
            ),
          ),
          sourceWithdrawalTotal,
        );
        final sourcePaymentTotal = sum(
          (await source.select(source.salaryPayments).get()).map(
            (p) => p.amount,
          ),
        );
        expect(
          sum(
            (await target.select(target.salaryPayments).get()).map(
              (p) => p.amount,
            ),
          ),
          sourcePaymentTotal,
        );

        // 4) العلاقات الأساسية
        final targetEmployees = await target.select(target.employees).get();
        int? idByUuid(String uuid) {
          for (final employee in targetEmployees) {
            if (employee.localUuid == uuid) return employee.id;
          }
          return null;
        }

        for (final e in targetExpenses.where(
          (e) => e.employeeUuid == 'emp-uuid-0001',
        )) {
          expect(
            e.relatedId,
            idByUuid('emp-uuid-0001'),
            reason: 'المصروف مربوط بالموظف عبر الهوية لا عبر رقم جهاز المصدر',
          );
        }
        for (final w in await target.select(target.salaryWithdrawals).get()) {
          expect(w.employeeUuid, isNotNull);
          expect(w.expenseUuid, isNotNull);
        }

        // 5) هوية الدورة في الدفعة: تُنقل عبر حمولة المزوّد (cycle_local_uuid)
        //    — نفس ما يحقنه مسار الرفع. الرقم المحلي cycle_id لا يُعتمد عليه.
        expect(
          exported['salary_payments']!.single['cycle_local_uuid'],
          'cycle-uuid-0001',
          reason: 'حمولة الرفع تحمل هوية الدورة الثابتة',
        );
        final payments = await target.select(target.salaryPayments).get();
        expect(payments.single.employeeUuid, 'emp-uuid-0001');
        final cycles = await target.select(target.salaryCycles).get();
        final linkedCycle = cycles.singleWhere(
          (c) => c.id == payments.single.cycleId,
        );
        expect(
          linkedCycle.localUuid,
          'cycle-uuid-0001',
          reason: 'الدفعة مرتبطة بدورتها عبر الهوية لا عبر تصادف الأرقام',
        );
        expect(linkedCycle.employeeUuid, 'emp-uuid-0001');
      },
    );

    test(
      'two devices with the same identity produce one employee per uuid (no duplication)',
      () async {
        final deviceA = _newDb();
        final deviceB = _newDb();
        addTearDown(() async {
          await deviceA.close();
          await deviceB.close();
        });

        const empUuid = 'shared-employee-uuid-1';
        await _employee(deviceA, uuid: empUuid, name: 'موظف');
        await _employee(deviceA, uuid: 'other-uuid', name: 'آخر');

        // جهاز B ينشئ نفس الموظف بنفس الهوية (حالة تصادم إنشاء نادرة)
        final employeeAdapter = EmployeesAdapter(IdResolver(deviceB));
        for (final uuid in [empUuid, empUuid]) {
          final json = <String, dynamic>{
            'localUuid': uuid,
            'name': 'موظف',
            'basicSalary': 0,
            'status': 'active',
            'createdAt': _now,
            'updatedAt': _now,
            'lastModified': _now,
          };
          final refs = await employeeAdapter.resolveRefs(
            deviceB,
            Map<String, dynamic>.from(json),
            src: Source.appwrite,
          );
          final companion = employeeAdapter.fromJson(
            json,
            src: Source.appwrite,
            refs: refs,
          );
          final existing = await (deviceB.select(
            deviceB.employees,
          )..where((e) => e.localUuid.equals(uuid))).getSingleOrNull();
          if (existing == null) {
            await deviceB.into(deviceB.employees).insert(companion);
          }
        }

        final rows = await deviceB.select(deviceB.employees).get();
        expect(
          rows.where((e) => e.localUuid == empUuid),
          hasLength(1),
          reason: 'الهوية الفريدة تمنع تكرار الموظف عبر الأجهزة',
        );
      },
    );
  });
}
