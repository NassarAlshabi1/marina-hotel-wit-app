// ============================================================================
// اختبارات البنية المعمارية لمسار Realtime → Delta (2026-09-01) — إلزامية
// ============================================================================
// المواصفة: المسار **الوحيد** المقبول لـ Remote → Local هو:
//
//   Appwrite Cloud → Appwrite Realtime → AppwriteRealtimeSync
//     → (طابور الأحداث: debounce + cooldown + in-flight + trailing)
//     → AppwriteSyncManager / SyncPullService
//     → Field-Level Delta → Drift → Riverpod → UI
//
// الممنوعات المُثبتة هنا وبالتحليل:
//   ✗ Realtime → Drift مباشر            (اختبارات A1/A2)
//   ✗ Realtime → Fast Apply → Drift     (أُزيل من الكود — إثبات A1/A2 + analyze)
//   ✗ Realtime → Full Sync              (اختبار D2: استرداد في bootstrap = صفر قراءات)
//   ✗ Remote Pull → Outbox              (إثبات بالكود enqueueOutbox:false + اختبار B)
//
// التشغيل:
//   flutter test test/services/realtime_pipeline_architecture_test.dart
// ============================================================================

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:appwrite/models.dart' as models;
// ignore: depend_on_referenced_packages (واجهة المنصة لمحاكاة الاتصال فقط)
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
// بنية تحتية (نفس منهجية اختبارات التكامل السابقة — فشل صاخب لأي مسار خفي)
// ─────────────────────────────────────────────────────────────────────────────

class _FakeConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Future<void> ensureInitialized() async {}
}

class _FakeAppwriteService implements AppwriteService {
  final Map<String, List<models.Document>> serverCollections = {};
  final List<String> callNames = [];
  final List<String> readCollections = <String>[];
  final Map<String, List<String>> byIdsRequests = {};

  /// بوابة اختيارية لإبقاء دورة مزامنة "جارية" قسراً (اختبار H2).
  Completer<void>? metadataGate;

  /// مسارات ترمي عمداً (مثل 'listDocumentsMetadata:blacklist') — لاختبار H2.
  final Map<String, Object> throwOn = {};

  void _maybeThrow(String key) {
    final err = throwOn[key];
    if (err != null) throw err;
  }

  @override
  void Function(String collectionId, models.Document document)?
  onDocumentUpserted;

  void reset() {
    serverCollections.clear();
    callNames.clear();
    readCollections.clear();
    byIdsRequests.clear();
    throwOn.clear();
    metadataGate = null;
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
        readCollections.add(collectionId);
        _maybeThrow('listDocumentsMetadata:$collectionId');
        if (metadataGate != null) {
          return metadataGate!.future.then(
            (_) => List<models.Document>.of(
              serverCollections[collectionId] ?? const [],
            ),
          );
        }
        return Future<List<models.Document>>.value(
          List.of(serverCollections[collectionId] ?? const []),
        );

      case 'listDocumentsByIds':
        final collectionId = invocation.positionalArguments[0].toString();
        final ids = (invocation.positionalArguments[1] as List).cast<String>();
        readCollections.add(collectionId);
        byIdsRequests.putIfAbsent(collectionId, () => []).addAll(ids);
        final all = serverCollections[collectionId] ?? const [];
        final idSet = ids.toSet();
        return Future<List<models.Document>>.value(
          all.where((d) => idSet.contains(d.$id)).toList(),
        );

      case 'listDocuments':
        final collectionId = invocation.namedArguments[#collectionId]
            .toString();
        readCollections.add(collectionId);
        return Future<List<models.Document>>.value(
          List.of(serverCollections[collectionId] ?? const []),
        );

      case 'listBookingNights':
        readCollections.add('booking_nights');
        return Future<List<models.Document>>.value(
          List.of(serverCollections['booking_nights'] ?? const []),
        );

      case 'createSyncLog':
        throw StateError('sync-log unavailable (fake)');

      case 'networkHelper':
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

models.Document mkDoc(
  String collectionId,
  String id,
  int updatedAtSec, [
  Map<String, dynamic> data = const {},
]) {
  final iso = DateTime.fromMillisecondsSinceEpoch(
    updatedAtSec * 1000,
    isUtc: true,
  ).toIso8601String();
  return models.Document(
    $id: id,
    $sequence: updatedAtSec,
    $collectionId: collectionId,
    $databaseId: 'main',
    $createdAt: iso,
    $updatedAt: iso,
    $permissions: const [],
    data: Map<String, dynamic>.of(data),
  );
}

/// حمولة حدث Realtime واقعية — Appwrite يرسل المستند نفسه (مع مفاتيح النظام).
Map<String, dynamic> blacklistPayload(
  String id,
  int updatedAtSec, {
  String deviceId = 'device-B',
}) {
  final iso = DateTime.fromMillisecondsSinceEpoch(
    updatedAtSec * 1000,
    isUtc: true,
  ).toIso8601String();
  return <String, dynamic>{
    r'$id': id,
    r'$sequence': updatedAtSec,
    r'$collectionId': 'blacklist',
    r'$databaseId': 'main',
    r'$createdAt': iso,
    r'$updatedAt': iso,
    r'$permissions': <String>[],
    'device_id': deviceId, // جهاز آخر (ليس هذا الجهاز)
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ConnectivityPlatform.instance = _FakeConnectivityPlatform();

  late AppDatabase db;
  late _FakeAppwriteService fake;
  late AppwriteSyncManager manager;
  late AppwriteRealtimeSync realtime;
  late SyncPullService pullService;

  db = AppDatabase.forTesting(NativeDatabase.memory());
  fake = _FakeAppwriteService();
  manager = AppwriteSyncManager(appwriteService: fake, database: db);
  realtime = AppwriteRealtimeSync();
  pullService = SyncPullService(
    appwriteService: fake,
    database: db,
    outboxDao: OutboxDao(db),
  );

  Future<Map<String, int>> entityWatermarks() =>
      pullService.getEntityPullTsMap();

  /// تنظيف كامل بين الاختبارات — قاعدة البيانات مشتركة (أُنشئت مرة) والـ
  /// singleton كذلك؛ بلا هذا يتسرب syncState/الصفوف بين الاختبارات (سبب
  /// فشل A2/D2 في التشغيل المجمّع).
  Future<void> resetAll() async {
    SharedPreferences.setMockInitialValues({});
    fake.reset();
    manager.resetPullThrottleForTesting();
    realtime.resetForTesting();
    realtime.currentDeviceIdForTesting = 'device-A';
    await (db.delete(db.syncState)).go();
    await (db.delete(db.syncRemoteMeta)).go();
    await (db.delete(db.shiftNotes)).go();
    await (db.delete(db.outbox)).go();
  }

  /// ربط الحلقة كما في main.dart تماماً (2026-09-01):
  /// trigger بلا وسائط + deltaOnly:true — لا fast-apply، لا Full Sync.
  /// يتتبع عدد الإطلاقات وأقصى تزامن وآخر نتيجة (pullSkipped).
  ({
    List<int> fireCount,
    List<bool> lastPullSkipped,
    int Function() maxConcurrent,
  })
  wireRealtimeLoop() {
    final fireCount = <int>[0];
    final lastPullSkipped = <bool>[false];
    var concurrent = 0;
    var maxConcurrent = 0;
    realtime.setSyncTrigger(() async {
      fireCount[0]++;
      concurrent++;
      if (concurrent > maxConcurrent) maxConcurrent = concurrent;
      try {
        final result = await manager.sync(
          push: true,
          pull: true,
          realtimePriority: true,
          deltaOnly: true,
        );
        lastPullSkipped[0] = result.pullSkipped;
        return result.isSuccess && !result.pullSkipped;
      } finally {
        concurrent--;
      }
    });
    return (
      fireCount: fireCount,
      lastPullSkipped: lastPullSkipped,
      maxConcurrent: () => maxConcurrent,
    );
  }

  group('A/B: المسار الوحيد — Realtime → طابور → Delta Pull → Drift', () {
    test('A1+B: حدث تعديل من جهاز آخر → لا كتابة قبل الديبونس، ثم الدورة '
        'تجلب من الخادم وتُطبّق field-level في Drift', () {
      fakeAsync((async) {
        unawaited(resetAll());
        async.flushMicrotasks();
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        realtime.debugPullCooldown = Duration.zero;
        final loop = wireRealtimeLoop();

        // خط الأساس: السجل موجود محلياً (نشط) باسم قديم.
        fake.serverCollections['blacklist'] = [
          mkDoc('blacklist', 'blk-1', 1700000000, {
            'name': 'اسم-قديم',
            'active': true,
            'deletedAt': null,
          }),
        ];
        unawaited(manager.sync(push: false, pull: true));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();

        // تعديل من جهاز آخر: الحمولة تحمل الاسم الجديد، والخادم أيضاً.
        fake.serverCollections['blacklist'] = [
          mkDoc('blacklist', 'blk-1', 1700001234, {
            'name': 'اسم-محدَّث-من-جهاز-B',
            'active': true,
            'deletedAt': null,
          }),
        ];
        realtime.handleRemoteDataChange(
          events: [
            'databases.main.collections.blacklist.documents.blk-1.update',
          ],
          payload: blacklistPayload('blk-1', 1700001234),
        );

        // ✅ إثبات إزالة fast-apply: قبل انقضاء الديبونس لا توجد أي كتابة
        // (النسخة القديمة كانت تطبّق من الحمولة هنا فوراً — صفر قراءات).
        async.flushMicrotasks();
        var nameNow = '';
        unawaited(
          (db.select(db.shiftNotes)..where((t) => t.localUuid.equals('blk-1')))
              .getSingleOrNull()
              .then((r) => nameNow = r?.title ?? ''),
        );
        async.flushMicrotasks();
        expect(
          nameNow,
          'اسم-قديم',
          reason: 'لا مسار مباشر من Realtime إلى Drift — الحدث في الطابور فقط',
        );

        // الديبونس انقضى → Delta Pull يجلب من الخادم → field-level merge.
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();

        expect(loop.fireCount[0], greaterThanOrEqualTo(1));
        expect(
          fake.byIdsRequests['blacklist'],
          contains('blk-1'),
          reason: 'البيانات وصلت من Delta Pull (قراءة خادم) لا من الحمولة',
        );
        var nameAfter = '';
        unawaited(
          (db.select(db.shiftNotes)..where((t) => t.localUuid.equals('blk-1')))
              .getSingleOrNull()
              .then((r) => nameAfter = r?.title ?? ''),
        );
        async.flushMicrotasks();
        expect(
          nameAfter,
          'اسم-محدَّث-من-جهاز-B',
          reason: 'التعديل البعيد وصل عبر المسار الوحيد: Queue → Delta → Drift',
        );
      });
    });

    test('A2: بلا trigger ولا fast-apply — الحدث لا يكتب في Drift إطلاقاً', () {
      fakeAsync((async) {
        unawaited(resetAll());
        async.flushMicrotasks();
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        // لا setSyncTrigger — لا setFastApplyHandler (أُزيل من الكود أصلاً:
        // إثبات compile-time عبر flutter analyze + grep).

        fake.serverCollections['blacklist'] = [
          mkDoc('blacklist', 'blk-x', 1700001234, {'name': 'من-جهاز-B'}),
        ];
        realtime.handleRemoteDataChange(
          events: [
            'databases.main.collections.blacklist.documents.blk-x.update',
          ],
          payload: blacklistPayload('blk-x', 1700001234),
        );
        async.elapse(const Duration(milliseconds: 20));
        async.flushMicrotasks();

        var rows = -1;
        unawaited(db.select(db.shiftNotes).get().then((r) => rows = r.length));
        async.flushMicrotasks();
        expect(
          rows,
          0,
          reason: 'بلا نقطة الدخول لا يوجد أي مسار بديل يكتب Drift مباشرة',
        );
      });
    });
  });

  group('C: عاصفة أحداث (Burst) — طابور مُصمت بلا سحوبات متزامنة', () {
    test(
      '10 أحداث متتالية → سحوبات قليلة متتالية (لا storm) وتزامن أقصى = 1',
      () {
        fakeAsync((async) {
          unawaited(resetAll());
          async.flushMicrotasks();
          realtime.debugEventDebounce = const Duration(milliseconds: 5);
          realtime.debugPullCooldown = const Duration(milliseconds: 20);
          final loop = wireRealtimeLoop();

          // خط أساس لتجنب bootstrap (وإلا تُتخطى كل الدلتا وينقلص العدّاد زوراً).
          fake.serverCollections['blacklist'] = [
            mkDoc('blacklist', 'seed', 1700000000, {'name': 'بذرة'}),
          ];
          unawaited(manager.sync(push: false, pull: true));
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 10));
          async.flushMicrotasks();
          final baselineFires = loop.fireCount[0];

          // 10 أحداث متتالية خلال نافذة الديبونس نفسها.
          for (var i = 1; i <= 10; i++) {
            realtime.handleRemoteDataChange(
              events: [
                'databases.main.collections.blacklist.documents.blk-$i.create',
              ],
              payload: blacklistPayload('blk-$i', 1700001000 + i),
            );
            async.flushMicrotasks();
          }

          async.elapse(const Duration(milliseconds: 200));
          async.flushMicrotasks();

          final fired = loop.fireCount[0] - baselineFires;
          expect(
            fired,
            lessThanOrEqualTo(2),
            reason:
                '10 أحداث = دفعة واحدة: 1 in-flight + 1 trailing كحد أقصى '
                '(كانت ستكون 10 سحوبات متزامنة بلا طابور)',
          );
          expect(
            loop.maxConcurrent(),
            1,
            reason:
                'لا سحوبات متزامنة إطلاقاً — حارس in-flight + trailing queue',
          );
        });
      },
    );
  });

  group('D: الاسترداد بعد إعادة الاتصال (إلزامي) — Delta لا Full', () {
    test('D1: disconnect ثم اشتراك ناجح → Delta Pull واحد يستدراك الفاقد', () {
      fakeAsync((async) {
        unawaited(resetAll());
        async.flushMicrotasks();
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        realtime.debugPullCooldown = Duration.zero;
        final loop = wireRealtimeLoop();

        // خط أساس قبل الانقطاع.
        fake.serverCollections['blacklist'] = [
          mkDoc('blacklist', 'seed', 1700000000, {'name': 'بذرة'}),
        ];
        unawaited(manager.sync(push: false, pull: true));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        final baselineFires = loop.fireCount[0];

        // انقطاع: أثناء الانقطاع تغيّر السجل على الخادم (أحداث فُقدان).
        realtime.markDisconnectedForTesting();
        async.flushMicrotasks();
        expect(
          realtime.pendingRecoveryPullForTesting,
          isTrue,
          reason: 'علامة الاسترداد مضبوطة بعد فقدان الاتصال',
        );
        // تغييرات حدثت خلال الانقطاع:
        fake.serverCollections['blacklist'] = [
          mkDoc('blacklist', 'seed', 1700000000, {'name': 'بذرة'}),
          mkDoc('blacklist', 'blk-missed', 1700005000, {
            'name': 'فائت-أثناء-الانقطاع',
          }),
        ];
        // إعادة الاتصال نجحت:
        realtime.onSubscriptionEstablished();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();

        expect(
          loop.fireCount[0],
          greaterThan(baselineFires),
          reason:
              'Reconnect → Delta Pull (استدراك الفاقد) عبر نقطة الدخول الحالية',
        );
        expect(
          fake.byIdsRequests['blacklist'],
          contains('blk-missed'),
          reason: 'التغييرات الفائتة استُدرِكت كاملة بالدلتا',
        );
        var found = false;
        unawaited(
          (db.select(db.shiftNotes)
                ..where((t) => t.localUuid.equals('blk-missed')))
              .get()
              .then((r) => found = r.isNotEmpty),
        );
        async.flushMicrotasks();
        expect(found, isTrue, reason: 'سجل الانقطاع وصل Drift');
        expect(
          realtime.pendingRecoveryPullForTesting,
          isFalse,
          reason: 'الاسترداد يُستهلك مرة واحدة',
        );
      });
    });

    test('D2: استرداد في حالة bootstrap → يُتخطى السحب (صفر قراءات) — '
        'لا Full Sync من Realtime أبداً', () {
      fakeAsync((async) {
        unawaited(resetAll());
        async.flushMicrotasks();
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        realtime.debugPullCooldown = Duration.zero;
        final loop = wireRealtimeLoop();

        // جهاز غير مُهيأ (بلا خط أساس) — الخادم مليء بالبيانات.
        fake.serverCollections['blacklist'] = [
          mkDoc('blacklist', 'big-1', 1700000000, {'name': 'سجل-قديم'}),
          mkDoc('blacklist', 'big-2', 1700000001, {'name': 'سجل-قديم2'}),
        ];

        // انقطاع ثم إعادة اتصال → استرداد:
        realtime.markDisconnectedForTesting();
        async.flushMicrotasks();
        realtime.onSubscriptionEstablished();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();

        expect(
          loop.lastPullSkipped[0],
          isTrue,
          reason: 'deltaOnly يمنع تحويل الاسترداد إلى Full Sync في bootstrap',
        );
        expect(
          fake.readCollections,
          isEmpty,
          reason: 'صفر قراءات شبكة — السحب الكامل قرار Bootstrap الصريح فقط',
        );
      });
    });
  });

  group('E: الحذف البعيد — Realtime DELETE → Queue → Delta → tombstone', () {
    test('حذف من جهاز آخر → يصل عبر الدلتا (تطبيق tombstone) → حذف محلي', () {
      fakeAsync((async) {
        unawaited(resetAll());
        async.flushMicrotasks();
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        realtime.debugPullCooldown = Duration.zero;
        final loop = wireRealtimeLoop();

        // السجل موجود محلياً ونشط.
        fake.serverCollections['blacklist'] = [
          mkDoc('blacklist', 'blk-del', 1700000000, {'name': 'سيُحذف'}),
        ];
        unawaited(manager.sync(push: false, pull: true));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();

        // جهاز B حذف السجل (soft delete بـ deletedAt ISO — صيغة blacklist):
        // الحدث delete لا يُطبَّق مباشرة من الحمولة — يمر عبر الدلتا.
        fake.serverCollections['blacklist'] = [
          mkDoc('blacklist', 'blk-del', 1700006000, {
            'name': 'سيُحذف',
            'deletedAt': '2026-09-01T10:00:00.000Z',
          }),
        ];
        realtime.handleRemoteDataChange(
          events: [
            'databases.main.collections.blacklist.documents.blk-del.delete',
          ],
          payload: blacklistPayload('blk-del', 1700006000),
        );
        async.flushMicrotasks();
        var stillThere = true;
        unawaited(
          (db.select(db.shiftNotes)
                ..where((t) => t.localUuid.equals('blk-del')))
              .get()
              .then((r) => stillThere = r.isNotEmpty),
        );
        async.flushMicrotasks();
        expect(
          stillThere,
          isTrue,
          reason:
              'لا حذف مباشر من الحدث — tombstone منطق الدلتا هو آلية التوصيل',
        );

        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();

        expect(loop.fireCount[0], greaterThanOrEqualTo(1));
        expect(
          fake.byIdsRequests['blacklist'],
          contains('blk-del'),
          reason:
              'السجل معروف محلياً → يُنزَّل tombstone لتوصيل الحذف (منع resurrection)',
        );
        stillThere = false;
        unawaited(
          (db.select(db.shiftNotes)
                ..where((t) => t.localUuid.equals('blk-del')))
              .get()
              .then((r) => stillThere = r.isNotEmpty),
        );
        async.flushMicrotasks();
        expect(
          stillThere,
          isFalse,
          reason:
              'Remote delete → Realtime → Queue → Delta → tombstone → local delete',
        );
      });
    });
  });

  group('F: Logout/Login — لا اشتراكات متبقية من الجلسة السابقة', () {
    test('stop() يغلق كل شيء ويفرّغ الطابور؛ ثم login يبدأ نظيفاً', () {
      fakeAsync((async) {
        unawaited(resetAll());
        async.flushMicrotasks();
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        realtime.debugPullCooldown = Duration.zero;
        final loop = wireRealtimeLoop();

        // Login أول: اشتراك فعّال + حدث في الطابور.
        realtime.onSubscriptionEstablished();
        async.flushMicrotasks();
        realtime.handleRemoteDataChange(
          events: ['databases.main.collections.blacklist.documents.p1.create'],
          payload: blacklistPayload('p1', 1700001000),
        );
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(loop.fireCount[0], greaterThanOrEqualTo(1));

        // Logout: إيقاف إرادي.
        unawaited(realtime.stop());
        async.flushMicrotasks();
        expect(realtime.isListening, isFalse);
        expect(
          realtime.triggerInFlightForTesting,
          isFalse,
          reason: 'لا دورة معلّقة بعد الخروج',
        );
        expect(
          realtime.pendingRecoveryPullForTesting,
          isFalse,
          reason: 'لا استرداد بعد توقف إرادي',
        );

        // أحداث متأخرة بعد stop → لا سحب ولا شارة (الاشتراك مغلق).
        realtime.handleRemoteDataChange(
          events: ['databases.main.collections.blacklist.documents.p2.create'],
          payload: blacklistPayload('p2', 1700002000),
        );
        async.elapse(const Duration(milliseconds: 20));
        async.flushMicrotasks();
        final firesAfterLogout = loop.fireCount[0];
        async.elapse(const Duration(milliseconds: 20));
        expect(
          loop.fireCount[0],
          firesAfterLogout,
          reason: 'بلا اشتراك حي لا يُطلق أي سحب (الطابور مُفرَّغ)',
        );

        // Login جديد: اشتراك جديد نظيف — استرداد واحد للفجوة فقط.
        realtime.markDisconnectedForTesting();
        async.flushMicrotasks();
        realtime.onSubscriptionEstablished();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(
          realtime.pendingRecoveryPullForTesting,
          isFalse,
          reason: 'الاشتراك الجديد استهلك الاسترداد (فجوة logout→login)',
        );
      });
    });
  });

  group('G: Realtime غير متاح — المزامنة اليدوية تبقى عاملة', () {
    test(
      'بلا أي trigger: sync يدوي يسحب ويطبّق (مسار DashboardSyncButton)',
      () {
        fakeAsync((async) {
          SharedPreferences.setMockInitialValues({
            'appwrite_realtime_sync_enabled': false, // Realtime معطّل كلياً
          });
          fake.reset();
          manager.resetPullThrottleForTesting();
          realtime.resetForTesting();
          realtime.debugEventDebounce = const Duration(milliseconds: 5);

          fake.serverCollections['blacklist'] = [
            mkDoc('blacklist', 'manual-1', 1700003000, {'name': 'يدوي'}),
          ];

          var ok = false;
          unawaited(
            manager
                .sync(push: false, pull: true, forcePull: true)
                .then((r) => ok = r.isSuccess),
          );
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 10));
          async.flushMicrotasks();

          expect(ok, isTrue, reason: 'المزامنة اليدوية لا تعتمد على Realtime');
          var found = false;
          unawaited(
            (db.select(db.shiftNotes)
                  ..where((t) => t.localUuid.equals('manual-1')))
                .get()
                .then((r) => found = r.isNotEmpty),
          );
          async.flushMicrotasks();
          expect(found, isTrue);
        });
      },
    );
  });

  group('H: Bootstrap الصريح — علم appwrite_pull_after_drive_skip_done', () {
    test('H1: نجاح السحب الشامل → true (العلم يُضبط بعده فقط)', () {
      fakeAsync((async) {
        unawaited(resetAll());
        async.flushMicrotasks();

        // خادم فارغ → سحب شامل نظيف ينتهي بنجاح.
        var ok = false;
        unawaited(manager.pullAllDataWithDisabledFK().then((v) => ok = v));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));
        async.flushMicrotasks();
        expect(ok, isTrue, reason: 'SUCCESS → المستدعي يضبط العلم بعدها');
      });
    });

    test('H2: دورة مزامنة جارية → pullAllDataWithDisabledFK تُرجع false — '
        'العلم لا يُضبط (لا سحب حصل)', () {
      fakeAsync((async) {
        unawaited(resetAll());
        async.flushMicrotasks();

        // إبقاء دورة مزامنة «جارية» قسراً عبر بوابة metadata:
        fake.metadataGate = Completer<void>();
        fake.serverCollections['blacklist'] = [
          mkDoc('blacklist', 'busy-1', 1700000000, {'name': 'مشغول'}),
        ];
        unawaited(manager.sync(push: false, pull: true));
        async.flushMicrotasks();

        var ok = true;
        unawaited(manager.pullAllDataWithDisabledFK().then((v) => ok = v));
        async.flushMicrotasks();
        expect(
          ok,
          isFalse,
          reason: 'syncing جارية → لم يحدث سحب شامل → false → العلم لا يُضبط',
        );

        // تحرير الدورة وتنظيف.
        fake.metadataGate!.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));
        async.flushMicrotasks();
      });
    });

    test(
      'H3: عقود العلم النقية — يُضبط بعد النجاح حصراً (نفس ترتيب الشاشة)',
      () async {
        SharedPreferences.setMockInitialValues({});
        // نفس منطق _pullAppwriteOnceAfterSkip في google_drive_login_screen.dart:
        //   if (done) return;  →  ok = await pull();  →  if (ok) setFlag.
        Future<bool> runBootstrapFlow(
          SharedPreferences prefs,
          Future<bool> Function() pull,
        ) async {
          const key = 'appwrite_pull_after_drive_skip_done';
          if (prefs.getBool(key) ?? false) return false;
          final ok = await pull();
          if (!ok) return false;
          await prefs.setBool(key, true);
          return true;
        }

        // نجاح → علم مرفوع.
        final prefs1 = await SharedPreferences.getInstance();
        var pulls1 = 0;
        final r1 = await runBootstrapFlow(prefs1, () async {
          pulls1++;
          return true;
        });
        expect(r1, isTrue);
        expect(pulls1, 1);
        expect(
          await prefs1.getBool('appwrite_pull_after_drive_skip_done'),
          isTrue,
        );

        // فشل → العلم فارغ + إعادة المحاولة ممكنة (يدعو pull ثانية).
        SharedPreferences.setMockInitialValues({}); // مخزن معزول لهذا السيناريو
        final prefs2 = await SharedPreferences.getInstance();
        var pulls2 = 0;
        final r2a = await runBootstrapFlow(prefs2, () async {
          pulls2++;
          return false; // Full Sync FAILURE
        });
        expect(r2a, isFalse);
        expect(
          await prefs2.getBool('appwrite_pull_after_drive_skip_done'),
          isNull,
        );
        final r2b = await runBootstrapFlow(prefs2, () async {
          pulls2++;
          return true; // إعادة المحاولة نجحت
        });
        expect(r2b, isTrue);
        expect(pulls2, 2, reason: 'الفشل سمح بإعادة المحاولة');

        // علم مرفوع مسبقاً → idempotent (لا سحب ثانٍ).
        var pulls3 = 0;
        final r3 = await runBootstrapFlow(prefs1, () async {
          pulls3++;
          return true;
        });
        expect(r3, isFalse);
        expect(pulls3, 0);
      },
    );
  });
}
