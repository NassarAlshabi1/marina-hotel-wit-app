// ============================================================================
//  اختبارات تكامل عميقة — تفعيل Realtime الكامل (2026-08-31)
// ============================================================================
//  الهدف: إثبات أن "حدث Realtime → سحب فعلي" يعمل عبر المسار العام الحقيقي
//  AppwriteSyncManager.sync() — المدير الحقيقي + قاعدة Drift في الذاكرة +
//  تزييف طبقة الشبكة فقط (نفس منهجية sync_metadata_first_integration_test).
//
//  ما تثبته:
//   M1  (شرط أساسي) حارس الدقيقتين يقيّد المداخل العادية: دورة ثانية مباشرة
//       بلا realtimePriority → "Pull skipped: minimum pull gap not reached".
//   M2  sync(realtimePriority: true) يتجاوز حارس الدقيقتين: دورة ثانية مباشرة
//       بعد دورة ناجحة → تعمل فعلاً (listDocumentsMetadata مستدعاة مجدداً).
//   M3  عند تخطّي السحب (حارس) مع استكمال الرفع → pullSkipped = true يصل
//       للمستدعي (عقد مدخل Realtime) وresult isSuccess (الرفع تم).
//   M4  الحلقة الكاملة: حدث Realtime من جهاز آخر → ديبونس → trigger محقون →
//       sync(push+pull, realtimePriority) → سحب metadata حقيقي حدث،
//       وresult نجاح → شارات AppwriteRealtimeSync صُفّرت.
//       (يُجرى بعد دورة ناجحة مباشرة — أي أن الحدث يتجاوز الحارس فعلياً.)
//
//  التشغيل:
//    flutter test test/unit/realtime_priority_sync_integration_test.dart
// ============================================================================

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:appwrite/models.dart' as models;
// ignore: depend_on_referenced_packages (واجهة المنصة مستخدمة لمحاكاة الاتصال في الاختبار فقط)
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_network_helper.dart';
import 'package:marina_hotel_mobile/services/appwrite_realtime_sync.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// بنية تحتية (نفس منهجية sync_metadata_first_integration_test)
// ─────────────────────────────────────────────────────────────────────────────

class _FakeConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  /// في M4 يُجرى فحص الاتصال داخل fakeAsync — نجعله دقيقة عبر microtask.
  @override
  Future<void> ensureInitialized() async {}
}

/// خدمة Appwrite وهمية — فشل صاخب لكل استدعاء غير متوقع.
class _FakeAppwriteService implements AppwriteService {
  final Map<String, List<models.Document>> serverCollections = {};
  final List<String> callNames = [];

  void reset() {
    serverCollections.clear();
    callNames.clear();
  }

  String _memberName(Invocation invocation) {
    final raw = invocation.memberName.toString();
    final start = raw.indexOf('"');
    return start >= 0 ? raw.substring(start + 1, raw.length - 2) : raw;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = _memberName(invocation);
    callNames.add(name);

    switch (name) {
      case 'initialize':
        return Future<void>.value();

      case 'isInitialized':
        return true;

      case 'listDocumentsMetadata':
        final collectionId = invocation.positionalArguments[0].toString();
        return Future<List<models.Document>>.value(
          List.of(serverCollections[collectionId] ?? const []),
        );

      case 'listDocumentsByIds':
        final collectionId = invocation.positionalArguments[0].toString();
        final ids = (invocation.positionalArguments[1] as List).cast<String>();
        final all = serverCollections[collectionId] ?? const [];
        final idSet = ids.toSet();
        return Future<List<models.Document>>.value(
          all.where((d) => idSet.contains(d.$id)).toList(),
        );

      case 'listDocuments':
        final named = invocation.namedArguments;
        final collectionId = named[#collectionId].toString();
        return Future<List<models.Document>>.value(
          List.of(serverCollections[collectionId] ?? const []),
        );

      case 'listBookingNights':
        return Future<List<models.Document>>.value(
          List.of(serverCollections['booking_nights'] ?? const []),
        );

      case 'createSyncLog':
        // سجل المزامنة السحابي غير حرج — المسار يستمر بلا سجل.
        throw StateError('sync-log unavailable (fake)');

      case 'networkHelper':
        // مسار الرفع يقرأ حالة الـ circuit breaker — نسخة حقيقية بلا شبكة.
        return AppwriteNetworkHelper();

      case 'quickConnectionTest':
        return Future<bool>.value(true);
    }

    throw StateError(
      '_FakeAppwriteService: استدعاء غير متوقع → $name. '
      'إذا كان شرعياً في دورة السحب أضفه صراحةً إلى الـ fake.',
    );
  }
}

models.Document mkDoc(String id, int updatedAtSec) {
  final iso = DateTime.fromMillisecondsSinceEpoch(
    updatedAtSec * 1000,
    isUtc: true,
  ).toIso8601String();
  return models.Document(
    $id: id,
    $sequence: updatedAtSec,
    $collectionId: 'blacklist',
    $databaseId: 'main',
    $createdAt: iso,
    $updatedAt: iso,
    $permissions: const [],
    data: const {},
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// الحزمة
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ConnectivityPlatform.instance = _FakeConnectivityPlatform();

  late AppDatabase db;
  late _FakeAppwriteService fake;
  late AppwriteSyncManager manager;
  late AppwriteRealtimeSync realtime;

  db = AppDatabase.forTesting(NativeDatabase.memory());
  fake = _FakeAppwriteService();
  manager = AppwriteSyncManager(appwriteService: fake, database: db);
  realtime = AppwriteRealtimeSync();

  Future<void> resetState() async {
    SharedPreferences.setMockInitialValues({});
    fake.reset();
    manager.resetPullThrottleForTesting();
    realtime.resetForTesting();
    await (db.delete(db.syncState)).go();
    await (db.delete(db.syncRemoteMeta)).go();
    await (db.delete(db.shiftNotes)).go();
    await (db.delete(db.outbox)).go();
  }

  Future<SyncResult> runNormalPull() => manager.sync(push: false, pull: true);

  group('M1/M2/M3: حارس الدقيقتين مقابل realtimePriority', () {
    setUp(resetState);

    test('M1: دورة عادية ثانية مباشرة → يمنعها حارس الدقيقتين', () async {
      fake.serverCollections['blacklist'] = [mkDoc('A', 1700001000)];

      final first = await runNormalPull();
      expect(first.isSuccess, isTrue, reason: 'الدورة الأولى سليمة');

      fake.reset(); // تعقّب استدعاءات الدورة الثانية فقط

      final second = await runNormalPull();
      expect(second.status, SyncStatus.idle);
      expect(second.errorMessage, contains('Pull skipped: minimum pull gap'));
      // السحب لم يحدث فعلاً — لا استدعاءات شبكة metadata.
      expect(
        fake.callNames.where((n) => n == 'listDocumentsMetadata'),
        isEmpty,
        reason: 'الحارس منع السحب العادي المتقارب',
      );
    });

    test('M2: realtimePriority يتجاوز الحارس → دورة سحب فعلية ثانية', () async {
      fake.serverCollections['blacklist'] = [mkDoc('A', 1700001000)];

      final first = await runNormalPull();
      expect(first.isSuccess, isTrue);

      fake.reset();

      // الحدث الواقعي: تغيير وصل مباشرة بعد دورة — يجب ألا يمنعه الحارس.
      final second = await manager.sync(
        push: false,
        pull: true,
        realtimePriority: true,
      );

      expect(
        second.isSuccess,
        isTrue,
        reason: 'realtimePriority يتجاوز حارس الدقيقتين',
      );
      // بعد اكتمال أول سحب، الدورة الثانية تعمل بوضع delta (listDocuments)
      // لا metadata-first — المهم أنها **حدثت فعلاً**.
      expect(
        fake.callNames,
        contains('listDocuments'),
        reason: 'السحب الثاني (delta) حدث فعلاً',
      );
      expect(second.pullSkipped, isFalse);
    });

    test('M3: تخطّي السحب بالحارس مع رفع سليم → pullSkipped=true يصل '
        'للمستدعي', () async {
      fake.serverCollections['blacklist'] = [mkDoc('A', 1700001000)];

      final first = await runNormalPull();
      expect(first.isSuccess, isTrue);

      fake.reset();

      // push+pull عادي متقارب: الحارس يخفض pull ويكمل push (الoutbox فارغ).
      final result = await manager.sync(push: true, pull: true);

      expect(
        result.isSuccess,
        isTrue,
        reason: 'دورة الرفع فقط اكتملت بنجاح (outbox فارغ)',
      );
      expect(
        result.pullSkipped,
        isTrue,
        reason: 'علامة pullSkipped إلزامية كي يُتابع مدخل Realtime',
      );
      expect(
        fake.callNames.where((n) => n == 'listDocumentsMetadata'),
        isEmpty,
        reason: 'لا سحب فعلي في هذه الدورة',
      );
    });
  });

  group('M4: الحلقة الكاملة — حدث Realtime → سحب فعلي عبر المدير الحقيقي', () {
    setUp(resetState);

    test(
      'حدث من جهاز آخر يُطلق sync(realtimePriority) حقيقية ويتجاوز الحارس',
      () {
        fakeAsync((async) {
          SharedPreferences.setMockInitialValues({});
          fake.reset();
          manager.resetPullThrottleForTesting();
          realtime.resetForTesting();
          realtime.currentDeviceIdForTesting = 'device-A';
          realtime.debugEventDebounce = const Duration(milliseconds: 5);

          // المحتوى الخادمي: مستند يحمل أقصى $updatedAt معروفاً.
          fake.serverCollections['blacklist'] = [mkDoc('A', 1700001000)];

          // ربط الحلقة كما في main.dart تماماً.
          var triggerCalls = 0;
          var lastTriggerResult = true;
          realtime.setSyncTrigger(() async {
            triggerCalls++;
            final result = await manager.sync(
              push: true,
              pull: true,
              realtimePriority: true,
            );
            lastTriggerResult = result.isSuccess && !result.pullSkipped;
            return lastTriggerResult;
          });

          // دورة سحب عادية سابقة (تضبط ساعة الحارس — تماماً كالواقع).
          unawaited(manager.sync(push: false, pull: true));
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 10));
          async.flushMicrotasks();
          expect(
            fake.callNames.where((n) => n == 'listDocumentsMetadata'),
            isNotEmpty,
          );
          fake.reset(); // تعقّب ما يحدث بعد الحدث فقط

          // ✅ الحدث: جهاز B أنشأ حجزاً — خلال ثوانٍ يجب أن يُسحب فعلياً.
          realtime.handleRemoteDataChange(
            events: ['databases.main.collections.bookings.documents.create'],
            payload: {
              'device_id': 'device-B',
              r'$updatedAt': '2026-08-31T12:00:00.000Z',
            },
          );

          async.elapse(const Duration(milliseconds: 20));
          async.flushMicrotasks();

          expect(triggerCalls, 1, reason: 'الحدث أطلق دورة sync واحدة');
          expect(
            lastTriggerResult,
            isTrue,
            reason:
                'الدورة نجحت والسحب تم (بلا pullSkipped) رغم أن الدورة '
                'السابقة انتهت قبل ثوانٍ — تجاوز الحارس عبر realtimePriority',
          );
          // الدورة المُطلَقة بالحدث تعمل بوضع delta (listDocuments) لأن أول
          // سحب اكتمل قبلها — المهم أنها حدثت فعلاً بتجاوز الحارس.
          expect(
            fake.callNames,
            contains('listDocuments'),
            reason: 'سحب delta حقيقي حدث نتيجة الحدث مباشرة',
          );
          expect(
            realtime.hasRemoteChanges.value,
            isFalse,
            reason: 'السحب نجح → شارة "تغييرات معلقة" صُفّرت',
          );
          expect(realtime.pendingRemoteChangesCount.value, 0);
        });
      },
    );
  });
}
