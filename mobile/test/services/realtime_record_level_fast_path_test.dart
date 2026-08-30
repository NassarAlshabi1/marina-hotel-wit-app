// ============================================================================
//  اختبارات عميقة — المسار السريع على مستوى السجل (Realtime Fast-Path)
//  تقليل السحب: الحدث يحمل السجل كاملاً → يُطبَّق مباشرة (صفر قراءات شبكة)
//  والكيان يتخطى الـ delta في الدورة التالية فقط. (2026-08-31)
// ============================================================================
//  المنهجية: نفس منهجية sync_metadata_first_integration_test و
//  realtime_priority_sync_integration_test — المدير الحقيقي + Drift في
//  الذاكرة + طبقة شبكة وهمية "فشل صاخب" لكل استدعاء غير متوقع.
//
//  ملاحظة: كيان blacklist يُخزَّن محلياً في جدول shift_notes (كما في الكود).
//
//  ما تثبته:
//   RL1  تحليل حدث Appwrite إلى (collection, document, action) بدقة،
//        ورفض أحداث permissions/النظام.
//   RL2  حدث update من جهاز آخر → السجل يُطبَّق محلياً من الحمولة مع
//        **صفر استدعاءات شبكة**، وتُحدَّث sync_remote_meta للسجل.
//   RL3  المؤشر (watermark) لا يتقدم من المسار السريع، والدورة المُطلقة
//        تتخطى delta للكيان المطبَّق فقط، والدورة التالية تعيد سحبه.
//   RL4  السحب الكامل (isDelta=false) لا يتأثر بمجموعة التخطي أبداً.
//   RL5  حدث delete لا يمر بالمسار السريع (tombstones فقط عبر الدورة).
//   RL6  فشل التطبيق السريع → بلا تعليم → الدelta تسحب الكيان.
//   RL7  مجموعة التخطي دورية: ما يُعلَّم بين دورتين فقط هو ما يُتخطى.
//   RL8  أثناء دورة مزامنة جارية → applyRemoteRecordFast يرفض (false).
//   RL9  مجموعات/حمولات غير مؤهلة → false (devices، نقص $updatedAt).
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
// بنية تحتية (نفس منهجية اختبارات التكامل السابقة)
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

  /// إثبات على مستوى السجل: أي مجموعة سُئلت عبر أي مسار قراءة.
  final List<String> readCollections = [];

  /// بوابة اختيارية لإبقاء دورة مزامنة "جارية" قسراً (اختبار RL8).
  Completer<void>? metadataGate;

  void reset() {
    serverCollections.clear();
    callNames.clear();
    readCollections.clear();
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
        if (metadataGate != null) {
          // بوابة مُكتوبة بشكل صحيح: تبقي الدورة "جارية" دون TypeError.
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

models.Document mkDoc(String collectionId, String id, int updatedAtSec) {
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
    data: const {},
  );
}

/// حمولة حدث Realtime واقعية — Appwrite يرسل المستند نفسه (مع مفاتيح النظام).
Map<String, dynamic> blacklistPayload(String id, int updatedAtSec) {
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
    'device_id': 'device-B', // جهاز آخر (ليس هذا الجهاز)
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

  Future<Map<String, int>> entityWatermarks() =>
      pullService.getEntityPullTsMap();

  /// ربط الحلقة كما في main.dart تماماً (trigger + fast-apply handler).
  /// handlerResult يمكن تغييره وقتياً لمحاكاة فشل التطبيق السريع.
  ({
    List<Set<String>> receivedSkipSets,
    List<int> fireCount,
    void Function(bool) setHandlerResult,
  })
  wireRealtimeLoop() {
    final receivedSkipSets = <Set<String>>[];
    final fireCount = <int>[0];
    var handlerResult = true;
    realtime.setSyncTrigger((fastAppliedEntities) async {
      fireCount[0]++;
      receivedSkipSets.add(Set<String>.of(fastAppliedEntities));
      final result = await manager.sync(
        push: true,
        pull: true,
        realtimePriority: true,
        fastAppliedEntities: fastAppliedEntities,
      );
      return result.isSuccess && !result.pullSkipped;
    });
    realtime.setFastApplyHandler((collectionId, documentId, payload) async {
      if (!handlerResult) return false;
      return manager.applyRemoteRecordFast(
        collectionId: collectionId,
        documentId: documentId,
        payload: payload,
      );
    });
    return (
      receivedSkipSets: receivedSkipSets,
      fireCount: fireCount,
      setHandlerResult: (v) => handlerResult = v,
    );
  }

  group('RL1: تحليل حدث Appwrite', () {
    test('حدث مستند كامل → (collection, document, action) صحيحة', () {
      final parsed = AppwriteRealtimeSync.parseDatabaseEvent([
        'databases.main.collections.payments.documents.doc-9-update.update',
      ]);
      expect(parsed.collectionId, 'payments');
      expect(parsed.documentId, 'doc-9-update');
      expect(parsed.action, 'update');
    });

    test('حدث permissions (مورد فرعي) → يُرفض ليس سجلاً', () {
      final parsed = AppwriteRealtimeSync.parseDatabaseEvent([
        'databases.main.collections.bookings.documents.abc.permissions.update',
      ]);
      expect(parsed.action, isNull);
    });

    test('حدث delete يُتعرف عليه بوضوح (ليقرر المسار السريع تجاهله)', () {
      final parsed = AppwriteRealtimeSync.parseDatabaseEvent([
        'databases.main.collections.expenses.documents.ex-1.delete',
      ]);
      expect(parsed.action, 'delete');
      expect(parsed.collectionId, 'expenses');
      expect(parsed.documentId, 'ex-1');
    });

    test('حدث غير بيانات (نظام) → null', () {
      final parsed = AppwriteRealtimeSync.parseDatabaseEvent([
        'account.sessions.create',
      ]);
      expect(parsed.action, isNull);
    });
  });

  group('RL2/RL3: حدث → تطبيق مباشر → تخطي delta دوري → عودة الكمال', () {
    setUp(resetState);

    test('RL2+RL3: الحمولة تُطبَّق بلا أي قراءة شبكة، الميتاداتا تُحدَّث، '
        'المؤشر لا يتحرك، الدورة تتخطى الكيان، والدورة التالية تعيد سحبه', () {
      fakeAsync((async) {
        SharedPreferences.setMockInitialValues({});
        manager.resetPullThrottleForTesting();
        realtime.resetForTesting();
        realtime.currentDeviceIdForTesting = 'device-A';
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        final loop = wireRealtimeLoop();

        // دورة أولى عادية تضبط خط الأساس (watermark لـ blacklist).
        fake.serverCollections['blacklist'] = [
          mkDoc('blacklist', 'seed', 1700000000),
        ];
        unawaited(manager.sync(push: false, pull: true));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();

        // ⚡ الحدث: مستند جديد من جهاز آخر — لا وجود له على الخادم الافتراضي
        // كي نثبت أن الوصول المحلي جاء من الحمولة لا من أي قراءة شبكة.
        fake.reset();
        realtime.handleRemoteDataChange(
          events: [
            'databases.main.collections.blacklist.documents.blk-fast-1.update',
          ],
          payload: blacklistPayload('blk-fast-1', 1700001234),
        );

        // التطبيق السريع microtask — قبل إطلاق الدورة (ديبونس 5ms).
        async.flushMicrotasks();
        expect(
          fake.callNames,
          isEmpty,
          reason: 'التطبيق السريع استخدم صفر قراءات شبكة',
        );

        // السجل وصل محلياً فعلاً (جدول shift_notes — مخزن blacklist).
        var fastRowFound = false;
        unawaited(
          (db.select(db.shiftNotes)
                ..where((t) => t.localUuid.equals('blk-fast-1')))
              .get()
              .then((r) => fastRowFound = r.isNotEmpty),
        );
        async.flushMicrotasks();
        expect(fastRowFound, isTrue, reason: 'السجل طُبّق من الحمولة مباشرة');

        // خريطة الميتاداتا تحمل ts الحمولة (تُغذي السحب الكامل القادم).
        var metaTs = 0;
        unawaited(
          db
              .getRemoteMetaMap('blacklist')
              .then((m) => metaTs = m['blk-fast-1'] ?? 0),
        );
        async.flushMicrotasks();
        expect(
          metaTs,
          1700001234,
          reason: 'sync_remote_meta حُدّثت بعد النجاح',
        );

        // ✅ RL3 (الجوهر): المؤشر الخاص بـ blacklist لم يتقدم — ما زال
        // عند بذرة الدورة الأولى (1700000000) وليس ts الحدث (1700001234).
        var watermark = 0;
        unawaited(
          entityWatermarks().then((m) => watermark = m['blacklist'] ?? 0),
        );
        async.flushMicrotasks();
        expect(
          watermark,
          1700000000,
          reason:
              'المسار السريع لا يحرك المؤشر — الدلتا الدورية '
              'تبقى مصدر الكمال',
        );

        // الدورة المُطلقة بعد الحدث: تستلم {blacklist} في مجموعة التخطي.
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(loop.fireCount[0], 1, reason: 'دورة واحدة أُطلقت للحدث');
        expect(
          loop.receivedSkipSets.first,
          {'blacklist'},
          reason: 'الكيان المطبَّق يُمرَّر للدورة كي يتخطى delta',
        );
        expect(
          fake.readCollections.where((c) => c == 'blacklist'),
          isEmpty,
          reason: 'delta السحب تخطّت blacklist في هذه الدورة',
        );
        expect(
          fake.readCollections,
          isNotEmpty,
          reason: 'بقية الكيانات سُحبت delta كالمعتاد',
        );

        // الدورة التالية (بلا مجموعة تخطٍ): delta تعود لسحب blacklist.
        fake.serverCollections['blacklist'] = [
          mkDoc('blacklist', 'seed', 1700000000),
          mkDoc('blacklist', 'blk-fast-1', 1700001234),
        ];
        fake.reset();
        manager.resetPullThrottleForTesting();
        unawaited(manager.sync(push: false, pull: true));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(
          fake.readCollections.where((c) => c == 'blacklist'),
          isNotEmpty,
          reason:
              'الدورة التالية أعادت سحب blacklist delta — '
              'التخطي دوري وليس دائماً',
        );
      });
    });
  });

  group('RL4/RL5/RL6/RL7: حدود المسار السريع', () {
    setUp(resetState);

    test('RL4: السحب الكامل لا يتأثر بمجموعة التخطي أبداً', () async {
      // قاعدة نظيفة → السحب القادم full (metadata-first) حتى مع مجموعة تخطٍ.
      fake.serverCollections['blacklist'] = [
        mkDoc('blacklist', 'A', 1700001000),
      ];
      await manager.sync(
        push: false,
        pull: true,
        fastAppliedEntities: {'blacklist'},
      );
      expect(
        fake.readCollections.where((c) => c == 'blacklist'),
        isNotEmpty,
        reason: 'السحب الكامل يجيب metadata لـ blacklist رغم مجموعة التخطي',
      );
    });

    test('RL5: حدث delete لا يمر بالمسار السريع', () {
      fakeAsync((async) {
        manager.resetPullThrottleForTesting();
        realtime.resetForTesting();
        realtime.currentDeviceIdForTesting = 'device-A';
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        final loop = wireRealtimeLoop();

        realtime.handleRemoteDataChange(
          events: [
            'databases.main.collections.blacklist.documents.blk-del.delete',
          ],
          payload: blacklistPayload('blk-del', 1700002000),
        );
        async.flushMicrotasks();

        expect(
          fake.callNames,
          isEmpty,
          reason: 'delete لا يُطبَّق من الحمولة (tombstones عبر الدورة فقط)',
        );
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(
          loop.receivedSkipSets.first,
          isEmpty,
          reason: 'بلا تعليم للكيان — الدورة تسحبه delta كالمعتاد',
        );
      });
    });

    test('RL6: فشل التطبيق السريع → بلا تعليم → الدورة تسحب الكيان', () {
      fakeAsync((async) {
        manager.resetPullThrottleForTesting();
        realtime.resetForTesting();
        realtime.currentDeviceIdForTesting = 'device-A';
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        final loop = wireRealtimeLoop();
        loop.setHandlerResult(false); // محاكاة فشل أي تطبيق سريع

        realtime.handleRemoteDataChange(
          events: [
            'databases.main.collections.blacklist.documents.blk-x.update',
          ],
          payload: blacklistPayload('blk-x', 1700003000),
        );
        async.flushMicrotasks();

        var rowFound = false;
        unawaited(
          (db.select(db.shiftNotes)..where((t) => t.localUuid.equals('blk-x')))
              .get()
              .then((r) => rowFound = r.isNotEmpty),
        );
        async.flushMicrotasks();
        expect(rowFound, isFalse, reason: 'التطبيق فشل — لا صف محلي');

        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(
          loop.receivedSkipSets.first,
          isEmpty,
          reason: 'الفشل لا يُعلّم الكيان — الدelta ستحضر السجل',
        );
      });
    });

    test('RL7: المجموعة دورية — الدورة الثانية لا ترى بقايا الدورة الأولى', () {
      fakeAsync((async) {
        manager.resetPullThrottleForTesting();
        realtime.resetForTesting();
        realtime.currentDeviceIdForTesting = 'device-A';
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        realtime.debugPullCooldown = Duration.zero;
        final loop = wireRealtimeLoop();

        // حدث أول → تطبيق ناجح → تعليم → الدورة الأولى تستلم {blacklist}.
        realtime.handleRemoteDataChange(
          events: [
            'databases.main.collections.blacklist.documents.blk-1.update',
          ],
          payload: blacklistPayload('blk-1', 1700004001),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(loop.fireCount[0], 1);
        expect(loop.receivedSkipSets.first, {'blacklist'});

        // حدث ثانٍ بفشل تطبيق مقصود → لا تعليم جديد. الدورة الثانية تستلم
        // مجموعة فارغة — إثبات أن بقايا الحدث الأول مُسحت عند محاولته.
        loop.setHandlerResult(false);
        realtime.handleRemoteDataChange(
          events: [
            'databases.main.collections.blacklist.documents.blk-2.update',
          ],
          payload: blacklistPayload('blk-2', 1700004002),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();

        expect(loop.fireCount[0], 2);
        expect(
          loop.receivedSkipSets.last,
          isEmpty,
          reason: 'لا تراكم عبر الدورات: تعليم كل حدث يُستهلك بدورته',
        );
      });
    });
  });

  group('RL8/RL9: حراس applyRemoteRecordFast', () {
    setUp(resetState);

    test('RL8: أثناء دورة مزامنة جارية → يرفض بلا كتابة', () async {
      fake.serverCollections['blacklist'] = [
        mkDoc('blacklist', 'A', 1700001000),
      ];

      // أبقِ الدورة جارية عبر بوابة على أول metadata read.
      final gate = Completer<void>();
      fake.metadataGate = gate;
      final cycle = manager.sync(push: false, pull: true);
      await Future<void>.delayed(Duration.zero);

      final applied = await manager.applyRemoteRecordFast(
        collectionId: 'blacklist',
        documentId: 'blk-guard',
        payload: blacklistPayload('blk-guard', 1700005000),
      );
      expect(applied, isFalse, reason: 'دورة جارية → يُسقط للدورة العادية');

      gate.complete();
      await cycle;

      final rows = await (db.select(
        db.shiftNotes,
      )..where((t) => t.localUuid.equals('blk-guard'))).get();
      expect(rows, isEmpty, reason: 'لم تُكتب أي بيانات أثناء الدورة');
    });

    test('RL9: مجموعة غير مخزنة أو حمولة ناقصة → false', () async {
      // devices ليست كياناً مخزَّناً محلياً كصفوف سحب.
      expect(
        await manager.applyRemoteRecordFast(
          collectionId: 'devices',
          documentId: 'dev-1',
          payload: blacklistPayload('dev-1', 1700006000),
        ),
        isFalse,
      );
      // حمولة بلا $updatedAt → غير مؤهلة.
      expect(
        await manager.applyRemoteRecordFast(
          collectionId: 'blacklist',
          documentId: 'blk-1',
          payload: {'device_id': 'device-B'},
        ),
        isFalse,
      );
      // لا استدعاءات شبكة ولا صفوف.
      expect(fake.callNames, isEmpty);
      final rows = await db.select(db.shiftNotes).get();
      expect(rows, isEmpty);
    });
  });
}
