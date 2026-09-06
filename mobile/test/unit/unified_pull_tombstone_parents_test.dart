// ✅ إصلاح (2026-09-07) — اختبار ربط آلية الآباء المرجعية بمسار السحب.
//
// الخلفية المثبتة: `SyncPullService.entityNeedsTombstoneParents` كانت
// معرّفة ومختبرة لكن بلا أي موقع استدعاء في مسار الإنتاج (كود ميت) —
// فكان Full pull يستبعد الموظفين المحذوفين (tombstones) وتبقى سحوبات
// رواتبهم يتيمة على الأجهزة الجديدة (سحابة الإنتاج: الموظفان
// serverId=11/12 مرتبط بهما 128 سحوبة راتب — 382,000 + 272,500).
//
// هذا الاختبار يثبت أن `UnifiedPullEngine.plan()` يوصّل الآلية فعلياً:
//   - خطة Full لـ employees بلا فلتر tombstones.
//   - بقية المجموعات تحتفظ بفلتر tombstones.
//   - خطط Delta لا تتأثر (استعلامات $updatedAt لا تفلتر الحذف أصلاً).
//   - `SyncCheckpointStore.reset` يعيد المجموعة إلى وضع Full — وهي
//     الآلية التي يبنى عليها الإصلاح الأحادي للأجهزة المتأثرة
//     (repair_tombstone_parents_v1 في AppwriteSyncManager).
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_checkpoint_store.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';
import 'package:marina_hotel_mobile/services/sync_core/unified_pull_engine.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late SyncCheckpointStore checkpoints;
  late UnifiedPullEngine engine;

  setUp(() {
    db = TestDatabase.create();
    checkpoints = SyncCheckpointStore(db);
    final pullService = SyncPullService(
      appwriteService: AppwriteService(),
      database: db,
      outboxDao: OutboxDao(db),
    );
    engine = UnifiedPullEngine(
      checkpoints: checkpoints,
      pullService: pullService,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('UnifiedPullEngine.plan — توصيل entityNeedsTombstoneParents', () {
    test(
      'employees في وضع Full: بلا فلتر tombstones (تُسحب المحذوفات أيضاً)',
      () async {
        final plan = await engine.plan('employees');
        expect(plan.isFullSync, isTrue);
        expect(
          plan.queries,
          isEmpty,
          reason:
              'includeTombstones=true يعيد استعلامات فارغة — '
              'يجب أن تصل الموظفان المحذوفان serverId=11/12 محلياً',
        );
      },
    );

    test('salary_withdrawals في وضع Full: يحتفظ بفلتر tombstones', () async {
      final plan = await engine.plan('salary_withdrawals');
      expect(plan.isFullSync, isTrue);
      expect(plan.queries, hasLength(1));
      expect(plan.queries.single, contains('deletedAt'));
    });

    test(
      'employees بعد اكتمال checkpoint: Delta ولا يفلتر tombstones',
      () async {
        await checkpoints.setLastPullTs('employees', 1700000000);
        final plan = await engine.plan('employees');
        expect(plan.isFullSync, isFalse);
        expect(plan.sinceTs, 1700000000);
        expect(plan.queries, hasLength(1));
        expect(plan.queries.single, contains(r'$updatedAt'));
        expect(
          plan.queries.single,
          isNot(contains('deletedAt')),
          reason: 'استعلامات Delta تصل tombstones الحذف اللاحق طبيعياً',
        );
      },
    );

    test('بقية المجموعات في وضع Full تحتفظ بفلتر tombstones (عينة)', () async {
      for (final collection in const ['bookings', 'rooms', 'salary_cycles']) {
        final plan = await engine.plan(collection);
        expect(plan.isFullSync, isTrue, reason: collection);
        expect(plan.queries, hasLength(1), reason: collection);
        expect(plan.queries.single, contains('deletedAt'), reason: collection);
      }
    });

    test('reset يعيد المجموعة إلى وضع Full (أساس الإصلاح الأحادي)', () async {
      await checkpoints.setLastPullTs('salary_withdrawals', 1700000000);
      expect((await engine.plan('salary_withdrawals')).isFullSync, isFalse);
      await checkpoints.reset('salary_withdrawals');
      final plan = await engine.plan('salary_withdrawals');
      expect(plan.isFullSync, isTrue);
      expect(plan.sinceTs, 0);
      expect(plan.queries.single, contains('deletedAt'));
    });
  });
}
