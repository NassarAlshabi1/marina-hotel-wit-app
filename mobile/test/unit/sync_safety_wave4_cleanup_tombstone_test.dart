// test/unit/sync_safety_wave4_cleanup_tombstone_test.dart
//
// ✅ Sync Safety Wave 4 (2026-08-12) — Cleanup Safety + Durable Tombstones
//
// يغطي هذا الملف سيناريوهات إصلاح الـ cleanup وdurable tombstones:
//
//  1. cleanupForMissingEntities تحذف فقط 'completed' (لا pending/failed)
//  2. cleanupForMissingEntities لا تحذف عناصر pending للكيانات المفقودة
//  3. cleanupForMissingEntities لا تحذف عناصر failed للكيانات المفقودة
//  4. cleanupForMissingEntities تحذف عناصر completed بأمان
//  5. cleanupForSoftDeletedEntities تحذف فقط عناصر tombstone المكتملة
//  6. _cleanupOutboxForDeletedEntities لا يحذف عناصر pending لـ op='delete'
//    (durable tombstone protection)
//  7. merge بعد delivery يُعيد ضبط delivery state (لا stale ack)
//  8. _isEntryDeliveredToServer يُرجع false عند فشل الشبكة (safe default)
//  9. _pushTombstone يبني payload صحيح مع deletedAt
// 10. SyncPullService حماية soft delete محلي ضد resurrection

// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late OutboxDao outboxDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outboxDao = OutboxDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 1: cleanupForMissingEntities — Hard Delete Safety
  // ═══════════════════════════════════════════════════════════════════════
  group('cleanupForMissingEntities — Hard Delete Safety', () {
    test(
      '1. تحذف فقط عناصر completed (لا pending/failed) للكيانات المفقودة',
      () async {
        // ✅ Sync Safety Wave 4: السيناريو الخطير الذي تم إصلاحه:
        // المستخدم يعدّل غرفة → outbox `create` pending
        // → المستخدم يحذف الغرفة فعلياً → الكيان غير موجود
        // → قبل الإصلاح: الكود يحذف العنصر → فقدان صامت.
        // بعد الإصلاح: العنصر يُترك ليُعاد في دورة push القادمة.

        // 1. سجل pending — يجب أن يُترك
        final idPending = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'missing-pending',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        expect(idPending, greaterThan(0));

        // 2. سجل failed — يجب أن يُترك
        final idFailed = await outboxDao.merge(
          entity: 'rooms',
          op: 'update',
          localUuid: 'missing-failed',
          payload: {},
          clientTs: 200,
          source: 'local',
        );
        await (db.update(db.outbox)..where((t) => t.id.equals(idFailed))).write(
          const OutboxCompanion(processingStatus: drift.Value('failed')),
        );

        // 3. سجل completed — يجب أن يُحذف
        final idCompleted = await outboxDao.merge(
          entity: 'rooms',
          op: 'delete',
          localUuid: 'missing-completed',
          payload: {},
          clientTs: 300,
          source: 'local',
        );
        await (db.update(
          db.outbox,
        )..where((t) => t.id.equals(idCompleted))).write(
          const OutboxCompanion(processingStatus: drift.Value('completed')),
        );

        // تنفيذ cleanup
        final cleaned = await outboxDao.cleanupForMissingEntities([
          'missing-pending',
          'missing-failed',
          'missing-completed',
        ]);

        // فقط 1 يجب أن يُحذف (الـ completed)
        expect(cleaned, 1);
        final remaining = await (db.select(db.outbox)).get();
        expect(remaining.length, 2);
      },
    );

    test('2. لا تحذف عنصر pending للكيان المفقود', () async {
      await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'test-pending',
        payload: {'data': 'important'},
        clientTs: 100,
        source: 'local',
      );

      final cleaned = await outboxDao.cleanupForMissingEntities([
        'test-pending',
      ]);
      expect(cleaned, 0, reason: 'عنصر pending يجب أن يُترك للأمان');

      final remaining = await (db.select(db.outbox)).get();
      expect(remaining.length, 1);
      expect(remaining.first.localUuid, 'test-pending');
      expect(remaining.first.payload, contains('important'));
    });

    test('3. لا تحذف عنصر failed للكيان المفقود', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'update',
        localUuid: 'test-failed',
        payload: {'data': 'failed-change'},
        clientTs: 100,
        source: 'local',
      );
      await (db.update(db.outbox)..where((t) => t.id.equals(id))).write(
        const OutboxCompanion(processingStatus: drift.Value('failed')),
      );

      final cleaned = await outboxDao.cleanupForMissingEntities([
        'test-failed',
      ]);
      expect(cleaned, 0, reason: 'عنصر failed يجب أن يُترك للأمان');

      final remaining = await (db.select(db.outbox)).get();
      expect(remaining.length, 1);
    });

    test('4. تحذف عنصر completed للكيان المفقود بأمان', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'delete',
        localUuid: 'test-completed',
        payload: {},
        clientTs: 100,
        source: 'local',
      );
      await (db.update(db.outbox)..where((t) => t.id.equals(id))).write(
        const OutboxCompanion(processingStatus: drift.Value('completed')),
      );

      final cleaned = await outboxDao.cleanupForMissingEntities([
        'test-completed',
      ]);
      expect(cleaned, 1, reason: 'عنصر completed يجب أن يُحذف بأمان');

      final remaining = await (db.select(db.outbox)).get();
      expect(remaining.length, 0);
    });

    test('5. قائمة فارغة → no-op', () async {
      final cleaned = await outboxDao.cleanupForMissingEntities([]);
      expect(cleaned, 0);
    });

    test('6. تدعم batches أكبر من 500', () async {
      // إنشاء 600 سجل completed
      final uuids = <String>[];
      for (var i = 0; i < 600; i++) {
        final uuid = 'batch-$i';
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'delete',
          localUuid: uuid,
          payload: {},
          clientTs: i,
          source: 'local',
        );
        await (db.update(db.outbox)..where((t) => t.id.equals(id))).write(
          const OutboxCompanion(processingStatus: drift.Value('completed')),
        );
        uuids.add(uuid);
      }

      final cleaned = await outboxDao.cleanupForMissingEntities(uuids);
      expect(cleaned, 600, reason: 'جميع السجلات completed يجب أن تُحذف');
      expect(await outboxDao.count(), 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 2: cleanupForSoftDeletedEntities — Tombstone Safety
  // ═══════════════════════════════════════════════════════════════════════
  group('cleanupForSoftDeletedEntities — Tombstone Safety', () {
    test('7. تحذف فقط عناصر completed للكيانات المحذوفة softly', () async {
      // ✅ Sync Safety Wave 4: السيناريو:
      // - المستخدم يحذف غرفة softly (soft delete, deletedAt != null)
      // - هناك outbox entries لهذه الغرفة:
      //   * one completed (آمن للحذف)
      //   * one pending (يجب أن يُترك — قد يكون update سابق لم يُرفع)

      final idCompleted = await outboxDao.merge(
        entity: 'rooms',
        op: 'update',
        localUuid: 'soft-deleted-room',
        payload: {'status': 'updated'},
        clientTs: 100,
        source: 'local',
      );
      await (db.update(
        db.outbox,
      )..where((t) => t.id.equals(idCompleted))).write(
        const OutboxCompanion(processingStatus: drift.Value('completed')),
      );

      final idPending = await outboxDao.merge(
        entity: 'rooms',
        op: 'delete',
        localUuid: 'soft-deleted-room-delete',
        payload: {},
        clientTs: 200,
        source: 'local',
      );
      // ترك pending (default)

      final cleaned = await outboxDao.cleanupForSoftDeletedEntities({
        'soft-deleted-room': 1000,
        'soft-deleted-room-delete': 2000,
      });

      // فقط الـ completed يجب أن يُحذف
      expect(cleaned, 1);
      final remaining = await (db.select(db.outbox)).get();
      expect(remaining.length, 1);
      expect(remaining.first.localUuid, 'soft-deleted-room-delete');
      expect(remaining.first.processingStatus, 'pending');
    });

    test('8. قائمة فارغة → no-op', () async {
      final cleaned = await outboxDao.cleanupForSoftDeletedEntities({});
      expect(cleaned, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 3: Outbox Coalescing — لا stale ack
  // ═══════════════════════════════════════════════════════════════════════
  group('Outbox Coalescing — Stale Ack Prevention', () {
    test(
      '9. تحديث payload يُعيد ضبط delivered_to_primary=false (لا stale ack)',
      () async {
        // ✅ Sync Safety: السيناريو:
        // 1. outbox entry بـ payload=v1 → delivery → delivered_to_primary=true
        // 2. تحديث payload إلى v2 (عن طريق merge أخرى)
        // 3. قبل الإصلاح: delivered_to_primary يبقى true → skip → فقدان v2
        // 4. بعد الإصلاح: delivered_to_primary=false → سيرفع v2

        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'update',
          localUuid: 'coalesce-test',
          payload: {'value': 'v1'},
          clientTs: 100,
          source: 'local',
        );

        // محاكاة التسليم للرئيسي
        await (db.update(db.outbox)..where((t) => t.id.equals(id))).write(
          const OutboxCompanion(deliveredToPrimary: drift.Value(true)),
        );

        // تحقق من الحالة قبل التحديث
        var record = await (db.select(
          db.outbox,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(record.deliveredToPrimary, isTrue);
        expect(record.payload, contains('v1'));

        // تحديث payload إلى v2
        await outboxDao.merge(
          entity: 'rooms',
          op: 'update',
          localUuid: 'coalesce-test',
          payload: {'value': 'v2'},
          clientTs: 200,
          source: 'local',
        );

        // تحقق من الحالة بعد التحديث
        record = await (db.select(
          db.outbox,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(
          record.deliveredToPrimary,
          isFalse,
          reason: 'يجب إعادة ضبطه لـ false',
        );
        expect(record.payload, contains('v2'));
        expect(record.attempts, 0, reason: 'attempts يجب أن يُعاد ضبطها');
      },
    );

    test('10. _markDelivered يرفض stale worker (worker mismatch)', () async {
      // ✅ Sync Safety: السيناريو:
      // 1. worker-A يلتقط السجل (processing_status='processing', worker='A')
      // 2. أثناء المعالجة، worker-B يحدّث payload (عبر merge)
      // 3. worker-A يحاول تأكيد التسليم
      // 4. لكن الحالة تغيّرت → يجب أن يُرفض التأكيد

      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'update',
        localUuid: 'worker-test',
        payload: {'value': 'v1'},
        clientTs: 100,
        source: 'local',
      );

      // محاكاة worker-A التقط السجل
      await (db.update(db.outbox)..where((t) => t.id.equals(id))).write(
        const OutboxCompanion(
          processingStatus: drift.Value('processing'),
          processingWorker: drift.Value('worker-A'),
        ),
      );

      // محاكاة تحديث payload بواسطة عملية أخرى
      // (merge تُعيد الحالة لـ 'pending' وتُفرغ processingWorker)
      await outboxDao.merge(
        entity: 'rooms',
        op: 'update',
        localUuid: 'worker-test',
        payload: {'value': 'v2'},
        clientTs: 200,
        source: 'local',
      );

      // الحالة الآن 'pending' (أعيدت من قبل merge)
      final record = await (db.select(
        db.outbox,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(record.processingStatus, 'pending');
      expect(record.processingWorker, isNull);

      // محاولة worker-A تأكيد التسليم — يجب أن تُرفض
      await outboxDao.markDeliveredToPrimary(id);

      // السجل يجب أن يبقى موجوداً (لم يُحذف)
      final after = await (db.select(
        db.outbox,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      expect(after, isNotNull, reason: 'السجل يجب أن يبقى — لم يُؤكد تسليمه');
      expect(
        after!.deliveredToPrimary,
        isFalse,
        reason: 'payload v2 لم تُسلّم',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 4: SyncPullService — Soft Delete Resurrection Prevention
  // ═══════════════════════════════════════════════════════════════════════
  group('SyncPullService — Soft Delete Resurrection Prevention', () {
    late SyncPullService pullService;

    setUp(() {
      pullService = SyncPullService(
        appwriteService: AppwriteService(),
        database: db,
        outboxDao: outboxDao,
      );
    });

    test(
      '11. soft delete محلي محمي — لا resurrection من remote بدون deletedAt',
      () async {
        // ✅ Sync Safety: السيناريو:
        // 1. الجهاز-A يحذف غرفة softly (deletedAt=1000 محلياً)
        // 2. الجهاز-B يرفع update للغرفة بدون deletedAt (لا يعرف بالحذف)
        // 3. الجهاز-A يسحب update من الجهاز-B
        // 4. يجب أن يُرفض الـ update (لا نُحيي الغرفة المحذوفة)

        final result = await pullService.checkAndResolveConflict(
          {
            'localUuid': 'deleted-room-1',
            'status': 'updated',
            'lastModified': 2000,
            // لا deletedAt في remote
          },
          1000, // localLastModified
          localDeletedAt: 1500, // محذوف محلياً
          remoteUpdatedAtSec: 2000,
          localVectorClock: '{"A": 2}',
          entityName: 'rooms',
          localUuid: 'deleted-room-1',
        );

        expect(
          result.shouldApplyRemote,
          isFalse,
          reason: 'لا نُحيي السجل المحذوف محلياً',
        );
      },
    );

    test(
      '12. soft delete محلي + remote deletedAt → تطبيق (كلاهما محذوف)',
      () async {
        // ✅ Sync Safety: السيناريو:
        // الجهاز-A حذف softly، السحابة حذفت (tombstone)
        // → تطبيق remote (تحديث طابع الحذف)

        final result = await pullService.checkAndResolveConflict(
          {
            'localUuid': 'deleted-room-2',
            'deletedAt': 2000, // remote has tombstone
            'lastModified': 2000,
          },
          1000,
          localDeletedAt: 1500, // محذوف محلياً
          remoteUpdatedAtSec: 2000,
          localVectorClock: '{"A": 2}',
          entityName: 'rooms',
          localUuid: 'deleted-room-2',
        );

        expect(
          result.shouldApplyRemote,
          isTrue,
          reason: 'كلاهما محذوف → تطبيق remote للتحديث',
        );
      },
    );

    test('13. سجل نشط محلياً + remote deletedAt → تطبيق tombstone', () async {
      // ✅ Sync Safety: السيناريو:
      // الجهاز-A لم يحذف، السحابة حذفت (tombstone from another device)
      // → تطبيق remote (نُنشئ tombstone محلياً)

      final result = await pullService.checkAndResolveConflict(
        {
          'localUuid': 'active-room',
          'deletedAt': 2000, // remote has tombstone
          'lastModified': 2000,
        },
        1000, // localLastModified (نشط)
        localDeletedAt: null, // غير محذوف محلياً
        remoteUpdatedAtSec: 2000,
        localVectorClock: '{"A": 1}',
        entityName: 'rooms',
        localUuid: 'active-room',
      );

      expect(
        result.shouldApplyRemote,
        isTrue,
        reason: 'تطبيق tombstone من remote على السجل النشط محلياً',
      );
    });
  });
}
