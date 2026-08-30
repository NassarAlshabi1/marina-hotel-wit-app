// ✅ اختبارات الفجوتان 3+4 (metadata-first) + مؤشرات الكيانات (Gap 1)
// تغطي:
//  1) SyncPullService.computeChangedIds — منطق حصر المتغيّر (نقي).
//  2) خريطة sync_remote_meta على قاعدة بيانات حقيقية في الذاكرة
//     (roundtrip / conflict-update / chunking / مسح كلي وجزئي).
//  3) مؤشرات السحب لكل كيان: الترحيل الكسول، التقدم الأحادي، نافذة
//     الأمان 15 ثانية، والمسح عند resetSyncState.
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncPullService.computeChangedIds (metadata-first diff)', () {
    test('الخريطة المحلية فارغة (أول تشغيل) → كل مستندات الخادم متغيرة', () {
      final changed = SyncPullService.computeChangedIds(
        serverMeta: {'a': 100, 'b': 200, 'c': 300},
        localMeta: {},
      );
      expect(changed.toSet(), {'a', 'b', 'c'});
      expect(changed.length, 3);
    });

    test('مطابقة تامة → لا شيء متغير', () {
      final changed = SyncPullService.computeChangedIds(
        serverMeta: {'a': 100, 'b': 200},
        localMeta: {'a': 100, 'b': 200},
      );
      expect(changed, isEmpty);
    });

    test('سجل جديد + سجل معدل + سجل مطابق → الأولان فقط', () {
      final changed = SyncPullService.computeChangedIds(
        serverMeta: {'a': 100, 'b': 250, 'new': 999},
        localMeta: {'a': 100, 'b': 200},
      );
      expect(changed.toSet(), {'b', 'new'});
    });

    test('طابع محلي أحدث من الخادم → يُعامل كمتغير (سلطة الخادم للمقارنة)', () {
      // حالة غير طبيعية نظرياً ($updatedAt لا يتراجع) لكن الأمان أولاً:
      // أي اختلاف ⇒ جلب كامل والمصالحة تتم لاحقاً بمنطق LWW/3-way.
      final changed = SyncPullService.computeChangedIds(
        serverMeta: {'a': 100},
        localMeta: {'a': 500},
      );
      expect(changed, ['a']);
    });

    test('مستندات بطابع غير مقروء تُجلب كاملة احتياطاً', () {
      final changed = SyncPullService.computeChangedIds(
        serverMeta: {'a': 100},
        localMeta: {'a': 100},
        unknownTsDocIds: ['mystery1', 'mystery2'],
      );
      expect(changed.toSet(), {'mystery1', 'mystery2'});
    });
  });

  group('SyncRemoteMeta helpers (in-memory drift database)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('upsert + get roundtrip لعدة كولكشنز', () async {
      await db.upsertRemoteMeta('bookings', {'doc1': 100, 'doc2': 200});
      await db.upsertRemoteMeta('rooms', {'r1': 300});

      expect(await db.getRemoteMetaMap('bookings'), {'doc1': 100, 'doc2': 200});
      expect(await db.getRemoteMetaMap('rooms'), {'r1': 300});
      expect(await db.getRemoteMetaMap('payments'), isEmpty);
    });

    test('التحديث على نفس docId يستبدل الطابع لا يكرر الصف', () async {
      await db.upsertRemoteMeta('bookings', {'doc1': 100});
      await db.upsertRemoteMeta('bookings', {'doc1': 250});

      final map = await db.getRemoteMetaMap('bookings');
      expect(map, {'doc1': 250});
    });

    test('الشرائح: 1200 مدخلاً (فوق حد الشريحة 500) تُخزن كلها', () async {
      final meta = {for (var i = 0; i < 1200; i++) 'doc_$i': 1700000000 + i};
      await db.upsertRemoteMeta('booking_nights', meta);

      final map = await db.getRemoteMetaMap('booking_nights');
      expect(map.length, 1200);
      expect(map['doc_0'], 1700000000);
      expect(map['doc_1199'], 1700000000 + 1199);
    });

    test('مسح كولكشن محدد لا يمس الآخرين', () async {
      await db.upsertRemoteMeta('bookings', {'doc1': 100});
      await db.upsertRemoteMeta('rooms', {'r1': 300});

      await db.clearRemoteMeta(collection: 'bookings');

      expect(await db.getRemoteMetaMap('bookings'), isEmpty);
      expect(await db.getRemoteMetaMap('rooms'), {'r1': 300});
    });

    test('المسح الكلي يمس الجميع (سلوك resetSyncState)', () async {
      await db.upsertRemoteMeta('bookings', {'doc1': 100});
      await db.upsertRemoteMeta('rooms', {'r1': 300});

      await db.clearRemoteMeta();

      expect(await db.getRemoteMetaMap('bookings'), isEmpty);
      expect(await db.getRemoteMetaMap('rooms'), isEmpty);
    });
  });

  group('Entity pull watermarks (per-entity, Gap 1)', () {
    late AppDatabase db;
    late SyncPullService pullService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      pullService = SyncPullService(
        appwriteService: AppwriteService(),
        database: db,
        outboxDao: OutboxDao(db),
      );
    });

    tearDown(() async {
      await pullService.clearEntityPullTsMap();
      await db.close();
    });

    Future<void> seedGlobalLastPullTs(int ts) async {
      await db
          .into(db.syncState)
          .insertOnConflictUpdate(
            SyncStateCompanion.insert(
              id: const drift.Value(1),
              lastPullTs: drift.Value(ts),
            ),
          );
    }

    test('الترحيل الكسول: كيان بلا مؤشر يهيأ من المؤشر العالمي', () async {
      await seedGlobalLastPullTs(1700000000);
      final ts = await pullService.getEntityPullTs('rooms');
      expect(ts, 1700000000);
      // يُثبَّت في الخريطة فبعد ذلك يقرأ من الخريطة مباشرة
      final map = await pullService.getEntityPullTsMap();
      expect(map['rooms'], 1700000000);
    });

    test('التقدم الأحادي: قيمة أصغر لا تتراجع بالمؤشر', () async {
      await pullService.updateEntityPullTs('bookings', 1700001000);
      await pullService.updateEntityPullTs('bookings', 1700000500);

      final ts = await pullService.getEntityPullTs('bookings');
      expect(ts, 1700001000);
    });

    test('نفس القيمة لا يغير شيئاً (idempotent)', () async {
      await pullService.updateEntityPullTs('payments', 1700001000);
      await pullService.updateEntityPullTs('payments', 1700001000);

      final ts = await pullService.getEntityPullTs('payments');
      expect(ts, 1700001000);
    });

    test('entityDeltaQueries يستخدم نافذة أمان 15 ثانية', () async {
      const ts = 1700001000;
      await pullService.updateEntityPullTs('debts', ts);

      final queries = await pullService.entityDeltaQueries('debts');
      expect(queries, hasLength(1));
      // الاستعلام يحمل ISO string للـ cutoff = ts - 15
      final expectedCutoff = DateTime.fromMillisecondsSinceEpoch(
        (ts - 15) * 1000,
        isUtc: true,
      ).toIso8601String();
      expect(queries.first, contains(expectedCutoff));
      expect(queries.first, contains(r'$updatedAt'));
    });

    test('كيان بلا مؤشر (≤0) → قائمة فارغة = سحب كامل للكيان وحده', () async {
      final queries = await pullService.entityDeltaQueries('guest_infos');
      expect(queries, isEmpty);
    });

    test('استقلالية الكيانات: فشل كيان لا يجمّد غيره', () async {
      await pullService.updateEntityPullTs('rooms', 1700005000);
      await pullService.updateEntityPullTs('bookings', 1700001000);

      // rooms تقدم، bookings تأخر — كل واحد يبني cutoff الخاص به
      final roomsQ = await pullService.entityDeltaQueries('rooms');
      final bookingsQ = await pullService.entityDeltaQueries('bookings');
      expect(roomsQ.first, isNot(equals(bookingsQ.first)));
      String cutoffIso(int ts) => DateTime.fromMillisecondsSinceEpoch(
        (ts - 15) * 1000,
        isUtc: true,
      ).toIso8601String();
      expect(roomsQ.first, contains(cutoffIso(1700005000))); // -15s أمان
      expect(bookingsQ.first, contains(cutoffIso(1700001000)));
    });

    test('المسح يعيد التهيئة من المؤشر العالمي في الدورة التالية', () async {
      await seedGlobalLastPullTs(1690000000);
      await pullService.updateEntityPullTs('rooms', 1700005000);

      await pullService.clearEntityPullTsMap();

      final ts = await pullService.getEntityPullTs('rooms');
      expect(ts, 1690000000);
    });
  });

  group('Schema v65', () {
    test(
      'قاعدة الذاكرة تُنشأ بأحدث schema ويوجد جدول sync_remote_meta',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        // أي عملية على الجدول تثبت وجوده وصحة أعمدته
        await db.upsertRemoteMeta('x', {'d': 1});
        expect(await db.getRemoteMetaMap('x'), {'d': 1});
        expect(db.schemaVersion, 65);
      },
    );
  });
}
