// test/unit/expenses_device_local_ids_conflict_test.dart
//
// ✅ درع انحدار لـ «تعارضات المصروفات ومصروفات الرواتب» (2026-11-02).
//
// السبب الجذري (pre-fix):
//   معرفات FK الرقمية المحلية لكل جهاز (autoincrement) كانت تُرفع للسحابة
//   وتدخل الدمج ثلاثي الأطراف:
//     expenses: relatedId (موظف) + cashTransactionId (حركة نقد)
//     salary_withdrawals: employeeId + expenseId
//   هذه القيم لا تتطابق أبداً بين جهازين → كل دمج يراها «تغييراً بعيداً»
//   → version+1 ورفع النتيجة → الجهاز الآخر يدمج ويرفع معرفاته →
//   ping-pong تعارضات لا ينتهي. وعلى السحب، cashTransactionId/relatedId
//   الخام كانا يُخزَّنان كما هما → ربط المصروف بصفوف خاطئة محلياً.
//
// العقود المثبتة هنا (كود الإنتاج نفسه بلا محاكاة):
//   A) ConflictDetector/SmartConflictResolver: معرفات الجهاز المحلية لا
//      تدخل حساب الحقول المتغيّرة أبداً، والدمج المتزامن لا ينسخها من
//      البعيد، ولا يرفع version بلا تغيير فعلي.
//   B) checkAndResolveConflict: تطابق VC مع اختلاف معرفات محلية فقط →
//      لا إعادة تطبيق (نهاية دوران «نفس السجل يُسحب في كل دورة»).
//   C) ExpensesAdapter (قاعدة حقيقية + FK مفعّل): relatedId الرواتب يُحل
//      عبر employeeUuid، غير الرواتب من مصدر بعيد → null (لا الرقم الخام)،
//      و cashTransactionId يُحل عبر cashFlowUuid لا الرقم الخام.
//   D) PayloadMapper: المصروف لا يرفع relatedId/cashTransactionId، وسحبة
//      الراتب لا ترفع employeeId/expenseId — الروابط المحمولة هي UUIDs.

// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/ancestor_cache_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync/payload_mapper.dart';
import 'package:marina_hotel_mobile/services/sync_core/conflict_detector.dart';
import 'package:marina_hotel_mobile/services/sync_core/smart_conflict_resolver.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';

const int _kBaseEpochSec = 1760000000;

Map<String, dynamic> _expenseData({
  required String uuid,
  required int relatedId,
  required int cashTransactionId,
  int? rowId,
  String vectorClock = '{"A":2}',
  int lastModified = _kBaseEpochSec + 100,
  double amount = 250.0,
}) {
  return <String, dynamic>{
    if (rowId != null) 'id': rowId,
    'localUuid': uuid,
    'expenseType': 'رواتب',
    'description': 'مصروف اختبار',
    'amount': amount,
    'date': '2026-11-01T10:00:00.000Z',
    'relatedId': relatedId,
    'cashTransactionId': cashTransactionId,
    'employeeUuid': 'emp-uuid-1',
    'cashFlowUuid': 'cash-uuid-1',
    'lastModified': lastModified,
    'version': 3,
    'vectorClock': vectorClock,
    'deviceId': 'device-A',
    'deletedAt': null,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════
  // الفصل A — كشف التعارض والدمج: معرفات الجهاز المحلية شفافة تماماً
  // ═══════════════════════════════════════════════════════════════════
  group('A) ConflictDetector + SmartConflictResolver', () {
    test('A1. معرفات محلية مختلفة بين جهازين لا تُحسب حقولاً متغيّرة', () {
      // جهازان لنفس المصروف: كل جهاز بمعرفاته المحلية الخاصة.
      final deviceA = _expenseData(
        uuid: 'exp-1',
        relatedId: 5,
        cashTransactionId: 7,
        rowId: 101,
      );
      final deviceB = _expenseData(
        uuid: 'exp-1',
        relatedId: 12,
        cashTransactionId: 19,
        rowId: 250,
        vectorClock: '{"B":2}',
      );

      final detection = ConflictDetector.detect(
        localData: deviceA,
        remoteData: deviceB,
        commonAncestor: null,
      );

      expect(
        detection.type,
        ConflictType.concurrentDifferentFields,
        reason:
            'ساعتان متجهيتان متزامنتان (A:2 مقابل B:2) '
            'لكن بلا حقول متعارضة — تأكيد الإعداد قبل الفحوص',
      );
      expect(
        detection.localChangedFields,
        isNot(contains('relatedId')),
        reason: 'relatedId محلي لكل جهاز — لا يدخل حساب التغيّر',
      );
      expect(
        detection.localChangedFields,
        isNot(contains('cashTransactionId')),
      );
      expect(detection.localChangedFields, isNot(contains('id')));
      expect(detection.remoteChangedFields, isNot(contains('relatedId')));
      expect(
        detection.remoteChangedFields,
        isNot(contains('cashTransactionId')),
      );
      // لا تغيير حقيقي إطلاقاً → الحالتان فارغتان → لا دمج ولا رفع.
      expect(detection.localChangedFields, isEmpty);
      expect(detection.remoteChangedFields, isEmpty);
    });

    test('A2. دمج متزامن بتغيير حقيقي واحد (amount) لا ينسخ معرفات البعيد', () {
      final local = _expenseData(
        uuid: 'exp-1',
        relatedId: 5,
        cashTransactionId: 7,
        rowId: 101,
      );
      // البعيد غيّر amount فعلاً (أحدث زمنياً) + يحمل معرفات جهاز مختلفة.
      final remote = _expenseData(
        uuid: 'exp-1',
        relatedId: 12,
        cashTransactionId: 19,
        rowId: 250,
        vectorClock: '{"B":2}',
        amount: 300.0,
        lastModified: _kBaseEpochSec + 200,
      );

      final resolution = SmartConflictResolver.resolve(
        entity: 'expenses',
        localData: local,
        remoteData: remote,
        commonAncestor: null,
      );

      expect(
        resolution.mergedData['amount'],
        300.0,
        reason: 'التغيير الحقيقي البعيد يصل',
      );
      expect(
        resolution.mergedData['relatedId'],
        5,
        reason: 'معرّف الموظف المحلي يبقى — رقم جهاز البعيد بلا معنى هنا',
      );
      expect(
        resolution.mergedData['cashTransactionId'],
        7,
        reason: 'معرّف حركة النقد المحلي يبقى',
      );
      expect(
        resolution.mergedData['id'],
        101,
        reason: 'معرّف الصف المحلي يبقى',
      );
    });

    test(
      'A3. تعارض متزامن بلا أي تغيير فعلي → المحلي يفوز بلا رفع (درع ping-pong)',
      () {
        final local = _expenseData(
          uuid: 'exp-1',
          relatedId: 5,
          cashTransactionId: 7,
          rowId: 101,
        );
        final remote = _expenseData(
          uuid: 'exp-1',
          relatedId: 12,
          cashTransactionId: 19,
          rowId: 250,
          vectorClock: '{"B":2}',
        );

        final resolution = SmartConflictResolver.resolve(
          entity: 'expenses',
          localData: local,
          remoteData: remote,
          commonAncestor: null,
        );

        expect(
          resolution.strategy,
          ResolutionStrategy.localWins,
          reason: 'لا تغيير حقيقياً — الدمج كان سيرفع version+1 بلا سبب',
        );
        expect(
          resolution.pushedToRemote,
          isFalse,
          reason: 'لا رفع للسحابة — هذا كان وقود دوران التعارضات',
        );
        expect(resolution.mergedData['version'], 3, reason: 'version لم يُزد');
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════
  // الفصل B — checkAndResolveConflict: تطابق VC + معرفات محلية فقط
  //          → لا إعادة تطبيق
  // ═══════════════════════════════════════════════════════════════════
  group('B) SyncPullService.checkAndResolveConflict', () {
    late AppDatabase db;
    late OutboxDao outboxDao;
    late SyncPullService pullService;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      outboxDao = OutboxDao(db);
      pullService = SyncPullService(
        appwriteService: AppwriteService(),
        database: db,
        outboxDao: outboxDao,
      );
      pullService.setAncestorCacheDao(
        AncestorCacheDao(db),
        deviceId: 'device-A',
      );
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'B1. VC متطابقة والفرق الوحيد معرفات محلية → shouldApplyRemote=false',
      () async {
        final localData = _expenseData(
          uuid: 'exp-1',
          relatedId: 5,
          cashTransactionId: 7,
          rowId: 101,
          vectorClock: '{"A":2}',
        );
        final remoteData = _expenseData(
          uuid: 'exp-1',
          relatedId: 12,
          cashTransactionId: 19,
          rowId: 250,
          vectorClock: '{"A":2}',
        );

        final result = await pullService.checkAndResolveConflict(
          remoteData,
          _kBaseEpochSec + 100,
          localVectorClock: '{"A":2}',
          entityName: 'expenses',
          localUuid: 'exp-1',
          localData: localData,
        );

        expect(
          result.shouldApplyRemote,
          isFalse,
          reason:
              'المحتوى الفعلي متطابق — قبل الإصلاح كانت مقارنة المحتوى تفشل '
              'على معرفات كل جهاز فيُعاد تطبيق نفس السجل في كل دورة سحب',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════
  // الفصل C — ExpensesAdapter على قاعدة حقيقية: الروابط تُحل عبر UUIDs
  // ═══════════════════════════════════════════════════════════════════
  group('C) ExpensesAdapter — cross-device link resolution', () {
    late AppDatabase db;
    late int employeeLocalId;
    late int cashLocalId;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AdapterRegistry.initialize(db);

      // موظف محلي (uuid هو الهوية المحمولة عبر الأجهزة).
      employeeLocalId = await db
          .into(db.employees)
          .insert(
            const EmployeesCompanion(
              name: d.Value('أحمد'),
              position: d.Value('عامل'),
              status: d.Value('نشط'),
              basicSalary: d.Value(50000),
              localUuid: d.Value('emp-uuid-1'),
              createdAt: d.Value(_kBaseEpochSec),
              updatedAt: d.Value(_kBaseEpochSec),
              lastModified: d.Value(_kBaseEpochSec),
            ),
          );

      // حركة نقد محلية (uuid هو الهوية المحمولة).
      cashLocalId = await db
          .into(db.cashTransactions)
          .insert(
            const CashTransactionsCompanion(
              transactionType: d.Value('expense'),
              amount: d.Value(250.0),
              transactionTime: d.Value('2026-11-01T10:00:00.000Z'),
              localUuid: d.Value('cash-uuid-1'),
              createdAt: d.Value(_kBaseEpochSec),
              updatedAt: d.Value(_kBaseEpochSec),
              lastModified: d.Value(_kBaseEpochSec),
            ),
          );

      // صفوف خادعة تحمل نفس الأرقام الخام الواردة من الجهاز الآخر —
      // قبل الإصلاح كانت هذه هي التي يُربط بها المصروع خطأً.
      await db
          .into(db.employees)
          .insert(
            const EmployeesCompanion(
              name: d.Value('موظف مختلف تماماً'),
              position: d.Value('عامل'),
              status: d.Value('نشط'),
              basicSalary: d.Value(70000),
              localUuid: d.Value('emp-uuid-OTHER'),
              createdAt: d.Value(_kBaseEpochSec),
              updatedAt: d.Value(_kBaseEpochSec),
              lastModified: d.Value(_kBaseEpochSec),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'C1. مصروف رواتب من Appwrite: relatedId من employeeUuid لا الرقم الخام',
      () async {
        // الرقم الخام 888 هو معرّف الموظف على جهاز الإنشاء — لا معنى له هنا.
        // الموظف المحلي الصحيح (بـ uuid emp-uuid-1) له معرّف مختلف.
        expect(employeeLocalId, isNot(888));

        await AdapterRegistry.instance.expenses
            .upsertFromJson(<String, dynamic>{
              'localUuid': 'exp-salary-1',
              'expenseType': 'رواتب',
              'description': 'راتب نوفمبر',
              'amount': 250.0,
              'date': '2026-11-01T10:00:00.000Z',
              'relatedId': 888,
              'employeeUuid': 'emp-uuid-1',
              'lastModified': _kBaseEpochSec + 50,
              'version': 2,
              'vectorClock': '{"B":1}',
              'deviceId': 'device-B',
            }, src: Source.appwrite);

        final row = await (db.select(
          db.expenses,
        )..where((e) => e.localUuid.equals('exp-salary-1'))).getSingle();
        expect(
          row.relatedId,
          employeeLocalId,
          reason: 'الربط عبر employeeUuid — لا الرقم الخام 888',
        );
      },
    );

    test('C2. مصروف غير رواتب من Appwrite: relatedId الخام لا يُخزَّن، '
        'و cashTransactionId يُحل عبر cashFlowUuid', () async {
      expect(cashLocalId, isNot(999));

      await AdapterRegistry.instance.expenses.upsertFromJson(<String, dynamic>{
        'localUuid': 'exp-normal-1',
        'expenseType': 'صيانة',
        'description': 'صيانة مكيف',
        'amount': 80.0,
        'date': '2026-11-01T10:00:00.000Z',
        'relatedId': 888,
        'cashTransactionId': 999,
        'cashFlowUuid': 'cash-uuid-1',
        'lastModified': _kBaseEpochSec + 50,
        'version': 2,
        'vectorClock': '{"B":1}',
        'deviceId': 'device-B',
      }, src: Source.appwrite);

      final row = await (db.select(
        db.expenses,
      )..where((e) => e.localUuid.equals('exp-normal-1'))).getSingle();
      expect(
        row.relatedId,
        isNull,
        reason: 'رقم جهاز المصدر لا يُخزَّن — كان يربط المصروف بصف خاطئ',
      );
      expect(
        row.cashTransactionId,
        cashLocalId,
        reason: 'الربط عبر cashFlowUuid — لا الرقم الخام 999',
      );
    });

    test(
      'C3. مصروف نقد من Appwrite بلا حركة نقد محلية بعد: لا ربط خاطئ',
      () async {
        await AdapterRegistry.instance.expenses
            .upsertFromJson(<String, dynamic>{
              'localUuid': 'exp-pending-1',
              'expenseType': 'مشتريات',
              'description': 'مشتريات مطبخ',
              'amount': 120.0,
              'date': '2026-11-01T10:00:00.000Z',
              'cashTransactionId': 999,
              'cashFlowUuid': 'cash-uuid-NOT-ARRIVED',
              'lastModified': _kBaseEpochSec + 50,
              'version': 2,
              'vectorClock': '{"B":1}',
              'deviceId': 'device-B',
            }, src: Source.appwrite);

        final row = await (db.select(
          db.expenses,
        )..where((e) => e.localUuid.equals('exp-pending-1'))).getSingle();
        expect(
          row.cashTransactionId,
          isNull,
          reason:
              'الحركة النقدية لم تصل بعد → null قابل للشفاء لاحقاً، '
              'لا الرقم الخام 999 الذي يربط بحركة مختلفة',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════
  // الفصل D — PayloadMapper: لا رفع لمعرفات الجهاز المحلية
  // ═══════════════════════════════════════════════════════════════════
  group('D) PayloadMapper — device-local ids never pushed', () {
    late AppDatabase db;
    const mapper = PayloadMapper();

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('D1. expenseToRemote: لا relatedId ولا cashTransactionId', () async {
      final expenseId = await db
          .into(db.expenses)
          .insert(
            const ExpensesCompanion(
              expenseType: d.Value('رواتب'),
              description: d.Value('راتب'),
              amount: d.Value(250.0),
              date: d.Value('2026-11-01'),
              relatedId: d.Value(5),
              cashTransactionId: d.Value(7),
              localUuid: d.Value('exp-map-1'),
              createdAt: d.Value(_kBaseEpochSec),
              updatedAt: d.Value(_kBaseEpochSec),
              lastModified: d.Value(_kBaseEpochSec),
            ),
          );
      final expense = await (db.select(
        db.expenses,
      )..where((e) => e.id.equals(expenseId))).getSingle();

      final payload = mapper.expenseToRemote(expense);

      expect(
        payload.containsKey('relatedId'),
        isFalse,
        reason: 'معرّف الموظف المحلي لا يُرفع — employeeUuid هو الرابط',
      );
      expect(
        payload.containsKey('cashTransactionId'),
        isFalse,
        reason: 'معرّف حركة النقد المحلي لا يُرفع — cashFlowUuid هو الرابط',
      );
      expect(payload['localUuid'], 'exp-map-1');
      expect(payload['amount'], 250.0);
    });

    test('D2. salaryWithdrawalToRemote: لا employeeId ولا expenseId', () async {
      final empId = await db
          .into(db.employees)
          .insert(
            const EmployeesCompanion(
              name: d.Value('أحمد'),
              position: d.Value('عامل'),
              status: d.Value('نشط'),
              basicSalary: d.Value(50000),
              localUuid: d.Value('emp-uuid-1'),
              createdAt: d.Value(_kBaseEpochSec),
              updatedAt: d.Value(_kBaseEpochSec),
              lastModified: d.Value(_kBaseEpochSec),
            ),
          );
      final withdrawalId = await db
          .into(db.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion(
              employeeId: d.Value(empId),
              amount: const d.Value(10000.0),
              withdrawDate: const d.Value('2026-11-01'),
              localUuid: const d.Value('wd-1'),
              expenseId: const d.Value(77),
              expenseUuid: const d.Value('exp-mirror-1'),
              createdAt: const d.Value(_kBaseEpochSec),
              updatedAt: const d.Value(_kBaseEpochSec),
              lastModified: const d.Value(_kBaseEpochSec),
            ),
          );
      final withdrawal = await (db.select(
        db.salaryWithdrawals,
      )..where((w) => w.id.equals(withdrawalId))).getSingle();

      final payload = mapper.salaryWithdrawalToRemote(
        withdrawal,
        employeeUuid: 'emp-uuid-1',
      );

      expect(
        payload.containsKey('employeeId'),
        isFalse,
        reason: 'معرّف الموظف المحلي لا يُرفع — employeeUuid هو الرابط',
      );
      expect(
        payload.containsKey('expenseId'),
        isFalse,
        reason: 'معرّف المصروف المحلي لا يُرفع — expenseUuid هو الرابط',
      );
      expect(payload['employeeUuid'], 'emp-uuid-1');
      expect(payload['expenseUuid'], 'exp-mirror-1');
      expect(payload['amount'], 10000.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // الفصل E — إثراء employeeUuid وقت الرفع (توحيد مساري outbox والشامل)
  //
  // ⚠️ اختبار واحد متصل عمداً (أربع سيناريوهات متتالية): AppwriteSyncManager
  // singleton بمُنشئ factory يتجاهل المعامل database بعد أول إنشاء — قاعدة
  // ثانية في نفس المجموعة ستستلم مديناً باتصال مغلق («Can't re-open a
  // database after closing it»). نفس نمط pull_commit_visibility_test.dart.
  // ═══════════════════════════════════════════════════════════════════
  test(
    'E) إثراء employeeUuid: الاشتقاق الطازج من relatedId يفوز، والعمود يُملأ أو يُحفظ حسب الحالة',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      AdapterRegistry.initialize(db);
      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );

      Future<Expense> insertExpense({
        required String uuid,
        required String type,
        int? relatedId,
        String? employeeUuid,
      }) async {
        final id = await db
            .into(db.expenses)
            .insert(
              ExpensesCompanion(
                expenseType: d.Value(type),
                description: const d.Value('مصروف'),
                amount: const d.Value(250.0),
                date: const d.Value('2026-11-01'),
                relatedId: d.Value(relatedId),
                employeeUuid: d.Value(employeeUuid),
                localUuid: d.Value(uuid),
                createdAt: const d.Value(_kBaseEpochSec),
                updatedAt: const d.Value(_kBaseEpochSec),
                lastModified: const d.Value(_kBaseEpochSec),
              ),
            );
        return (db.select(
          db.expenses,
        )..where((e) => e.id.equals(id))).getSingle();
      }

      final emp1Id = await db
          .into(db.employees)
          .insert(
            const EmployeesCompanion(
              name: d.Value('أحمد'),
              position: d.Value('عامل'),
              status: d.Value('نشط'),
              basicSalary: d.Value(50000),
              localUuid: d.Value('emp-uuid-1'),
              createdAt: d.Value(_kBaseEpochSec),
              updatedAt: d.Value(_kBaseEpochSec),
              lastModified: d.Value(_kBaseEpochSec),
            ),
          );
      final emp2Id = await db
          .into(db.employees)
          .insert(
            const EmployeesCompanion(
              name: d.Value('سالم'),
              position: d.Value('عامل'),
              status: d.Value('نشط'),
              basicSalary: d.Value(60000),
              localUuid: d.Value('emp-uuid-2'),
              createdAt: d.Value(_kBaseEpochSec),
              updatedAt: d.Value(_kBaseEpochSec),
              lastModified: d.Value(_kBaseEpochSec),
            ),
          );

      // ─── E1: صف قديم (عمود فارغ + relatedId محدد) → الاشتقاق يملأ الرابط.
      // سيناريو ما قبل PR #601 — المسار الشامل كان يرفع المصروف بلا أي
      // رابط موظف → يتيم على الأجهزة الأخرى لا يُعيد الـ relink ربطه.
      final legacy = await insertExpense(
        uuid: 'exp-legacy-1',
        type: 'رواتب',
        relatedId: emp1Id,
        employeeUuid: null,
      );
      expect(
        (await manager.expenseToRemoteWithEmployeeLinkForTesting(
          legacy,
        ))['employeeUuid'],
        'emp-uuid-1',
        reason: 'الاشتقاق من relatedId الحالي يملأ الرابط الغائب',
      );

      // ─── E2: عمود متقادم (أعيد تعيين المصروف دون تحديث العمود) → الطازج
      // يفوز — رفع القيمة المتقادمة كان يربط المصروف بالموظف السابق على كل
      // الأجهزة الأخرى ويُحسب راتبه على الجهة الخطأ.
      final stale = await insertExpense(
        uuid: 'exp-stale-1',
        type: 'رواتب',
        relatedId: emp2Id,
        employeeUuid: 'emp-uuid-1',
      );
      expect(
        (await manager.expenseToRemoteWithEmployeeLinkForTesting(
          stale,
        ))['employeeUuid'],
        'emp-uuid-2',
        reason: 'الاشتقاق الطازج من relatedId يتفوق على العمود المتقادم',
      );

      // ─── E3: مصروف غير رواتب → لا حقن اصطناعي.
      final normal = await insertExpense(
        uuid: 'exp-normal-2',
        type: 'ضيافة',
        relatedId: emp1Id,
        employeeUuid: null,
      );
      expect(
        (await manager.expenseToRemoteWithEmployeeLinkForTesting(
          normal,
        )).containsKey('employeeUuid'),
        isFalse,
        reason: 'الإثراء لمصروفات الرواتب حصراً — غيرها لا موظف له',
      );

      // ─── E4: تعذّر الحل (صف الموظف غائب محلياً) → قيمة العمود تبقى:
      // إسقاط الرابط كان يقطع البيانات عن الأجهزة التي ما زالت تملك الموظف.
      final unresolved = await insertExpense(
        uuid: 'exp-unresolved-1',
        type: 'رواتب',
        relatedId: 999,
        employeeUuid: 'emp-uuid-remote',
      );
      expect(
        (await manager.expenseToRemoteWithEmployeeLinkForTesting(
          unresolved,
        ))['employeeUuid'],
        'emp-uuid-remote',
        reason: 'لا نُسقط رابطاً صالحاً لأن جهازنا فقد صف الموظف',
      );
    },
  );
}
