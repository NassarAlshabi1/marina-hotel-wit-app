// test/unit/resumable_full_sync_test.dart
//
// ✅ Resumable Full Sync (2026-09-21) — إصلاح P0 لسحب booking_nights.
//
// يغطي السيناريوهات الحرجة للسحب الكامل التدفقي القابل للاستئناف:
//
//  1. SyncCheckpointStore: أعمدة cursor/max_updated (قراءة/كتابة/مسح/رتابة)
//     + ترقية ALTER لجدول قديم (تثبيتات موجودة).
//  2. buildFullSyncPageQueries: orderAsc($id) + limit + cursorAfter.
//  3. UnifiedPullEngine (مسار تدفقي):
//     - بلا سقف: كل الصفحات تُطبَّق والمؤشر يُثبَّت من max($updatedAt) عند
//       النفاد فقط (إصلاح فقدان الليالي > 1000).
//     - الانقطاع (شبكة ضعيفة): المؤشر يتوقف عند آخر صفحة نجحت — الاستئناف
//       يبدأ من cursorAfter نفسها (لا فقدان ولا إعادة سحب كل شيء).
//     - المجموعة الفارغة تبقى في وضع Full (استعلام رخيص) — نفس دلالات commit.
//     - المهام الكلاسيكية (بلا streamFullSync) لم تتغير.
//  4. IdResolver.buildBookingIndex: حل exact/normalized/stripped/serverId
//     بنفس نتائج مسار SQL + منع localId البعيد (ربط خاطئ).
//
// كل الاختبارات بلا شبكة — fetchPage/apply دوال مزيّفة.

// ignore_for_file: lines_longer_than_80_chars

import 'package:appwrite/models.dart' as models;
import 'package:collection/collection.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/adapters/id_resolver.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_checkpoint_store.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';
import 'package:marina_hotel_mobile/services/sync_core/unified_pull_engine.dart';

models.Document _doc(
  String id,
  Map<String, dynamic> data, {
  String updatedAt = '2026-09-21T10:00:00.000Z',
}) {
  return models.Document(
    $id: id,
    $sequence: 1,
    $collectionId: 'booking_nights',
    $databaseId: 'test_db',
    $createdAt: '2026-09-01T00:00:00.000Z',
    $updatedAt: updatedAt,
    $permissions: const <String>[],
    data: data,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late OutboxDao outboxDao;
  late SyncPullService pullService;
  late SyncCheckpointStore checkpoints;
  late UnifiedPullEngine engine;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outboxDao = OutboxDao(db);
    pullService = SyncPullService(
      appwriteService: AppwriteService(),
      database: db,
      outboxDao: outboxDao,
    );
    checkpoints = SyncCheckpointStore(db);
    engine = UnifiedPullEngine(
      checkpoints: checkpoints,
      pullService: pullService,
    );
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 1: SyncCheckpointStore — حالة الاستئناف
  // ═══════════════════════════════════════════════════════════════════════
  group('SyncCheckpointStore — Resumable state', () {
    test('cursor: null افتراضياً → set → get → clear', () async {
      expect(await checkpoints.getFullSyncCursor('booking_nights'), isNull);

      await checkpoints.setFullSyncCursor('booking_nights', 'doc-100');
      expect(await checkpoints.getFullSyncCursor('booking_nights'), 'doc-100');

      await checkpoints.clearFullSyncProgress('booking_nights');
      expect(await checkpoints.getFullSyncCursor('booking_nights'), isNull);
      expect(await checkpoints.getFullSyncMaxUpdated('booking_nights'), 0);
    });

    test('bumpFullSyncMaxUpdated رتيب (monotonic)', () async {
      await checkpoints.bumpFullSyncMaxUpdated('booking_nights', 100);
      await checkpoints.bumpFullSyncMaxUpdated('booking_nights', 50);
      await checkpoints.bumpFullSyncMaxUpdated('booking_nights', 200);
      expect(await checkpoints.getFullSyncMaxUpdated('booking_nights'), 200);
    });

    test(
      'completeFullSync يثبّت last_pull_ts + complete ويمسح التقدم',
      () async {
        await checkpoints.bumpFullSyncMaxUpdated('booking_nights', 12345);
        await checkpoints.setFullSyncCursor('booking_nights', 'doc-7');
        await checkpoints.completeFullSync(
          'booking_nights',
          maxUpdatedSec: 12345,
        );

        expect(await checkpoints.getLastPullTs('booking_nights'), 12345);
        expect(await checkpoints.isFullSyncComplete('booking_nights'), isTrue);
        expect(await checkpoints.getFullSyncCursor('booking_nights'), isNull);
        expect(await checkpoints.getFullSyncMaxUpdated('booking_nights'), 0);
      },
    );

    test('completeFullSync بدون maxUpdated: اكتمال بلا مؤشر', () async {
      await checkpoints.completeFullSync('booking_nights', maxUpdatedSec: 0);
      expect(await checkpoints.isFullSyncComplete('booking_nights'), isTrue);
      expect(await checkpoints.getLastPullTs('booking_nights'), 0);
    });

    test('reset يمسح cursor/max مع القيم القديمة', () async {
      await checkpoints.setLastPullTs('booking_nights', 999);
      await checkpoints.setFullSyncCursor('booking_nights', 'doc-3');
      await checkpoints.bumpFullSyncMaxUpdated('booking_nights', 777);

      await checkpoints.reset('booking_nights');

      expect(await checkpoints.getLastPullTs('booking_nights'), 0);
      expect(await checkpoints.isFullSyncComplete('booking_nights'), isFalse);
      expect(await checkpoints.getFullSyncCursor('booking_nights'), isNull);
      expect(await checkpoints.getFullSyncMaxUpdated('booking_nights'), 0);
    });

    test('ترقية ALTER: جدول بالمخطط القديم يكتسب عمودي cursor/max', () async {
      // جدول قديم بدون العمودين الجديدين (كما في تثبيتات الإنتاج).
      await db.customStatement(
        'CREATE TABLE legacy_checkpoints ('
        'collection_name TEXT NOT NULL PRIMARY KEY, '
        'last_pull_ts INTEGER NOT NULL DEFAULT 0, '
        'full_sync_complete INTEGER NOT NULL DEFAULT 0, '
        'updated_at INTEGER NOT NULL DEFAULT 0'
        ')',
      );
      await db.customStatement(
        "INSERT INTO legacy_checkpoints "
        "(collection_name, last_pull_ts, full_sync_complete, updated_at) "
        "VALUES ('booking_nights', 500, 1, 1)",
      );

      // نفس ترقية _ensureTable على الجدول القديم.
      await db.customStatement(
        'ALTER TABLE legacy_checkpoints ADD COLUMN full_sync_cursor TEXT',
      );
      await db.customStatement(
        'ALTER TABLE legacy_checkpoints ADD COLUMN full_sync_max_updated '
        'INTEGER NOT NULL DEFAULT 0',
      );

      final rows = await db
          .customSelect(
            'SELECT last_pull_ts, full_sync_complete, full_sync_cursor, '
            'full_sync_max_updated FROM legacy_checkpoints '
            "WHERE collection_name = 'booking_nights'",
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.first.data['last_pull_ts'], 500);
      expect(rows.first.data['full_sync_cursor'], isNull);
      expect(rows.first.data['full_sync_max_updated'], 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 2: بناء استعلامات الصفحة
  // ═══════════════════════════════════════════════════════════════════════
  group('SyncPullService.buildFullSyncPageQueries', () {
    test('بلا cursor: ترتيب + حد فقط', () {
      final queries = SyncPullService.buildFullSyncPageQueries(
        baseQueries: SyncPullService.buildFullSyncQueries(),
        cursor: null,
        pageSize: 100,
      );
      expect(
        queries.where((q) => q.contains('orderAsc')).length,
        1,
        reason: 'ترتيب \$id مطلوب في كل صفحة',
      );
      expect(
        queries
            .where((q) => q.contains('"limit"') || q.contains('limit'))
            .length,
        1,
      );
      expect(queries.where((q) => q.contains('cursorAfter')), isEmpty);
      // فلتر tombstones من القاعدة محفوظ.
      expect(queries.where((q) => q.contains('isNull')).length, 1);
    });

    test('مع cursor: cursorAfter يُضاف', () {
      final queries = SyncPullService.buildFullSyncPageQueries(
        baseQueries: SyncPullService.buildFullSyncQueries(),
        cursor: 'doc-42',
        pageSize: 100,
      );
      expect(queries.where((q) => q.contains('cursorAfter')).length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 3: UnifiedPullEngine — المسار التدفقي
  // ═══════════════════════════════════════════════════════════════════════
  group('UnifiedPullEngine — Streaming Full Pull', () {
    test(
      'بلا سقف: 450 مستنداً (5 صفحات) تُطبَّق كلها والمؤشر عند النفاد فقط',
      () async {
        // 4 صفحات كاملة (100) + صفحة ناقصة (50) = 450 مستنداً.
        final appliedIds = <String>[];
        final fetchCursors = <String?>[];

        final task = CollectionPullTask(
          name: 'booking_nights',
          streamFullSync: true,
          fetchPage: (queries) async {
            final cursor = queries
                .where((q) => q.contains('cursorAfter'))
                .map((q) => _cursorValueOf(q))
                .firstOrNull;
            fetchCursors.add(cursor);
            final start = cursor != null
                ? int.parse(cursor.split('-').last)
                : 0;
            final count = (start + 100 <= 400) ? 100 : 50;
            return List.generate(
              count,
              (i) => _doc('doc-${start + i + 1}', <String, dynamic>{
                'localUuid': 'night-${start + i + 1}',
                'lastModified': 1700000000 + start + i,
                'vectorClock': '{}',
                'deviceId': 'device-A',
              }),
            );
          },
          fetch: (plan) => throw StateError('legacy fetch must not run'),
          apply: (docs) async {
            appliedIds.addAll(docs.map((d) => d.$id));
            return docs.length;
          },
        );

        final result = await engine.run([task]);

        expect(result.recordsPulled, 450, reason: 'كل المستندات بلا سقف');
        expect(result.failedCollections, isEmpty);
        // الصفحة الأولى بلا cursor، وبعدها كل صفحة تستأنف بعد آخر $id.
        expect(fetchCursors.first, isNull);
        expect(fetchCursors[1], 'doc-100');
        expect(fetchCursors[2], 'doc-200');
        // المؤشر النهائي من max($updatedAt) — وليس من أول 1000 (الخلل القديم).
        expect(
          await checkpoints.getLastPullTs('booking_nights'),
          UnifiedPullEngine.updatedAtSecOf(
            _doc('x', {}, updatedAt: '2026-09-21T10:00:00.000Z'),
          ),
        );
        expect(await checkpoints.isFullSyncComplete('booking_nights'), isTrue);
        // تقدم الاستئناف مُمسح بعد الاكتمال.
        expect(await checkpoints.getFullSyncCursor('booking_nights'), isNull);
      },
    );

    test(
      'انقطاع الشبكة: المؤشر عند آخر صفحة نجحت والاستئناف من نفس الصفحة',
      () async {
        var failOnPage = 3; // تفشل الصفحة الثالثة (بعد تطبيق صفحتين).
        var fetchCalls = 0;
        final applied = <String>[];
        String? lastSeenCursorInFetch;

        Future<List<models.Document>> fetchPage(List<String> queries) async {
          fetchCalls++;
          final cursor = queries
              .where((q) => q.contains('cursorAfter'))
              .map((q) => _cursorValueOf(q))
              .firstOrNull;
          lastSeenCursorInFetch = cursor;
          if (fetchCalls == failOnPage) {
            throw Exception('network timeout — weak internet');
          }
          final start = cursor != null ? int.parse(cursor.split('-').last) : 0;
          // المجموعة محدودة (450 مستنداً) — الصفحة الأخيرة ناقصة (50) وهي
          // التي تُنهي السحب التدفقي؛ مولّد لا نهائي كان يُشغّل صمام 5000
          // صفحة ويُفشل المهمة في الدورة الثانية خطأً.
          const totalDocs = 450;
          final remaining = totalDocs - start;
          if (remaining <= 0) return const <models.Document>[];
          final count = remaining < 100 ? remaining : 100;
          return List.generate(
            count,
            (i) => _doc('doc-${start + i + 1}', <String, dynamic>{
              'localUuid': 'night-${start + i + 1}',
              'lastModified': 1700000000 + start + i,
              'vectorClock': '{}',
              'deviceId': 'device-A',
            }),
          );
        }

        final makeTask = () => CollectionPullTask(
          name: 'booking_nights',
          streamFullSync: true,
          fetchPage: fetchPage,
          fetch: (plan) => throw StateError('legacy fetch must not run'),
          apply: (docs) async {
            applied.addAll(docs.map((d) => d.$id));
            return docs.length;
          },
        );

        // الدورة الأولى: صفحتان نجحتا ثم انقطعت الشبكة.
        final firstRun = await engine.run([makeTask()]);
        expect(firstRun.failedCollections, [
          'booking_nights',
        ], reason: 'فشل المهمة يُسجَّل');
        expect(applied.length, 200, reason: 'صفحتان طُبّقتا قبل الانقطاع');
        // المؤشر عند نهاية الصفحة الثانية (crash-safe).
        expect(
          await checkpoints.getFullSyncCursor('booking_nights'),
          'doc-200',
        );
        // لم يُعلن اكتمال ولم يُثبَّت مؤشر Delta.
        expect(await checkpoints.isFullSyncComplete('booking_nights'), isFalse);
        expect(await checkpoints.getLastPullTs('booking_nights'), 0);

        // الدورة الثانية (بعد عودة الشبكة): تستأنف من doc-200 لا من الصفر.
        failOnPage = 0; // لا فشل هذه المرة.
        fetchCalls = 0;
        final secondRun = await engine.run([makeTask()]);
        expect(secondRun.failedCollections, isEmpty);
        // الاستئناف بدأ من cursorAfter(doc-200).
        expect(lastSeenCursorInFetch, isNotNull);
        expect(applied.length, 200 + 250, reason: 'الاستئناف أكمل البقية فقط');
        expect(await checkpoints.isFullSyncComplete('booking_nights'), isTrue);
      },
    );

    test('مجموعة فارغة: تبقى في وضع Full (استعلام رخيص) دون فقدان', () async {
      final task = CollectionPullTask(
        name: 'booking_nights',
        streamFullSync: true,
        fetchPage: (queries) async => const <models.Document>[],
        fetch: (plan) => throw StateError('legacy fetch must not run'),
        apply: (docs) async => 0,
      );

      final result = await engine.run([task]);
      expect(result.recordsPulled, 0);
      // لا اكتمال — الدورة التالية تعيد وضع Full (استعلام فارغ رخيص).
      expect(await checkpoints.isFullSyncComplete('booking_nights'), isFalse);
    });

    test(
      'المهام الكلاسيكية (بلا streamFullSync) لم تتغير — مسار fetch/apply',
      () async {
        final docs = [
          _doc('doc-1', {
            'localUuid': 'n1',
            'lastModified': 1,
            'vectorClock': '{}',
          }),
        ];
        var legacyFetchCalled = false;
        final task = CollectionPullTask(
          name: 'rooms',
          fetch: (plan) async {
            legacyFetchCalled = true;
            return docs;
          },
          apply: (d) async => d.length,
        );

        final result = await engine.run([task]);
        expect(legacyFetchCalled, isTrue);
        expect(result.recordsPulled, 1);
        expect(
          await checkpoints.isFullSyncComplete('rooms'),
          isTrue,
          reason:
              'commit الكلاسيكي: setLastPullTs(max \$updatedAt) يعلن '
              'الاكتمال كما قبل التعديل',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 4: IdResolver — فهرس الحجوزات الجماعي
  // ═══════════════════════════════════════════════════════════════════════
  group('IdResolver.buildBookingIndex — O(1) booking resolution', () {
    late IdResolver resolver;

    setUp(() async {
      resolver = IdResolver(db);
      await _seedBookings(db);
      await resolver.buildBookingIndex();
    });

    test('حل exact uuid', () async {
      final id = await resolver.resolveBooking(
        uuid: 'b-uuid-1',
        fromRemote: true,
      );
      expect(id, 1);
    });

    test('حل normalized (بحث بالشرطات لسجل مخزّن بدون شرطات)', () async {
      // b-uuid-2 مخزّن بـ UUID 32 حرفاً بدون شرطات (legacy)؛ البحث بالصيغة
      // القياسية بالشرطات يجب أن يُحل عبر الفهرس المقيس.
      final withDashes = '11111111-2222-3333-4444-555555555555';
      final id = await resolver.resolveBooking(
        uuid: withDashes,
        fromRemote: true,
      );
      expect(id, 2, reason: 'يجب حل صيغة UUID القديمة بدون شرطات');
    });

    test('حل serverId', () async {
      final id = await resolver.resolveBooking(serverId: 77, fromRemote: true);
      expect(id, 3);
    });

    test('uuid غير موجود → null (تخطي آمن — لا ربط خاطئ)', () async {
      final id = await resolver.resolveBooking(
        uuid: 'nonexistent-uuid',
        fromRemote: true,
      );
      expect(id, isNull);
    });

    test('localId من جهاز بعيد ممنوع حتى مع الفهرس (ربط خاطئ)', () async {
      final id = await resolver.resolveBooking(localId: 3, fromRemote: true);
      expect(
        id,
        isNull,
        reason: 'id المحلي autoIncrement يختلف بين الأجهزة — ممنوع بعيداً',
      );
    });

    test('localId محلي مسموح', () async {
      final id = await resolver.resolveBooking(localId: 3, fromRemote: false);
      expect(id, 3);
    });

    test('clearBookingIndex يعيد مسار SQL (نفس النتائج)', () async {
      resolver.clearBookingIndex();
      expect(resolver.hasBookingIndex, isFalse);
      final id = await resolver.resolveBooking(
        uuid: 'b-uuid-1',
        fromRemote: true,
      );
      expect(id, 1);
      final stripped = await resolver.resolveBooking(
        uuid: '11111111222233334444555555555555',
        fromRemote: true,
      );
      expect(stripped, 2, reason: 'مسار SQL يحل الصيغة المخزّنة كما هي');
    });
  });
}

/// يستخرج قيمة cursorAfter من نص استعلام Appwrite المتسلسل.
String? _cursorValueOf(String query) {
  // Query.cursorAfter يُسلسل كـ {"method":"cursorAfter","values":["doc-100"]}
  final match = RegExp(r'"values":\["([^"]+)"\]').firstMatch(query);
  return match?.group(1);
}

/// يبذر غرفة + 3 حجوزات (أحد UUIDs بدون شرطات — نمط legacy).
Future<void> _seedBookings(AppDatabase db) async {
  const now = 1700000000;
  await db.customStatement(
    "INSERT INTO rooms (room_number, type, price, status, image_url, "
    "cleaning_status, local_uuid, server_id, created_at, updated_at, "
    "deleted_at, last_modified, created_at_epoch, last_modified_epoch, "
    "version, origin, vector_clock, device_id, sync_timestamp) VALUES ("
    "'101', 'standard', 100.0, 'available', NULL, 'clean', "
    "'room-uuid-1', NULL, $now, $now, NULL, $now, $now, $now, 1, "
    "'local', '{}', 'device-A', $now)",
  );
  Future<void> insertBooking(int id, String uuid, int? serverId) async {
    final sid = serverId?.toString() ?? 'NULL';
    await db.customStatement(
      "INSERT INTO bookings (room_number, guest_name, guest_phone, "
      "guest_nationality, checkin_date, status, local_uuid, server_booking_id, "
      "created_at, updated_at, last_modified, created_at_epoch, "
      "last_modified_epoch, version, origin, vector_clock, device_id, "
      "sync_timestamp) VALUES ("
      "'101', 'Guest $id', '000$id', 'N/A', '2026-09-01 14:00:00', 'active', "
      "'$uuid', $sid, $now, $now, $now, $now, $now, 1, 'local', '{}', "
      "'device-A', $now)",
    );
  }

  await insertBooking(1, 'b-uuid-1', null);
  // UUID بدون شرطات (legacy من Drive/backup قديم) — 32 حرفاً.
  await insertBooking(2, '11111111222233334444555555555555', null);
  await insertBooking(3, 'b-uuid-3', 77);
}
