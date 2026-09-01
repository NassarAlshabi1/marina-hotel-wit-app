// test/services/pull_staleness_guard_test.dart
//
// ✅ (2026-09-01) صمام أمان الركود — سيناريو "المستخدم نسى المزامنة
// اليدوية": فحص تلقائي كل 10 دقائق؛ إذا مرت ساعة على آخر **سحب** مكتمل
// يبدأ سحب تلقائي **دلتا فقط**.
//
// ما يغطيه هذا الملف:
//   1. الدالة النقية isPullStaleForAutoDelta — الحدود (null/59د/60د/ساعتان).
//   2. deltaOnly=true + bootstrap (full_sync_complete=0) → تخطي السحب
//      كلياً — صفر قراءات شبكة، لا يبدأ Full Sync من الخلفية أبداً.
//   3. deltaOnly=true بعد اكتمال التهيئة → الدورة تعمل كدلتا وتطبع التغيير.
//   4. طابع lastPullWallClockKey يتقدم عند دورة سحب فقط — ولا يتقدم مع
//      دورة رفع فقط (جوهر دلالة "آخر سحب" لقياس الركود).
//   5. الثوابت: العتبة ساعة، الفحص كل 10 دقائق، المفتاح غير فارغ.
//
// المنهجية: نفس harness ‏pull_entry_matrix_test.dart — المدير الحقيقي مع
// خدمة Appwrite وهمية صاخبة وقاعدة drift في الذاكرة.

// ignore_for_file: avoid_print

import 'package:appwrite/models.dart' as models;
// ignore: depend_on_referenced_packages (واجهة المنصة لمحاكاة الاتصال فقط)
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_network_helper.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Future<void> ensureInitialized() async {}
}

class _MetaCall {
  _MetaCall(this.collectionId, this.extraQueries);
  final String collectionId;
  final List<String> extraQueries;

  /// قراءة دلتا تمرر فلاتر إضافية (cutoff ‏$updatedAt)؛ الكاملة بلا فلتر زمني.
  bool get isDelta => extraQueries.isNotEmpty;
}

class _FakeAppwriteService implements AppwriteService {
  final Map<String, List<models.Document>> serverCollections = {};
  final List<String> callNames = [];
  final List<_MetaCall> metadataCalls = [];

  @override
  void Function(String collectionId, models.Document document)?
  onDocumentUpserted;

  void reset() {
    serverCollections.clear();
    callNames.clear();
    metadataCalls.clear();
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
        final extra =
            (invocation.namedArguments[#extraQueries] as List<String>?) ??
            const <String>[];
        metadataCalls.add(_MetaCall(collectionId, List.of(extra)));
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ConnectivityPlatform.instance = _FakeConnectivityPlatform();

  late AppDatabase db;
  late _FakeAppwriteService fake;
  late AppwriteSyncManager manager;

  db = AppDatabase.forTesting(NativeDatabase.memory());
  fake = _FakeAppwriteService();
  manager = AppwriteSyncManager(appwriteService: fake, database: db);

  Future<int> wallClock() async =>
      (await SharedPreferences.getInstance()).getInt(
        SyncConstants.lastPullWallClockKey,
      ) ??
      0;

  Future<void> resetState() async {
    SharedPreferences.setMockInitialValues({});
    fake.reset();
    manager.resetPullThrottleForTesting();
    await (db.delete(db.syncState)).go();
    await (db.delete(db.syncRemoteMeta)).go();
    await (db.delete(db.shiftNotes)).go();
    await (db.delete(db.outbox)).go();
  }

  /// هل آخر قراءة metadata في دورة السحب الأخيرة كانت دلتا (بفلتر cutoff)؟
  bool lastPullWasDelta() =>
      fake.metadataCalls.isNotEmpty ? fake.metadataCalls.last.isDelta : false;

  group('الدالة النقية isPullStaleForAutoDelta — حدود العتبة', () {
    test('null (لم يسحب قط) → لا ركود — التهيئة ليست مسؤولية الصمام', () {
      final now = DateTime.now();
      expect(
        AppwriteSyncManager.isPullStaleForAutoDelta(
          lastPullWallClockMs: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('59 دقيقة → false، 60 دقيقة → true (الحد مشمول)، ساعتان → true', () {
      final now = DateTime(2026, 9, 1, 12);
      bool stale(int minutesAgo) => AppwriteSyncManager.isPullStaleForAutoDelta(
        lastPullWallClockMs: now
            .subtract(Duration(minutes: minutesAgo))
            .millisecondsSinceEpoch,
        now: now,
      );
      expect(stale(59), isFalse);
      expect(stale(60), isTrue, reason: 'عتبة الساعة بالضبط مشمولة');
      expect(stale(120), isTrue);
    });
  });

  group('deltaOnly — قاعدة "لا Full Sync من الخلفية"', () {
    test(
      'bootstrap (لم تكتمل أول مزامنة) → تخطي صامت بلا أي قراءة شبكة',
      () async {
        await resetState();

        fake.serverCollections['blacklist'] = [mkDoc('A', 1700001000)];

        final result = await manager.sync(
          push: false,
          pull: true,
          deltaOnly: true,
        );

        expect(result.status, SyncStatus.idle);
        expect(
          result.errorMessage,
          contains('Delta-only pull skipped'),
          reason: 'الجهاز في مرحلة التهيئة — السحب الكامل قرار يدوي',
        );
        expect(
          fake.callNames.where((n) => n == 'listDocumentsMetadata'),
          isEmpty,
          reason: 'صفر قراءات شبكة — لم يبدأ Full Sync تلقائياً',
        );
        final rows = await db.select(db.shiftNotes).get();
        expect(rows, isEmpty, reason: 'لم يُنزَّل أي سجل');
      },
    );

    test(
      'بعد اكتمال التهيئة → دورة deltaOnly تعمل كدلتا وتطبع التغييرات',
      () async {
        await resetState();

        // دورة تهيئة عادية (كاملة) — تضبط full_sync_complete والمؤشرات.
        fake.serverCollections['blacklist'] = [mkDoc('A', 1700001000)];
        final bootstrap = await manager.sync(push: false, pull: true);
        expect(bootstrap.isSuccess, isTrue);
        expect(
          lastPullWasDelta(),
          isFalse,
          reason: 'الدورة الأولى تهيئة كاملة (metadata بلا cutoff)',
        );

        // تغيير خادم جديد ثم دورة دلتا-فقط (بعد تجاوز حارس الدقيقتين).
        fake.reset();
        fake.serverCollections['blacklist'] = [
          mkDoc('A', 1700001000),
          mkDoc('B', 1700001200),
        ];
        manager.resetPullThrottleForTesting();

        final delta = await manager.sync(
          push: false,
          pull: true,
          deltaOnly: true,
        );
        expect(delta.isSuccess, isTrue, reason: 'الدلتا متاحة — الدورة تسير');
        expect(lastPullWasDelta(), isTrue);
        final ids = (await db.select(db.shiftNotes).get()).map(
          (r) => r.localUuid,
        );
        expect(ids, containsAll(<String>['A', 'B']));
      },
    );
  });

  group('طابع آخر سحب مكتمل (lastPullWallClockKey) — دلالة السحب فقط', () {
    test('دورة سحب ناجحة تكتب الطابع — دورة رفع فقط لا تمسّه', () async {
      await resetState();

      expect(await wallClock(), 0, reason: 'لا طابع قبل أي سحب');

      // دورة رفع فقط (لا يوجد outbox — لا شيء يُرفع، ولا سحب).
      final pushOnly = await manager.sync(push: true, pull: false);
      expect(pushOnly.isSuccess, isTrue);
      expect(
        await wallClock(),
        0,
        reason:
            'الرفع وحده لا يجلب بيانات الأجهزة الأخرى — '
            'قياس الركود لن يقاس منه',
      );

      // دورة سحب → الطابع يُكتب.
      manager.resetPullThrottleForTesting();
      fake.serverCollections['blacklist'] = [mkDoc('A', 1700001000)];
      final pullCycle = await manager.sync(push: false, pull: true);
      expect(pullCycle.isSuccess, isTrue);
      final stamp = await wallClock();
      expect(stamp, greaterThan(0), reason: 'دورة سحب مكتملة تكتب الطابع');
    });
  });

  group('الثوابت — عقود صمام الركود', () {
    test('العتبة ساعة واحدة، الفحص كل 10 دقائق، المفتاح معرّف', () {
      expect(SyncConstants.pullStalenessThreshold, const Duration(hours: 1));
      expect(
        SyncConstants.pullStalenessCheckInterval,
        const Duration(minutes: 10),
      );
      expect(SyncConstants.lastPullWallClockKey, isNotEmpty);
    });
  });
}
