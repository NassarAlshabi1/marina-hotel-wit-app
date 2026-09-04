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
//       في السحب الكامل، وdelta يمر عبر metadata-first بلا استدعاء
//       listBookingNights المقيّد إطلاقاً (probe + تنزيل المتغيّر فقط).
//   T7  audit_logs مستبعدة: صفر استدعاءات لكولكشن audit_logs في كل دورة.
//   T8  نافذة الأمان 15 ثانية في دورة delta تالية: cutoff مشتق من مؤشر
//       الكيان (سلطة الخادم) وليس من وقت الجهاز.
//
//  التشغيل:
//    flutter test test/unit/sync_metadata_first_integration_test.dart
// ============================================================================

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

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
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];
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

  /// ✅ (2026-08-31) استعلامات listDocumentsMetadata الإضافية (extraQueries)
  /// لكل كولكشن — لإثبات أن delta metadata-first يمرّر فلتر delta نفسه.
  final Map<String, List<String>> metadataQueries = {};

  /// معاملات listBookingNights الأخيرة (للتحقق من maxRecords).
  Map<Symbol, Object?>? lastBookingNightsNamedArgs;

  /// ✅ (2026-08-31) مراقب نجاح الرفع (echo immunization) — يُلتقط من
  /// المُنشئ عبر setter حقيقي (الحقل مُعرَّف هنا فيتجاوز noSuchMethod).
  @override
  void Function(String collectionId, models.Document document)?
  onDocumentUpserted;

  void reset() {
    serverCollections.clear();
    throwOn.clear();
    callNames.clear();
    byIdsRequests.clear();
    listDocumentsQueries.clear();
    metadataQueries.clear();
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

  /// ✅ (2026-08-31) يفك ترميز استعلام Appwrite (JSON) ويستخرج cutoff من
  /// `greaterThan($updatedAt, iso)` — لمحاكاة فلترة الخادم في الـ fake.
  String? _parseGreaterThanUpdatedAtCutoff(String query) {
    try {
      final decoded = jsonDecode(query);
      if (decoded is Map<String, dynamic> &&
          decoded['method'] == 'greaterThan' &&
          decoded['attribute'] == r'$updatedAt') {
        final values = decoded['values'];
        if (values is List && values.isNotEmpty) {
          return values.first.toString();
        }
      }
    } catch (_) {}
    return null;
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

      // ── metadata-first: سحب ($id + $updatedAt) فقط ──
      // ✅ (2026-08-31) يدعم extraQueries ويطبّق فلتر greaterThan($updatedAt)
      // بشكل وفي للخادم — delta metadata-first يمرّر فلتر نافذة المؤشر
      // فالخادم الحقيقي يُرجع فقط ما تغيّر فيها (لا كل الكولكشن).
      case 'listDocumentsMetadata':
        final collectionId = _argStr(invocation.positionalArguments[0]);
        final extraQueries =
            (invocation.namedArguments[#extraQueries] as List?)
                ?.cast<String>() ??
            const <String>[];
        metadataQueries
            .putIfAbsent(collectionId, () => <String>[])
            .addAll(extraQueries);
        _maybeThrow('listDocumentsMetadata:$collectionId');
        _maybeThrow('listDocumentsMetadata');
        var metaDocs = List.of(
          serverCollections[collectionId] ?? const <models.Document>[],
        );
        for (final q in extraQueries) {
          final cutoffIso = _parseGreaterThanUpdatedAtCutoff(q);
          if (cutoffIso != null) {
            metaDocs = metaDocs
                .where((d) => d.$updatedAt.compareTo(cutoffIso) > 0)
                .toList();
          }
        }
        return Future<List<models.Document>>.value(metaDocs);

      // ── جلب المستندات الكاملة بمعرّفاتها (بعد حصر المتغيّر) ──
      case 'listDocumentsByIds':
        final collectionId = _argStr(invocation.positionalArguments[0]);
        final ids = (invocation.positionalArguments[1] as List).cast<String>();
        byIdsRequests.putIfAbsent(collectionId, () => <String>[]).addAll(ids);
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
          List.of(
            serverCollections[AppwriteConfig.bookingNightsCollectionId] ??
                const [],
          ),
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

String isoOf(int tsSec) => DateTime.fromMillisecondsSinceEpoch(
  tsSec * 1000,
  isUtc: true,
).toIso8601String();

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
    final row = await (db.select(
      db.syncState,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
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
      expect(
        fake.byIdsRequests['blacklist'],
        isNull,
        reason: 'مطابقة تامة يجب ألا تُنزّل أي مستند كامل',
      );
      expect(
        fake.listDocumentsQueries['blacklist'],
        isNull,
        reason: 'السحب الكامل لا يمر عبر listDocuments عند تطابق meta',
      );
      expect(fake.callNames.where((n) => n == 'listBlacklist'), isEmpty);

      // 3) مؤشر الكيان تقدّم إلى أقصى $updatedAt على الخادم (1700001000)
      //    رغم عدم تنزيل أي مستند — بواسطة pending serverMax.
      final marks = await entityWatermarks();
      expect(marks['blacklist'], 1700001000);

      // 4) خريطة meta المحلية بقيت كما هي.
      expect(await db.getRemoteMetaMap('blacklist'), {
        'A': 1700001000,
        'B': 1700000900,
      });

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
      expect(
        fake.byIdsRequests['blacklist'],
        ['NEW'],
        reason: 'يجب حصر الجلب الكامل في المستند المتغيّر وحده',
      );

      // المستند الجديد وصل قاعدة البيانات المحلية.
      final rows = await (db.select(
        db.shiftNotes,
      )..where((t) => t.localUuid.equals('NEW'))).get();
      expect(rows, hasLength(1));
      // lastModified اشتُق من $updatedAt (1700002000) — بلا lastModified في data.
      expect(rows.first.lastModified, 1700002000);
      expect(rows.first.title, 'مطلوب-للشرطة');
      expect(rows.first.origin, 'server');

      // مؤشر الكيان = أقصى $updatedAt على الخادم (يشمل غير المجلوب A).
      final marks = await entityWatermarks();
      expect(marks['blacklist'], 1700002000);

      // خريطة meta تحدّثت بالمستند المطبّق فقط (A: القديم، NEW: الجديد).
      expect(await db.getRemoteMetaMap('blacklist'), {
        'A': 1700001000,
        'NEW': 1700002000,
      });
    });

    test('T3: فشل metadata لكولكشن → failedCollections الحقيقي: مؤشره لا '
        'يتقدم، غيره يتقدم (استقلالية)، والعالمي لا يُضبط', () async {
      // blacklist: metadata ترمي (فشل شبكة محاكى).
      fake.throwOn['listDocumentsMetadata:blacklist'] = Exception(
        'socket timeout',
      );
      // rooms: metadata سليمة ومطابقة محلياً (كيان سليم يثبت استقلاليته).
      fake.serverCollections['rooms'] = [mkDoc('R1', 1700005000)];
      await seedLocalMeta(AppwriteConfig.roomsCollectionId, {'R1': 1700005000});

      final result = await runFullPull();

      // الدورة لا تنهار (كل كولكشن مستقل) والخطأ يُسجَّل في failedCollections
      // داخلياً — الأثر المهم: منع تقدم المؤشرات.
      expect(result.errorMessage, isNull);

      // 1) مؤشر الكيان الفاشل لا يتقدم أبداً.
      final marks = await entityWatermarks();
      expect(
        marks.containsKey('blacklist'),
        false,
        reason: 'فشل الجلب يجب ألا يقدّم مؤشر blacklist',
      );

      // 2) مؤشر الكيان السليم تقدّم — استقلالية الكيانات عبر المسار الحقيقي.
      expect(
        marks['rooms'],
        1700005000,
        reason: 'فشل blacklist يجب ألا يجمّد rooms',
      );

      // 3) المؤشر العالمي لم يتقدم (حارس كل-أو-لاشيء).
      expect(
        await globalLastPullTs(),
        0,
        reason: 'failedCollections غير فارغة → لا تحديث لـ lastPullTs',
      );

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
      expect(
        marks.containsKey('blacklist'),
        false,
        reason: 'فشل الجلب الكامل بعد metadata يجب ألا يقدّم المؤشر',
      );
      expect(
        await db.getRemoteMetaMap('blacklist'),
        isEmpty,
        reason: r'لا يحق تخزين $updatedAt قبل تطبيق المحتوى فعلياً',
      );
      expect(await fullSyncDone(), false);
      expect(await globalLastPullTs(), 0);
    });

    test(
      'T5: دورة كاملة ناجحة → full_sync_complete = 1 و lastPullTs يتقدم',
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
      },
    );

    test('T6: سقف booking_nights = initialBookingNightsPullLimit (1000) في '
        'السحب الكامل، وdelta عبر metadata-first بلا استدعاء مقيّد', () async {
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
      ];
      await seedLocalMeta('blacklist', {'A': 1700001000});

      // 1) دورة أولى: سحب كامل → maxRecords = 1000.
      await runFullPull();
      expect(fake.lastBookingNightsNamedArgs, isNotNull);
      expect(
        fake.lastBookingNightsNamedArgs![#maxRecords],
        SyncConstants.initialBookingNightsPullLimit,
      );

      // 2) دورة ثانية: full_sync_complete=1 و lastPullTs>0 → delta.
      //    ✅ (2026-09-03) delta لـ booking_nights عبر طبقة metadata-first
      //    نفسها المستخدمة لبقية الكيانات: probe ($id + $updatedAt) بفلتر
      //    delta ثم تنزيل المتغيّر فقط عبر listDocumentsByIds — لا استدعاء
      //    listBookingNights الكامل المقيّد في delta إطلاقاً.
      fake.reset();
      manager.resetPullThrottleForTesting();
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
      ];
      await runFullPull();
      expect(
        fake.lastBookingNightsNamedArgs,
        isNull,
        reason: 'delta لا يستدعي listBookingNights المقيّد — metadata-first',
      );
      expect(
        fake.metadataQueries.containsKey('booking_nights'),
        isTrue,
        reason: 'delta لـ booking_nights يمر عبر probe الـ metadata-first',
      );
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
      expect(
        fake.callNames.where((n) => n.toLowerCase().contains('audit')),
        isEmpty,
        reason:
            'auditLogsSyncEnabled=false → لا مسار سحب لـ audit_logs إطلاقاً',
      );
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
      expect(
        fake.callNames,
        isEmpty,
        reason: 'داخل فاصل الدقيقتين لا يُسمح بأي استدعاء شبكة',
      );

      // pullRemoteChanges كذلك يُخَطّى (يعيد true — ليس فشلاً).
      expect(await manager.pullRemoteChanges(), isTrue);
      expect(fake.callNames, isEmpty);

      // إعادة الضبط للاختبار (أو مرور الفاصل في الواقع) → السحب يعمل من جديد.
      // ملاحظة: الدورة هنا ستكون delta لأن الدورة الأولى نجحت (full_sync_complete=1
      // والمؤشرات > 0) — والمسار الآن metadata-first أيضاً في delta.
      fake.serverCollections['blacklist'] = [
        mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
      ];
      manager.resetPullThrottleForTesting();
      final resumed = await runFullPull();
      expect(resumed.errorMessage, isNull);
      expect(
        fake.callNames,
        contains('listDocumentsMetadata'),
        reason: 'بعد مرور الفاصل استُؤنف السحب — بوضع delta (metadata-first)',
      );
      expect(fake.metadataQueries['blacklist'], isNotNull);
      expect(
        fake.byIdsRequests['blacklist'],
        isNull,
        reason: 'النافذة مطابقة محلياً → صفر تنزيل حتى في delta',
      );
    });

    test('T8: دورة delta تالية → مقارنة metadata بفلتر النافذة (cutoff = مؤشر '
        r'الكيان − 15) وكل المطابق يُتخطى بلا تنزيل', () async {
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

      // دورة ثانية: delta metadata-first — فلتر النافذة يُمرَّر للـ metadata.
      await runFullPull();

      final metaQ = fake.metadataQueries['blacklist'];
      expect(metaQ, isNotNull, reason: 'delta يستخدم مقارنة metadata الآن');
      expect(metaQ, hasLength(1));
      expect(metaQ!.first, contains(r'$updatedAt'));
      // cutoff = 1700001000 − 15 = 1700000985 (نافذة الأمان).
      expect(metaQ.first, contains(isoOf(1700001000 - 15)));

      // كل مستندات النافذة (A) مطابقة محلياً → صفر تنزيل إطلاقاً:
      // لا جلب كامل ولا byIds — وأثر ذلك الوحيد قراءة metadata خفيفة.
      expect(
        fake.byIdsRequests['blacklist'],
        isNull,
        reason: 'echo/مطابق → لا تنزيل حمولة كاملة في delta',
      );
      expect(
        fake.listDocumentsQueries['blacklist'],
        isNull,
        reason: 'لا حاجة لتمرير كامل بديل — المقارنة حصرت المتغيّر (لا شيء)',
      );

      // المؤشر بقي عند قيمة الخادم (لا تراجع ولا قفز زائف).
      expect((await entityWatermarks())['blacklist'], 1700001000);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // ✅ (2026-08-31) تقليل السحب على مستوى السجل — metadata-first في delta
  // ───────────────────────────────────────────────────────────────────────
  group(
    'DT: delta metadata-first — السحب على مستوى السجل عبر الدورة الحقيقية',
    () {
      setUp(resetState);

      test('DT1: echo الرفع لا يُنزَّل — تسجيل meta من مراقب الرفع يكفي '
          'للتخطي، والمؤشر يتقدم فوق النافذة المحكومة', () async {
        // دورة 1 (full): خط الأساس — مؤشر 1700001000 و meta {A}.
        fake.serverCollections['blacklist'] = [
          mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
        ];
        await seedLocalMeta('blacklist', {'A': 1700001000});
        await runFullPull();
        expect((await entityWatermarks())['blacklist'], 1700001000);

        // ⚡ محاكاة رفع ناجح: مراقب الرفع (المربوط في المُنشئ) يُخطِر بالسجل
        // المرفوع P مع $updatedAt الذي أعاده الخادم.
        expect(
          fake.onDocumentUpserted,
          isNotNull,
          reason: 'المدير يربط مراقب نجاح الرفع في المُنشئ',
        );
        fake.onDocumentUpserted!(
          'blacklist',
          mkDoc('P', 1700003000, {'name': 'رفع-محلي'}),
        );
        await pumpEventQueue();
        expect(
          (await db.getRemoteMetaMap('blacklist'))['P'],
          1700003000,
          reason: 'echo immunization: meta تُسجَّل لحظة نجاح الرفع',
        );

        // دورة 2 (delta): الخادم يحمل A وP (echo عاد في النافذة) — الاثنان
        // مطابقان محلياً → صفر تنزيل رغم أن P أحدث من المؤشر.
        fake.reset();
        manager.resetPullThrottleForTesting();
        fake.serverCollections['blacklist'] = [
          mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
          mkDoc('P', 1700003000, {'name': 'رفع-محلي'}),
        ];
        await runFullPull();

        expect(
          fake.byIdsRequests['blacklist'],
          isNull,
          reason: 'echo المسجَّل meta لا يُنزَّل — هذا هو وفر السجل الواحد',
        );
        expect(fake.listDocumentsQueries['blacklist'], isNull);

        // المؤشر تقدم إلى أقصى النافذة (1700003000) — آمن لأن كل مستنداتها
        // صارت محكومة: A مطابق وP هو echo مرفوعنا.
        expect((await entityWatermarks())['blacklist'], 1700003000);
      });

      test(
        'DT2: نافذة delta بمطابق + متغيرين → byIds يجلب المتغيرين فقط '
        'والمؤشر يتقدم إلى أقصى النافذة (سلطة الخادم) لا أقصى المجلوب',
        () async {
          // دورة 1: خط الأساس — A وC معروفان محلياً (C داخل نافذة الأمان
          // من المؤشر: 1700000990 > 1700000985).
          fake.serverCollections['blacklist'] = [
            mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
          ];
          await seedLocalMeta('blacklist', {'A': 1700001000, 'C': 1700000990});
          await runFullPull();
          expect((await entityWatermarks())['blacklist'], 1700001000);

          // دورة 2: تغيّر A (محتوى جديد) + وُلد B + بقي C كما هو (سيُعاد
          // فحصه في النافذة بسبب نافذة الأمان — وهذا المطلوب).
          fake.reset();
          manager.resetPullThrottleForTesting();
          fake.serverCollections['blacklist'] = [
            mkDoc('A', 1700002500, {'name': 'شخص-أ-محدث'}),
            mkDoc('B', 1700002000, {'name': 'جديد'}),
            mkDoc('C', 1700000990, {'name': 'ثابت'}),
          ];
          await runFullPull();

          // الجلب الكامل حُصر في المتغيرين فعلاً — C المطابق لم يُنزَّل رغم
          // وجوده في النافذة.
          expect(
            fake.byIdsRequests['blacklist'],
            ['A', 'B'],
            reason: 'metadata-first في delta: تنزيل المتغيّر فقط',
          );

          // الصفوف وصلت محلياً.
          final rows = await db.select(db.shiftNotes).get();
          expect(rows.map((r) => r.localUuid).toSet(), {'A', 'B'});

          // المؤشر = أقصى $updatedAt في النافذة (1700002500) — بواسطة pending
          // serverMax لا أقصى المستندات المجلوبة (وهما متساويان هنا لأن أقصى
          // النافذة هو نفسه متغير مُجلوب، لكن القيمة مصدرها النافذة الكاملة).
          expect((await entityWatermarks())['blacklist'], 1700002500);

          // meta حُدّثت بالمجلوب فقط، والمطابق C بقي بطابعه.
          expect(await db.getRemoteMetaMap('blacklist'), {
            'A': 1700002500,
            'B': 1700002000,
            'C': 1700000990,
          });
        },
      );

      test('DT3: فشل metadata في delta → مؤشر الكيان والسحب العالمي لا '
          'يتقدمان (لا "رؤية" بلا محتوى)', () async {
        fake.serverCollections['blacklist'] = [
          mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
        ];
        await seedLocalMeta('blacklist', {'A': 1700001000});
        await runFullPull();
        expect((await entityWatermarks())['blacklist'], 1700001000);
        final globalBefore = await globalLastPullTs();
        expect(globalBefore, greaterThan(0));

        // دورة delta فاشلة: metadata لـ blacklist ترمي — سجل جديد N لن يُرى.
        fake.reset();
        manager.resetPullThrottleForTesting();
        fake.throwOn['listDocumentsMetadata:blacklist'] = Exception('timeout');
        fake.serverCollections['blacklist'] = [
          mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
          mkDoc('N', 1700002000, {'name': 'لن-يصل'}),
        ];

        await runFullPull();

        // المؤشر تجمّد: N لم يُحكَم عليه فلا حق لتقدم المؤشر فوقه.
        expect(
          (await entityWatermarks())['blacklist'],
          1700001000,
          reason: 'فشل مرحلة metadata في delta يجب ألا يقدّم المؤشر',
        );
        expect(
          await globalLastPullTs(),
          globalBefore,
          reason: 'failedCollections تمنع تقدم المؤشر العالمي',
        );
        expect(
          await db.getRemoteMetaMap('blacklist'),
          {'A': 1700001000},
          reason: 'لا كتابة meta عند الفشل',
        );
      });

      test('DT4: bootstrap الكيان (meta فارغة) → تمرير واحد عادي في delta '
          'لا مرحلتين (لا فائدة من المقارنة بلا معرفة لكل سجل)', () async {
        fake.serverCollections['blacklist'] = [
          mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
        ];
        await seedLocalMeta('blacklist', {'A': 1700001000});
        await runFullPull();
        expect((await entityWatermarks())['blacklist'], 1700001000);

        // فقدان المعرفة لكل سجل (كأن الكولكشن جديد على هذه القاعدة).
        await db.clearRemoteMeta(collection: 'blacklist');

        fake.reset();
        manager.resetPullThrottleForTesting();
        fake.serverCollections['blacklist'] = [
          mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
          mkDoc('B', 1700002000, {'name': 'جديد'}),
        ];
        await runFullPull();

        // مرحلة metadata اشتغلت ثم اكتشفت غياب المعرفة → fallback تمرير واحد.
        expect(fake.metadataQueries['blacklist'], isNotNull);
        expect(
          fake.listDocumentsQueries['blacklist'],
          isNotNull,
          reason: 'bootstrap: سحب delta عادي بتمرير واحد (أرخص من byIds)',
        );
        expect(
          fake.byIdsRequests['blacklist'],
          isNull,
          reason: 'لا دفعات byIds في مسار bootstrap',
        );

        // النتيجة كاملة كالسحب العادي: B وصل والمؤشر تقدم من المستندات.
        final rows = await db.select(db.shiftNotes).get();
        expect(rows.map((r) => r.localUuid).toSet(), {'A', 'B'});
        expect((await entityWatermarks())['blacklist'], 1700002000);
      });

      test('DT5: بقايا pending من دورة فاشلة لا تُستهلك في مسار fast-path — '
          'سجلات النافذة غير المطبقة تُسحب لاحقاً (حارس ضد اختفاء)', () async {
        // دورة 1: خط الأساس.
        fake.serverCollections['blacklist'] = [
          mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
        ];
        await seedLocalMeta('blacklist', {'A': 1700001000});
        await runFullPull();
        expect((await entityWatermarks())['blacklist'], 1700001000);

        // دورة 2 (delta): C وB متغيران → pending = 1700002000 يُضبط ثم
        // فشل byIds → checkpoint لا يُستهلك — بقايا pending على الطاولة.
        fake.reset();
        manager.resetPullThrottleForTesting();
        fake.throwOn['listDocumentsByIds:blacklist'] = Exception('timeout');
        fake.serverCollections['blacklist'] = [
          mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
          mkDoc('C', 1700001500, {'name': 'بين-النافذتين'}),
          mkDoc('B', 1700002000, {'name': 'أحدث'}),
        ];
        await runFullPull();
        expect(
          (await entityWatermarks())['blacklist'],
          1700001000,
          reason: 'الفشل أوقف checkpoint — المؤشر ثابت',
        );

        // دورة 3 (delta عادي): النافذة ما زالت من 1700000985 → C وB يظهران
        // ويُجلَبان — إثبات أن الحارس أبقى سجلات كانت ستُفقد.
        // ✅ (2026-09-01) ملاحظة: دورة "fast-path" السابقة أُزيلت من هذا
        // الاختبار مع إزالة المسار السريع نفسه (لا يوجد fastAppliedEntities
        // بعد الآن) — الحارس بلا مدخل يخطّي مرحلة metadata أصلاً.
        fake.reset(); // ✅ يزيل throwOn من دورة الفشل (كانت الدورة 3 المحذوفة تفعله)
        fake.serverCollections['blacklist'] = [
          mkDoc('A', 1700001000, {'name': 'شخص-أ'}),
          mkDoc('C', 1700001500, {'name': 'بين-النافذتين'}),
          mkDoc('B', 1700002000, {'name': 'أحدث'}),
        ];
        manager.resetPullThrottleForTesting();
        await runFullPull();
        expect(
          fake.byIdsRequests['blacklist'],
          containsAll(['C', 'B']),
          reason: 'سجلات النافذة غير المطبقة تُسحب بعد الدورة المُخطَّاة',
        );
        final rows = await db.select(db.shiftNotes).get();
        expect(rows.map((r) => r.localUuid).toSet(), containsAll({'C', 'B'}));
        expect((await entityWatermarks())['blacklist'], 1700002000);
      });

      test('DT6: recordPushedDocumentMeta — يسجل لكيانات المزامنة فقط ولا '
          'يرمي أبداً على كولكشنز النظام', () async {
        // ربط المراقب موجود (أُثبت في DT1) — هنا العقد المباشر للدالة.
        await manager.recordPushedDocumentMeta(
          'blacklist',
          mkDoc('P', 1700003000, {'name': 'مرفوع'}),
        );
        expect(
          await db.getRemoteMetaMap('blacklist'),
          {'P': 1700003000},
          reason: 'echo immunization: الطابع المعاد يُخزَّن فوراً',
        );

        // كولكشن غير مخطَّط → يُتجاهل بصمت (لا تلوث ولا استثناء).
        await manager.recordPushedDocumentMeta(
          'definitely_not_mapped_xyz',
          mkDoc('X', 1700004000),
        );
        expect(await db.getRemoteMetaMap('definitely_not_mapped_xyz'), isEmpty);

        // مستند بلا $updatedAt مقروء → يُتجاهل بلا استثناء.
        await manager.recordPushedDocumentMeta('blacklist', mkDoc('Q', 0));
      });
    },
  );
}
