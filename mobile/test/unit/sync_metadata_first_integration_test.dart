// ============================================================================
//  اختبارات تكامل عميقة (Deep Integration) — إثبات بالتنفيذ لا بالمحاكاة
// ============================================================================
//  الهدف (طلب صريح: "تأكد أن اقتراحاتك لم تُبنَ على تخمينات"):
//  كل اختبار هنا يشغّل المسار العام الحقيقي AppwriteSyncManager.sync() —
//  المدير الحقيقي + SyncPullService الحقيقي + قاعدة Drift حقيقية في الذاكرة —
//  مع تزييف AppwriteService فقط (طبقة الشبكة) عبر noSuchMethod.
//
//  ما يُثبته (منطق البناء المنشأ في commits e1975be/ede837e/60367d9/30ebe23):
//   T1  metadata-first: مطابقة تامة → صفر جلب مستندات كاملة + تقدّم مؤشر الكيان
//       إلى أقصى $updatedAt على الخادم (سلطة الخادم حتى بلا تنزيل).
//   T2  metadata-first: مستند جديد واحد → يُجلب هو فقط عبر listDocumentsByIds
//       ويصل لقاعدة البيانات بمشتق lastModified من $updatedAt.
//   T3  فشل جلب metadata لكولكشن → failedCollections الحقيقي: مؤشر الكيان
//       الفاشل لا يتقدّم، مؤشرات الكيانات الأخرى تتقدّم (استقلالية)، والمؤشر
//       العالمي و full_sync_complete لا يُضبطان (كل-أو-لاشيء عالمياً).
//   T4  فشل listDocumentsByIds بعد نجاح metadata → لا تُستهلك الـ pending:
//       مؤشر الكيان لا يتقدّم ولا تُكتب sync_remote_meta (لا "رؤية" بلا محتوى).
//   T5  دورة كاملة ناجحة → full_sync_complete = 1 (idempotent عبر الدورات).
//   T6  سقف booking_nights: maxRecords = initialBookingNightsPullLimit (1000)
//       في السحب الكامل، ويصبح null في delta.
//   T7  audit_logs مستبعدة: صفر استدعاءات لكولكشن audit_logs في كل دورة.
//   T8  نافذة الأمان 15 ثانية في دورة delta تالية: cutoff مشتق من مؤشر
//       الكيان (سلطة الخادم) وليس من وقت الجهاز.
//
//  التشغيل:
//    flutter test test/unit/sync_metadata_first_integration_test.dart
// ============================================================================

// ignore_for_file: avoid_print

import 'package:appwrite/models.dart' as models;
// ignore: depend_on_referenced_packages (واجهة المنصة مستخدمة لمحاكاة الاتصال في الاختبار فقط)
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_config.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_constants.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// بنية تحتية
// ─────────────────────────────────────────────────────────────────────────────

/// منصة اتصال وهمية — تتجاوز DBus/NetworkManager على مضيف الاختبار.
class _FakeConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];
}

/// خدمة Appwrite وهمية تُسجّل كل استدعاء وتتحكم في سلوك كل مسار.
///
/// مبدأ "الفشل الصاخب": أي استدعاء غير متوقع يرمي StateError بدل الردود
/// الافتراضية الصامتة — كي لا يمرّ مسار خفي بلا ملاحظة (عكس أداة محايدة).
class _FakeAppwriteService implements AppwriteService {
  /// صورة الخادم: collectionId → مستندات (تُخدم للـ metadata والـ byIds).
  final Map<String, List<models.Document>> serverCollections = {};

  /// المسارات التي ترمي عمداً: مثل 'listDocumentsMetadata:blacklist'.
  final Map<String, Object> throwOn = {};

  /// سجل أسماء الاستدعاءات بالترتيب.
  final List<String> callNames = [];

  /// معرّفات طلبها listDocumentsByIds لكل كولكشن (بترتيب الطلب).
  final Map<String, List<String>> byIdsRequests = {};

  /// استعلامات listDocuments لكل كولكشن (للتحقق من cutoff في وضع delta).
  final Map<String, List<String>> listDocumentsQueries = {};

  /// معاملات listBookingNights الأخيرة (للتحقق من maxRecords).
  Map<Symbol, Object?>? lastBookingNightsNamedArgs;

  void reset() {
    serverCollections.clear();
    throwOn.clear();
    callNames.clear();
    byIdsRequests.clear();
    listDocumentsQueries.clear();
    lastBookingNightsNamedArgs = null;
  }

  void _maybeThrow(String key) {
    final err = throwOn[key];
    if (err != null) throw err;
  }

  String _memberName(Invocation invocation) {
    // Symbol('name') → name (VM). كافٍ لبيئة flutter test.
    final raw = invocation.memberName.toString();
    final start = raw.indexOf('"');
    return start >= 0 ? raw.substring(start + 1, raw.length - 2) : raw;
  }

  String _argStr(Object? v) => v?.toString() ?? '';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = _memberName(invocation);
    callNames.add(name);

    switch (name) {
      case 'initialize':
        return Future<void>.value();

      case 'isInitialized':
        return true;

      // ── metadata-first: سحب ($id + $updatedAt) فقط ──
      case 'listDocumentsMetadata':
        final collectionId = _argStr(invocation.positionalArguments[0]);
        _maybeThrow('listDocumentsMetadata:$collectionId');
        _maybeThrow('listDocumentsMetadata');
        return Future<List<models.Document>>.value(
          List.of(serverCollections[collectionId] ?? const []),
        );

      // ── جلب المستندات الكاملة بمعرّفاتها (بعد حصر المتغيّر) ──
      case 'listDocumentsByIds':
        final collectionId = _argStr(invocation.positionalArguments[0]);
        final ids = (invocation.positionalArguments[1] as List).cast<String>();
        byIdsRequests
            .putIfAbsent(collectionId, () => <String>[])
            .addAll(ids);
        _maybeThrow('listDocumentsByIds:$collectionId');
        _maybeThrow('listDocumentsByIds');
        final all = serverCollections[collectionId] ?? const [];
        final idSet = ids.toSet();
        return Future<List<models.Document>>.value(
          all.where((d) => idSet.contains(d.$id)).toList(),
        );

      // ── السحب العام (delta + كيانات بلا خريطة) ──
      case 'listDocuments':
        final named = invocation.namedArguments;
        final collectionId = _argStr(named[#collectionId]);
        final queries = (named[#queries] as List?)?.cast<String>();
        if (queries != null) {
          listDocumentsQueries
              .putIfAbsent(collectionId, () => <String>[])
              .addAll(queries);
        }
        _maybeThrow('listDocuments:$collectionId');
        return Future<List<models.Document>>.value(
          List.of(serverCollections[collectionId] ?? const []),
        );

      case 'listBookingNights':
        lastBookingNightsNamedArgs = Map<Symbol, Object?>.from(
          invocation.namedArguments,
        );
        _maybeThrow('listBookingNights');
        return Future<List<models.Document>>.value(
          List.of(serverCollections[AppwriteConfig.bookingNightsCollectionId] ??
              const []),
        );

      // سجل المزامنة السحابي غير حرج — يرمي والمسار يستمر بلا سجل.
      case 'createSyncLog':
        throw StateError('sync-log unavailable (fake)');

      // مسارات شبكة غير متوقعة في دورة سحب ناجحة — فشل صاخب.
      case 'getDocument':
      case 'createDocument':
      case 'deleteDocument':
        throw StateError('unexpected network call: $name (test fake)');

      case 'updateDocument':
      case 'upsertDocument':
        // قد تُستدعى لمسارات ثانوية (سجل المزامنة الفاشل مسبقاً…) — اسمح
        // بوجودها لكن لا تعدها مستنداً حقيقياً.
        throw StateError('unexpected network write: $name (test fake)');

      case 'quickConnectionTest':
        return Future<bool>.value(true);
    }

    // أي عضو آخر (خصائص/توابع) — فشل صاخب ليُظهر أي اعتماد خفي.
    throw StateError(
      '_FakeAppwriteService: استدعاء غير متوقع → $name. '
      'إذا كان هذا الاستدعاء شرعياً في دورة السحب أضفه صراحةً إلى الـ fake.',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// أدوات مساعدة
// ─────────────────────────────────────────────────────────────────────────────

models.Document mkDoc(
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
    $collectionId: 'blacklist',
    $databaseId: 'main',
    $createdAt: iso,
    $updatedAt: iso,
    $permissions: const [],
    data: data,
  );
}

String isoOf(int tsSec) =>
    DateTime.fromMillisecondsSinceEpoch(tsSec * 1000, isUtc: true)
        .toIso8601String();

// ─────────────────────────────────────────────────────────────────────────────
// الحزمة
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ConnectivityPlatform.instance = _FakeConnectivityPlatform();

  late AppDatabase db;
  late _FakeAppwriteService fake;
  late AppwriteSyncManager manager;
  late SyncPullService pullService;

  // AppwriteSyncManager singleton: يُبنى مرة واحدة لكل isolate. لذا تُشغّل
  // السيناريوهات داخل test واحد تسلسلي أو تُنظَّف الحالة في setUp بدقة.
  db = AppDatabase.forTesting(NativeDatabase.memory());
  fake = _FakeAppwriteService();
  manager = AppwriteSyncManager(appwriteService: fake, database: db);
  pullService = SyncPullService(
    appwriteService: fake,
    database: db,
    outboxDao: OutboxDao(db),
  );

  Future<void> resetState() async {
    SharedPreferences.setMockInitialValues({});
    fake.reset();
    // الحارس المركزي (فاصل دقيقتين) يُعاد ضبطه — الاختبارات تشغّل دورات متقاربة.
    manager.resetPullThrottleForTesting();
    await (db.delete(db.syncState)).go();
    await (db.delete(db.syncRemoteMeta)).go();
    await (db.delete(db.shiftNotes)).go();
    await (db.delete(db.outbox)).go();
  }

  Future<int> globalLastPullTs() async {
    final row =
        await (db.select(db.syncState)..where((t) => t.id.equals(1)))
            .getSingleOrNull();
    return row?.lastPullTs ?? 0;
  }

  Future<bool> fullSyncDone() => pullService.isFullSyncComplete();

  Future<Map<String, int>> entityWatermarks() =>
      pullService.getEntityPullTsMap();

  Future<void> seedLocalMeta(String collection, Map<String, int> meta) =>
      db.upsertRemoteMeta(collection, meta);

  /// تشغيل دورة سحب كاملة عبر المسار العام الحقيقي.
  Future<SyncResult> runFullPull() => manager.sync(push: false, pull: true);

  group('تكامل عميق: metadata-first عبر AppwriteSyncManager.sync() الحقيقي', () {
    setUp(resetState);

    test('T1: مطابقة تامة → صفر جلب مستندات كاملة + مؤشر الكيان = أقصى '
        r'$updatedAt للخادم', () async {
      // الخادم: مستندان للـ blacklist. المحلي يعرف الطابعين (meta متطابقة).
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
        mkDoc('B', 1700000900, {'name': 'شخص-ب'}),
      ];
      await seedLocalMeta('blacklist', {'A': 1700001000, 'B': 1700000900});

      final result = await runFullPull();

      // لا سجلات جديدة → sync تعيد recordsPulled=0 لكن الدورة ناجحة.
      expect(result.errorMessage, isNull);

      // 1) metadata سُحبت فعلاً (طبقة المقارنة الخفيفة تعمل).
      expect(fake.callNames, contains('listDocumentsMetadata'));

      // 2) صفر جلب مستندات كاملة — لا byIds ولا listDocuments للكولكشن.
      expect(fake.byIdsRequests['blacklist'], isNull,
          reason: 'مطابقة تامة يجب ألا تُنزّل أي مستند كامل');
      expect(fake.listDocumentsQueries['blacklist'], isNull,
          reason: 'السحب الكامل لا يمر عبر listDocuments عند تطابق meta');
      expect(fake.callNames.where((n) => n == 'listBlacklist'), isEmpty);

      // 3) مؤشر الكيان تقدّم إلى أقصى $updatedAt على الخادم (1700001000)
      //    رغم عدم تنزيل أي مستند — بواسطة pending serverMax.
      final marks = await entityWatermarks();
      expect(marks['blacklist'], 1700001000);

      // 4) خريطة meta المحلية بقيت كما هي.
      expect(await db.getRemoteMetaMap('blacklist'),
          {'A': 1700001000, 'B': 1700000900});

      // 5) لا شيء كُتب في shift_notes.
      final rows = await db.select(db.shiftNotes).get();
      expect(rows, isEmpty);
    });

    test('T2: مستند جديد وحيد → listDocumentsByIds يطلب هو فقط ويصل '
        'للقاعدة بمشتق lastModified من \$updatedAt (سلطة الخادم)', () async {
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
        mkDoc('NEW', 1700002000, {'name': 'مطلوب-للشرطة', 'active': true}),
      ];
      // المحلي يعرف A فقط (طابعه مطابق) → NEW وحده المتغيّر.
      await seedLocalMeta('blacklist', {'A': 1700001000});

      final result = await runFullPull();

      expect(result.errorMessage, isNull);
      expect(fake.callNames, contains('listDocumentsMetadata'));
      expect(fake.byIdsRequests['blacklist'], ['NEW'],
          reason: 'يجب حصر الجلب الكامل في المستند المتغيّر وحده');

      // المستند الجديد وصل قاعدة البيانات المحلية.
      final rows =
          await (db.select(db.shiftNotes)
                ..where((t) => t.localUuid.equals('NEW')))
              .get();
      expect(rows, hasLength(1));
      // lastModified اشتُق من $updatedAt (1700002000) — بلا lastModified في data.
      expect(rows.first.lastModified, 1700002000);
      expect(rows.first.title, 'مطلوب-للشرطة');
      expect(rows.first.origin, 'server');

      // مؤشر الكيان = أقصى $updatedAt على الخادم (يشمل غير المجلوب A).
      final marks = await entityWatermarks();
      expect(marks['blacklist'], 1700002000);

      // خريطة meta تحدّثت بالمستند المطبّق فقط (A: القديم، NEW: الجديد).
      expect(await db.getRemoteMetaMap('blacklist'),
          {'A': 1700001000, 'NEW': 1700002000});
    });

    test('T3: فشل metadata لكولكشن → failedCollections الحقيقي: مؤشره لا '
        'يتقدم، غيره يتقدم (استقلالية)، والعالمي لا يُضبط', () async {
      // blacklist: metadata ترمي (فشل شبكة محاكى).
      fake.throwOn['listDocumentsMetadata:blacklist'] =
          Exception('socket timeout');
      // rooms: metadata سليمة ومطابقة محلياً (كيان سليم يثبت استقلاليته).
      fake.serverCollections['rooms'] = [mkDoc('R1', 1700005000)];
      await seedLocalMeta(AppwriteConfig.roomsCollectionId, {'R1': 1700005000});

      final result = await runFullPull();

      // الدورة لا تنهار (كل كولكشن مستقل) والخطأ يُسجَّل في failedCollections
      // داخلياً — الأثر المهم: منع تقدم المؤشرات.
      expect(result.errorMessage, isNull);

      // 1) مؤشر الكيان الفاشل لا يتقدم أبداً.
      final marks = await entityWatermarks();
      expect(marks.containsKey('blacklist'), false,
          reason: 'فشل الجلب يجب ألا يقدّم مؤشر blacklist');

      // 2) مؤشر الكيان السليم تقدّم — استقلالية الكيانات عبر المسار الحقيقي.
      expect(marks['rooms'], 1700005000,
          reason: 'فشل blacklist يجب ألا يجمّد rooms');

      // 3) المؤشر العالمي لم يتقدم (حارس كل-أو-لاشيء).
      expect(await globalLastPullTs(), 0,
          reason: 'failedCollections غير فارغة → لا تحديث لـ lastPullTs');

      // 4) full_sync_complete لم يُضبط — الجهاز لا يدخل delta قبل اكتمال كل شيء.
      expect(await fullSyncDone(), false);

      // 5) لا "رؤية بلا محتوى": لم تُكتب meta لـ blacklist.
      expect(await db.getRemoteMetaMap('blacklist'), isEmpty);
    });

    test('T4: فشل listDocumentsByIds بعد نجاح metadata → pending لا '
        'يُستهلك: مؤشر الكيان ثابت و meta لا تُكتب', () async {
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
      ];
      fake.throwOn['listDocumentsByIds:blacklist'] = Exception('timeout');

      await runFullPull();

      final marks = await entityWatermarks();
      expect(marks.containsKey('blacklist'), false,
          reason: 'فشل الجلب الكامل بعد metadata يجب ألا يقدّم المؤشر');
      expect(await db.getRemoteMetaMap('blacklist'), isEmpty,
          reason: r'لا يحق تخزين $updatedAt قبل تطبيق المحتوى فعلياً');
      expect(await fullSyncDone(), false);
      expect(await globalLastPullTs(), 0);
    });

    test('T5: دورة كاملة ناجحة → full_sync_complete = 1 و lastPullTs يتقدم',
        () async {
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
      ];
      // المحلي يعرف A → صفر جلب كامل، والدورة ناجحة تماماً.
      await seedLocalMeta('blacklist', {'A': 1700001000});

      final result = await runFullPull();

      expect(result.errorMessage, isNull);
      expect(await fullSyncDone(), true);
      expect(await globalLastPullTs(), greaterThan(0));
      // idempotency: دورة ثانية ناجحة تحافظ على العلم (بإلغاء الحارس الزمني
      // لأن الدورتين متلاصقتان داخل الاختبار).
      manager.resetPullThrottleForTesting();
      await runFullPull();
      expect(await fullSyncDone(), true);
    });

    test('T6: سقف booking_nights = initialBookingNightsPullLimit (1000) في '
        'السحب الكامل، وnull في delta', () async {
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
      ];
      await seedLocalMeta('blacklist', {'A': 1700001000});

      // 1) دورة أولى: سحب كامل → maxRecords = 1000.
      await runFullPull();
      expect(fake.lastBookingNightsNamedArgs, isNotNull);
      expect(fake.lastBookingNightsNamedArgs![#maxRecords],
          SyncConstants.initialBookingNightsPullLimit);

      // 2) دورة ثانية: full_sync_complete=1 و lastPullTs>0 → delta.
      fake.reset();
      manager.resetPullThrottleForTesting();
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
      ];
      await runFullPull();
      expect(fake.lastBookingNightsNamedArgs, isNotNull);
      expect(fake.lastBookingNightsNamedArgs![#maxRecords], isNull,
          reason: 'delta لـ booking_nights لا يجب أن يقيّد بعدُ');
    });

    test('T7: audit_logs مستبعدة تماماً من دورة السحب (محلية فقط)', () async {
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
      ];

      await runFullPull();

      // لا أي استدعاء شبكي لكولكشن audit_logs.
      expect(
        fake.listDocumentsQueries.keys,
        isNot(contains(AppwriteConfig.auditLogsCollectionId)),
      );
      expect(fake.callNames.where((n) => n.toLowerCase().contains('audit')),
          isEmpty,
          reason: 'auditLogsSyncEnabled=false → لا مسار سحب لـ audit_logs إطلاقاً');
      // دفاعي: الثابت نفسه false — لو تغيّر، صار هذا الاختبار بلا معنى.
      expect(SyncConstants.auditLogsSyncEnabled, false);
    });

    test('T9: الحارس المركزي — دورة ثانية خلال دقيقتين تُخطّى السحب من '
        'sync و pullRemoteChanges، ويُستأنف السحب بعد إعادة الضبط', () async {
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
      ];
      await seedLocalMeta('blacklist', {'A': 1700001000});

      // دورة أولى ناجحة → تُثبّت _lastSyncTime (وقت اكتمال الدورة).
      await runFullPull();
      final callsAfterFirst = fake.callNames.length;
      expect(callsAfterFirst, greaterThan(0));

      // دورة ثانية فوراً (بلا إعادة ضبط الحارس في resetState) → السحب يُتخطى:
      // لا استدعاءات شبكة جديدة إطلاقاً، والدورة تعود سليمة (ليست failure).
      fake.reset();
      final throttled = await runFullPull();
      expect(throttled.status, SyncStatus.idle);
      expect(throttled.errorMessage, contains('minimum pull gap'));
      expect(fake.callNames, isEmpty,
          reason: 'داخل فاصل الدقيقتين لا يُسمح بأي استدعاء شبكة');

      // pullRemoteChanges كذلك يُخَطّى (يعيد true — ليس فشلاً).
      expect(await manager.pullRemoteChanges(), isTrue);
      expect(fake.callNames, isEmpty);

      // إعادة الضبط للاختبار (أو مرور الفاصل في الواقع) → السحب يعمل من جديد.
      // ملاحظة: الدورة هنا ستكون delta لأن الدورة الأولى نجحت (full_sync_complete=1
      // والمؤشرات > 0) — لذا نتحقق من مسار delta لا من metadata.
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
      ];
      manager.resetPullThrottleForTesting();
      final resumed = await runFullPull();
      expect(resumed.errorMessage, isNull);
      expect(fake.callNames, contains('listDocuments'),
          reason: 'بعد مرور الفاصل استُؤنف السحب — بوضع delta');
      expect(fake.listDocumentsQueries['blacklist'], isNotNull);
      expect(
        fake.callNames.where((n) => n == 'listDocumentsMetadata'),
        isEmpty,
        reason: 'delta لا يحتاج مقارنة metadata',
      );
    });

    test('T8: دورة delta تالية → cutoff مشتق من مؤشر الكيان − 15 ثانية '
        'وليس من وقت الجهاز', () async {
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
      ];
      await seedLocalMeta('blacklist', {'A': 1700001000});

      // دورة أولى ناجحة → مؤشر blacklist = 1700001000 + full_sync_complete.
      await runFullPull();
      expect((await entityWatermarks())['blacklist'], 1700001000);

      // تنظيف سجل الاستدعاءات (تبقى مؤشرات و prefs) ثم إعادة بذر الخادم —
      // كي تنطبق تأكيدات "دورة delta" على استدعاءات هذه الدورة فقط.
      fake.reset();
      manager.resetPullThrottleForTesting();
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
      ];

      // دورة ثانية: delta — تحقق من الاستعلام المُرسل لـ blacklist.
      await runFullPull();

      final queries = fake.listDocumentsQueries['blacklist'];
      expect(queries, isNotNull, reason: 'delta يستخدم listDocuments');
      expect(queries, hasLength(1));
      expect(queries!.first, contains(r'$updatedAt'));
      // cutoff = 1700001000 − 15 = 1700000985 (نافذة الأمان).
      expect(queries.first, contains(isoOf(1700001000 - 15)));
      // وفي delta لا تُستدعى طبقة metadata إطلاقاً (delta رخيصة أصلاً).
      expect(fake.callNames.where((n) => n == 'listDocumentsMetadata'),
          isEmpty,
          reason: 'delta لا يحتاج مقارنة metadata — فلتر زمني مباشر');
    });
  });
}
