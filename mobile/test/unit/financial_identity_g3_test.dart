// test/unit/financial_identity_g3_test.dart
//
// ✅ G-3 (تدقيق الهوية المالية 2026-10-06): **لا ربط عبر الأجهزة بمعرّف
// رقمي محلي، ولا تخطٍّ صامت لسجل ناقص الربط.**
//
// هذا الاختبار يُثبت ثلاث حقائق هندسية على قاعدة بيانات حقيقية (Drift
// in-memory) — بالضبط الحالات التي كانت تُفسد الربط قبل الإصلاح:
//
//   1) جهازان فيهما «موظف #7» مختلفان (تصادم أرقام محلية):
//      • UUID يحسم دائماً (لا لبس).
//      • المطابقة الرقمية عبر الأجهزة مرفوضة إلا بإثبات وحدة فضاء
//        المعرّفات (نفس `deviceId` الكاتب) — كانت قبل الإصلاح تُطابق
//        «أول صف» فتربط سجلاً مالياً بموظف آخر بصمت.
//      • المطابقة الرقمية المحلية (fromRemote=false) تبقى تعمل كما هي.
//
//   2) «الابن قبل الأب»: سحبة راتب تصل قبل موظفها:
//      • لا تُهمَل ولا تُكتب بموظف خاطئ ⇒ تُخزَّن كحمولة معلّقة.
//      • عند وصول الموظف تُربط تلقائياً بـ UUID فقط، ولا يُنشأ سجل مكرر
//        لو تكرّرت الدورة (idempotency).
//
//   3) سجل بلا رابط هوية (رقم فقط من جهاز مجهول) ⇒ لا تخمين: يذهب إلى
//      «مراجعة بشرية» مع حفظ دليل التشخيص (الجهاز/الرقم) — البند 12.
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/id_resolver.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/deferred_relation_relinker.dart';
import 'package:marina_hotel_mobile/services/sync_core/deferred_relation_store.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertEmployee({
    required String uuid,
    required String deviceId,
    int? serverId,
  }) {
    final now = Time.nowEpoch();
    return db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            localUuid: uuid,
            createdAt: now,
            updatedAt: now,
            lastModified: now,
            serverId: d.Value(serverId),
            deviceId: d.Value(deviceId),
            origin: d.Value(deviceId == 'server' ? 'server' : 'local'),
            name: 'موظف $uuid',
            basicSalary: 100000,
            status: 'active',
          ),
        );
  }

  /// حمولة سحب راتب بصيغة السحب من Appwrite (نفس ما يمرّ على المحوّل).
  Map<String, dynamic> withdrawalPayload({
    required String uuid,
    String? employeeUuid,
    int? employeeId,
    required String deviceId,
  }) {
    final now = Time.nowEpoch();
    return <String, dynamic>{
      'localUuid': uuid,
      'employeeUuid': employeeUuid,
      'employeeId': employeeId,
      'amount': 500,
      'withdrawDate': '2026-10-01',
      'hotelDayKey': '2026-10-01',
      'reason': 'سحب راتب',
      'deviceId': deviceId,
      'createdAt': now,
      'updatedAt': now,
      'lastModified': now,
    };
  }

  group('G-3/1 — الفضاء الرقمي: لا ربط عبر الأجهزة بلا إثبات', () {
    test('تصادم serverId بين جهازين: UUID يحسم، والرقم يُرفض', () async {
      final resolver = IdResolver(db);

      // الجهاز B أنشأ موظفه #7 أولاً (id محلي أصغر) — وهو «الخطر»:
      final localSevenId = await insertEmployee(
        uuid: 'uuid-devB-emp',
        deviceId: 'devB',
        serverId: 7,
      );
      // ثم وصلت نسخة موظف الجهاز A (رقمه هو أيضاً 7 في فضاء جهازه):
      final pulledId = await insertEmployee(
        uuid: 'uuid-devA-emp',
        deviceId: 'devA',
        serverId: 7,
      );
      expect(localSevenId, lessThan(pulledId));

      // (أ) UUID يحسم دائماً — بغضّ النظر عن الأرقام.
      expect(
        await resolver.resolveEmployee(
          uuid: 'uuid-devA-emp',
          fromRemote: true,
        ),
        pulledId,
      );
      expect(
        await resolver.resolveEmployee(
          uuid: 'uuid-devB-emp',
          fromRemote: true,
        ),
        localSevenId,
      );

      // (ب) الرقم من جهاز A مع إثبات الكاتب ⇒ صفّ الجهاز A (لا الأصغر id).
      expect(
        await resolver.resolveEmployee(
          serverId: 7,
          fromRemote: true,
          sourceDeviceId: 'devA',
        ),
        pulledId,
        reason: 'إثبات فضاء المعرّفات: نفس الجهاز الكاتب',
      );

      // (ج) الرقم بلا دليل ⇒ لا ربط إطلاقاً (كان يربط صفّ الجهاز B خطأً).
      expect(
        await resolver.resolveEmployee(serverId: 7, fromRemote: true),
        isNull,
        reason: 'بلا deviceId لا إثبات ⇒ لا ربط تخميني',
      );

      // (د) الرقم من جهاز ثالث لا يملك الصف ⇒ لا ربط.
      expect(
        await resolver.resolveEmployee(
          serverId: 7,
          fromRemote: true,
          sourceDeviceId: 'devC',
        ),
        isNull,
      );

      // (هـ) المسار المحلي (fromRemote=false) لم يتغيّر: id المحلي يعمل.
      expect(
        await resolver.resolveEmployee(
          localId: localSevenId,
          fromRemote: false,
        ),
        localSevenId,
      );
    });
  });

  group('G-3/2 — الابن قبل الأب: تعليق ثم ربط عبر UUID بلا تكرار', () {
    test('سحبة تصل قبل موظفها: تُخزَّن، ثم تُربط، ولا تتكرر', () async {
      final registry = AdapterRegistry.testing(db);
      final store = DeferredRelationStore(db);
      final relinker =
          DeferredRelationRelinker(db: db, registry: registry, store: store)
            ..install();

      // 1) الحمولة تصل والموظف غير موجود محلياً ⇒ تخطٍّ **غير صامت**.
      final skipped = await registry.salaryWithdrawals.upsertFromJson(
        withdrawalPayload(
          uuid: 'wd-uuid-1',
          employeeUuid: 'emp-remote-uuid',
          employeeId: 7,
          deviceId: 'devA',
        ),
        src: Source.appwrite,
      );
      expect(skipped, -1, reason: 'لم يُكتب سجل بموظف خاطئ');
      expect(
        await db.select(db.salaryWithdrawals).get(),
        isEmpty,
        reason: 'لا سجل مالي بموظف غير صحيح',
      );

      final pending =
          await store.all(states: {DeferredRelationState.pending});
      expect(pending.length, 1, reason: 'الحمولة محفوظة لا مفقودة');
      expect(pending.first.parentUuid, 'emp-remote-uuid');
      expect(pending.first.missingParent, 'employee');
      expect(pending.first.sourceDeviceId, 'devA');

      // 2) وصل الأب (نفس UUID) ⇒ ربط تلقائي عبر UUID فقط.
      final employeeId = await insertEmployee(
        uuid: 'emp-remote-uuid',
        deviceId: 'devA',
        serverId: 7,
      );
      final first = await relinker.relinkAll();
      expect(first.resolved, 1);

      final rows = await db.select(db.salaryWithdrawals).get();
      expect(rows.length, 1);
      expect(rows.first.employeeId, employeeId);
      expect(rows.first.employeeUuid, 'emp-remote-uuid');
      expect(rows.first.amount, 500);
      expect(rows.first.localUuid, 'wd-uuid-1');

      // 3) إعادة الدورة (سحب/دفع متكرر) ⇒ لا سجل مكرر، لا كتابة جديدة.
      final second = await relinker.relinkAll();
      expect(second.resolved, 0);
      final again = await db.select(db.salaryWithdrawals).get();
      expect(again.length, 1, reason: 'idempotency: لا تكرار بالسحب المتكرر');

      // 4) إعادة إرسال نفس الحمولة (echo) ⇒ لا تكرار كذلك.
      await registry.salaryWithdrawals.upsertFromJson(
        withdrawalPayload(
          uuid: 'wd-uuid-1',
          employeeUuid: 'emp-remote-uuid',
          employeeId: 7,
          deviceId: 'devA',
        ),
        src: Source.appwrite,
      );
      expect((await db.select(db.salaryWithdrawals).get()).length, 1);
    });

    test('تعليق متكرر لنفس السجل لا يُنشئ صفوفاً مكررة في المخزن', () async {
      final store = DeferredRelationStore(db);
      final payload = withdrawalPayload(
        uuid: 'wd-uuid-2',
        employeeUuid: 'emp-x',
        employeeId: 3,
        deviceId: 'devA',
      );

      for (var i = 0; i < 3; i++) {
        await store.defer(
          collection: 'salary_withdrawals',
          localUuid: 'wd-uuid-2',
          payload: payload,
          source: 'appwrite',
          missingParent: 'employee',
          parentUuid: 'emp-x',
        );
      }

      final rows = await store.all();
      expect(rows.length, 1, reason: 'مفتاح (collection, local_uuid)');
      expect(rows.first.attempts, 0, reason: 'التعليق لا يُحتسب محاولة فاشلة');
    });
  });

  group('G-3/3 — لا ربط تخميني: المجهول يذهب للمراجعة', () {
    test('رقم فقط + جهاز مجهول ⇒ مراجعة بشرية مع حفظ الدليل', () async {
      final registry = AdapterRegistry.testing(db);
      final store = DeferredRelationStore(db);
      final relinker =
          DeferredRelationRelinker(db: db, registry: registry, store: store)
            ..install();

      // موظف موجود برقم 7 لكنه من جهاز آخر — لا يجوز الربط به.
      await insertEmployee(uuid: 'emp-other', deviceId: 'devZ', serverId: 7);

      final skipped = await registry.salaryWithdrawals.upsertFromJson(
        withdrawalPayload(
          uuid: 'wd-uuid-3',
          employeeId: 7,
          deviceId: 'devUnknown',
        ),
        src: Source.appwrite,
      );
      expect(skipped, -1);

      final result = await relinker.relinkAll();
      expect(result.movedToReview, 1);
      expect(
        await db.select(db.salaryWithdrawals).get(),
        isEmpty,
        reason: 'لا يُربط بموظف لم تُثبت هويته',
      );

      final review = await store.all(
        states: {DeferredRelationState.needsReview},
      );
      expect(review.length, 1);
      expect(review.first.remoteParentId, 7);
      expect(review.first.sourceDeviceId, 'devUnknown');
      expect(review.first.reason, contains('مراجعة'));
    });

    test('معرّف الجلسة المعلّقة يُحفظ كحمولة كاملة (لا فقدان حقول)', () async {
      final store = DeferredRelationStore(db);
      final payload = withdrawalPayload(
        uuid: 'wd-uuid-4',
        employeeUuid: 'emp-y',
        employeeId: 9,
        deviceId: 'devA',
      );

      await store.defer(
        collection: 'salary_withdrawals',
        localUuid: 'wd-uuid-4',
        payload: payload,
        source: 'appwrite',
        missingParent: 'employee',
        parentUuid: 'emp-y',
      );

      final row = (await store.all()).single;
      expect(row.payload['amount'], 500);
      expect(row.payload['employeeUuid'], 'emp-y');
      expect(row.payload['reason'], 'سحب راتب');
      expect(
        row.payload.containsKey('id'),
        isFalse,
        reason: 'لا يُخزَّن id محلي في الحمولة',
      );
    });
  });
}
