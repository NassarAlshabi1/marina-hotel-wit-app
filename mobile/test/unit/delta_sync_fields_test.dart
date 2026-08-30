// test/unit/delta_sync_fields_test.dart
//
// ✅ اختبارات مزامنة Delta Appwrite (2026-08-08).
// تثبت:
//  - البناء الصحيح لاستعلامات delta المعتمدة على زمن الخادم ($updatedAt)
//    لا على زمن الجهاز، مع نافذة أمان 15 ثانية.
//  - عند lastPullTs <= 0 يُرجَع [] (سحب كامل لا delta).
//  - ارتباط delta بمعالجة التعارضات: كل مستند مُسحوب يمر عبر
//    checkAndResolveConflict (مغطى في conflict_resolution_fix_test).
//
// ملاحظة: syncTimestamp يُرسَل في الـ payload (push) لكن المؤشر/الفلتر
// يعتمدان على $updatedAt الخادمي — هذا متعمد لتفادي انحراف ساعات الأجهزة.

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';
import '../helpers/test_database.dart';

void main() {
  group('SyncPullService.buildDeltaQueries', () {
    late SyncPullService pull;
    late AppDatabase db;

    setUp(() {
      db = TestDatabase.create();
      pull = SyncPullService(
        appwriteService: AppwriteService(),
        database: db,
        outboxDao: OutboxDao(db),
      );
    });

    tearDown(() => db.close());

    test('lastPullTs <= 0 → سحب كامل ([])', () async {
      final q = await pull.buildDeltaQueries(0);
      expect(q, isEmpty);
    });

    test('lastPullTs > 0 → فلتر updatedAt مع نافذة أمان 15s', () async {
      // ✅ Sync Safety Wave 2 (2026-08-12): full_sync_complete يجب أن = 1
      // قبل السماح بـ delta queries. نضبطه يدوياً هنا للاختبار.
      await pull.markFullSyncComplete();

      // lastPullTs = 1000 ثانية، cutoff = 1000 - 15 = 985 ثانية.
      final q = await pull.buildDeltaQueries(1000);
      expect(q, hasLength(2));
      expect(q.first, contains(r'$updatedAt'));
      // cutoff ISO لـ 985 ثانية = 1970-01-01T00:16:25.000Z
      expect(q.first, contains('1970-01-01T00:16:25'));
      // يجب أن يكون greaterThan (ليس greaterThanEqual) لتفادي التكرار اللانهائي.
      expect(q.first, contains('greaterThan'));
      // الحد العلوي يثبت snapshot الدورة أثناء cursor pagination.
      expect(q[1], contains('lessThanEqual'));
      expect(q[1], contains(r'$updatedAt'));
    });

    test(
      'تقدّم المؤشر لا يفقد السجلات: cutoff أقدم بـ 15s من lastPullTs',
      () async {
        // ✅ Sync Safety Wave 2 (2026-08-12): full_sync_complete يجب أن = 1
        await pull.markFullSyncComplete();

        const lastPull = 2000000000; // ~2033
        final q = await pull.buildDeltaQueries(lastPull);
        // cutoff ISO لـ (2000000000 - 15) ثانية.
        final expectedCutoffIso = DateTime.fromMillisecondsSinceEpoch(
          (lastPull - 15) * 1000,
          isUtc: true,
        ).toIso8601String();
        expect(q.first, contains(expectedCutoffIso));
        expect(q, hasLength(2));
        expect(q[1], contains('lessThanEqual'));
      },
    );

    test(
      '✅ Wave2: buildDeltaQueries تُرجع [] عندما full_sync_complete = 0',
      () async {
        // لا نستدعي markFullSyncComplete — full_sync_complete = 0 افتراضياً
        final q = await pull.buildDeltaQueries(1000);
        expect(
          q,
          isEmpty,
          reason:
              'عندما full_sync_complete = 0، يجب إجبار full fetch '
              'حتى لو lastPullTs > 0',
        );
      },
    );

    test('bookingNightsDeltaQueries يحاكي نفس منطق delta', () {
      final q = pull.bookingNightsDeltaQueries(
        1000,
        remoteEpochIsMillis: false,
      );
      expect(q, hasLength(2));
      expect(q.first, contains(r'$updatedAt'));
      expect(q[1], contains('lessThanEqual'));
    });

    test('bookingNightsDeltaQueries(lastPullTs=0) → سحب كامل', () {
      final q = pull.bookingNightsDeltaQueries(0, remoteEpochIsMillis: false);
      expect(q, isEmpty);
    });
  });
}
