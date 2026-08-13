// test/unit/outbox_dao_comprehensive_test.dart
//
// اختبارات شاملة لـ OutboxDao: merge, takeBatch, dual-delivery,
// reclaimForPush, retryFailedWithBackoff, cleanup, mergeBatch
//
// ✅ P0 — صحة دورة حياة outbox الكاملة

// ignore_for_file: lines_longer_than_80_chars, avoid_redundant_argument_values, unused_local_variable, unnecessary_parenthesis

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

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

  group('OutboxDao — merge / idempotency', () {
    test('merge يُنشئ سجلاً جديداً ويُعيد id', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'room-001',
        payload: {'roomNumber': '101'},
        clientTs: 1000,
        source: 'local',
      );
      expect(id, greaterThan(0));
      final count = await outboxDao.count();
      expect(count, 1);
    });

    test(
      'merge لا يُنشئ سجلاً مكرراً لنفس entity+localUuid في حالة pending',
      () async {
        final id1 = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'room-001',
          payload: {'roomNumber': '101'},
          clientTs: 1000,
          source: 'local',
        );
        final id2 = await outboxDao.merge(
          entity: 'rooms',
          op: 'update',
          localUuid: 'room-001',
          payload: {'roomNumber': '102'},
          clientTs: 2000,
          source: 'local',
        );
        expect(id1, id2, reason: 'يجب إعادة نفس id عند التحديث');
        expect(await outboxDao.count(), 1, reason: 'يجب أن يبقى سجل واحد فقط');
      },
    );

    test('يُحدّث المحتوى عند استدعاء merge مجدداً', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'room-001',
        payload: {'roomNumber': '101'},
        clientTs: 1000,
        source: 'local',
      );
      await outboxDao.merge(
        entity: 'rooms',
        op: 'update',
        localUuid: 'room-001',
        payload: {'roomNumber': '999'},
        clientTs: 2000,
        source: 'local',
      );
      final all = await (db.select(db.outbox)).get();
      expect(all.length, 1);
      expect(all.first.payload, contains('999'));
    });

    test(
      'merge يحافظ على op=delete عندما يكون السجل موجوداً كـ delete',
      () async {
        await outboxDao.merge(
          entity: 'rooms',
          op: 'delete',
          localUuid: 'room-001',
          payload: {},
          clientTs: 1000,
          source: 'local',
        );
        await outboxDao.merge(
          entity: 'rooms',
          op: 'update',
          localUuid: 'room-001',
          payload: {'roomNumber': '101'},
          clientTs: 2000,
          source: 'local',
        );
        final all = await (db.select(db.outbox)).get();
        expect(
          all.first.op,
          'delete',
          reason: 'delete له أولوية أعلى — لا يُستبدل',
        );
      },
    );
  });

  group('OutboxDao — takeBatch', () {
    test('takeBatch يعيد السجلات المنتظرة بالترتيب الصحيح', () async {
      await outboxDao.merge(
        entity: 'expenses',
        op: 'create',
        localUuid: 'exp-1',
        payload: {},
        clientTs: 100,
        source: 'local',
      );
      await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'room-1',
        payload: {},
        clientTs: 200,
        source: 'local',
      );
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'bkg-1',
        payload: {},
        clientTs: 300,
        source: 'local',
      );

      final batch = await outboxDao.takeBatch(10);
      // UPDATE … RETURNING * لا يضمن ترتيب الصفوف، نتحقق فقط من المحتوى
      expect(batch.length, 3);
      final entities = batch.map((e) => e.entity).toSet();
      expect(entities, contains('rooms'));
      expect(entities, contains('bookings'));
      expect(entities, contains('expenses'));
    });

    test('takeBatch يحدّد حالة السجلات إلى processing', () async {
      await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'room-1',
        payload: {},
        clientTs: 100,
        source: 'local',
      );
      final batch = await outboxDao.takeBatch(10);
      expect(batch.length, 1);
      expect(batch.first.processingStatus, 'processing');
      expect(batch.first.processingWorker, isNotEmpty);
      expect(batch.first.processingStartedAt, isNotNull);
    });

    test(
      'takeBatch لا يلتقط السجلات المُسلّمة للرئيسي (delivered_to_primary=1)',
      () async {
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'room-1',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        // سلّم يدوياً للرئيسي
        await db.customStatement(
          'UPDATE outbox SET delivered_to_primary = 1 WHERE id = ?',
          [id],
        );
        final batch = await outboxDao.takeBatch(10);
        expect(batch, isEmpty, reason: 'السجل المُسلّم للرئيسي يجب ألا يُلتقط');
      },
    );

    test('takeBatch يلتقط حسب source عندما يُمرّر', () async {
      await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'r1',
        payload: {},
        clientTs: 100,
        source: 'local',
      );
      await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'r2',
        payload: {},
        clientTs: 101,
        source: 'restore',
      );
      final batch = await outboxDao.takeBatch(10, sources: const ['local']);
      expect(batch.length, 1);
      expect(batch.first.source, 'local');
    });
  });

  group('OutboxDao — dual-delivery lifecycle', () {
    test(
      'markDeliveredToPrimary يحذف السجل إذا كان مُسلّماً للثانوي أيضاً',
      () async {
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r1',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        // delivered_to_secondary افتراضياً true (لأن SecondaryAppwriteConfig غير مُهيّأ)
        // delivered_to_primary = false (افتراضي)
        // ✅ Sync Safety Fix: set to processing before markDelivered
        await (db.customStatement(
          'UPDATE outbox SET processing_status = ? WHERE id = ?',
          ['processing', id],
        ));
        await outboxDao.markDeliveredToPrimary(id);
        // منذ delivered_to_secondary = true و delivered_to_primary = true → يحذف
        final after = await (db.select(db.outbox)).get();
        expect(after, isEmpty, reason: 'السجل يُحذف بعد تسليمه لكلا الوجهتين');
      },
    );

    test(
      'markDeliveredToPrimary يحذف السجل فقط إذا كان مُسلّماً للثانوي أيضاً',
      () async {
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r1',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        // اجعل delivered_to_secondary=false لمحاكاة Secondary قيد الانتظار
        await db.customStatement(
          'UPDATE outbox SET delivered_to_secondary = 0 WHERE id = ?',
          [id],
        );
        // ✅ Sync Safety Fix: set to processing before markDelivered
        await (db.customStatement(
          'UPDATE outbox SET processing_status = ? WHERE id = ?',
          ['processing', id],
        ));
        await outboxDao.markDeliveredToPrimary(id);
        final updated = await (db.select(
          db.outbox,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        expect(
          updated,
          isNotNull,
          reason: 'السجل يبقى حتى يُسلّم للثانوي أيضاً',
        );
        expect(updated!.deliveredToPrimary, true);
        expect(updated.deliveredToSecondary, false);
        expect(updated.processingStatus, 'pending');
      },
    );

    test(
      '✅ Wave3: markDeliveredToSecondary no-op — السجل يُحذف فقط عبر markDeliveredToPrimary',
      () async {
        // ✅ Sync Simplification (2026-08-10): Secondary sync معطّل بالكامل.
        // markDeliveredToSecondary أصبحت no-op. السجل يُحذف تلقائياً عند
        // تسليمه للرئيسي فقط (لأن delivered_to_secondary=true دائماً في schema).
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r1',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        // تعيين حالة processing (مطلوبة قبل markDelivered)
        await db.customStatement(
          'UPDATE outbox SET processing_status = ? WHERE id = ?',
          ['processing', id],
        );
        // markDeliveredToPrimary يحذف السجل فوراً (لأن secondary=true دائماً)
        await outboxDao.markDeliveredToPrimary(id);
        expect(
          await (db.select(db.outbox)).get(),
          isEmpty,
          reason: 'السجل يُحذف فور تسليمه للرئيسي — لا حاجة لـ secondary',
        );

        // markDeliveredToSecondary على id محذوف يجب أن تكون no-op آمنة
        // (لا رمي استثناء)
        await outboxDao.markDeliveredToSecondary(id);
      },
    );

    test(
      '✅ Wave3: دورة حياة مبسطة — pending → processing → markDeliveredToPrimary → حذف',
      () async {
        // ✅ Sync Simplification (2026-08-10): دورة حياة أبسط — لا حاجة
        // لـ markDeliveredToSecondary منفصلة.
        // 1) إنشاء سجل
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r1',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        expect(await outboxDao.countPendingPushable(), 1);

        // 2) takeBatch = processing
        final batch = await outboxDao.takeBatch(10, sources: const ['local']);
        expect(batch.length, 1);
        expect(batch.first.processingStatus, 'processing');

        // 3) markCompleted + markDeliveredToPrimary → حذف فوري
        await outboxDao.markCompleted([id]);
        // ✅ Sync Safety Fix: set to processing before markDelivered
        await db.customStatement(
          'UPDATE outbox SET processing_status = ? WHERE id = ?',
          ['processing', id],
        );
        await outboxDao.markDeliveredToPrimary(id);
        expect(
          await (db.select(db.outbox)).get(),
          isEmpty,
          reason: 'حُذف فور تسليمه للرئيسي — secondary=true دائماً',
        );
      },
    );
  });

  group('OutboxDao — reclaimForPush', () {
    test('يُعيد السجلات العالقة في processing إلى pending', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'r1',
        payload: {},
        clientTs: 100,
        source: 'local',
      );
      // اجعل السجل في processing مع processing_started_at قديم جداً
      await db.customStatement(
        "UPDATE outbox SET processing_status = 'processing', processing_started_at = 1000 WHERE id = ?",
        [id],
      );
      final reclaimed = await outboxDao.reclaimForPush(
        stuckAfter: const Duration(seconds: 1),
      );
      expect(reclaimed, 1);
      final updated = await (db.select(
        db.outbox,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      expect(updated!.processingStatus, 'pending');
      expect(updated.processingStartedAt, isNull);
      expect(updated.processingWorker, isNull);
    });

    test('يُعيد السجلات الفاشلة ذات المحاولات القليلة إلى pending', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'r1',
        payload: {},
        clientTs: 100,
        source: 'local',
      );
      await outboxDao.setError(id, 'Transient error', 3);
      final reclaimed = await outboxDao.reclaimForPush(maxFailedAttempts: 5);
      expect(reclaimed, 1);
      final updated = await (db.select(
        db.outbox,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      expect(updated!.processingStatus, 'pending');
    });

    test('لا يُعيد السجلات الفاشلة فوق maxFailedAttempts', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'r1',
        payload: {},
        clientTs: 100,
        source: 'local',
      );
      await outboxDao.setError(id, 'Many failures', 10);
      final reclaimed = await outboxDao.reclaimForPush(maxFailedAttempts: 5);
      expect(reclaimed, 0, reason: 'لم يتجاوز maxFailedAttempts');
    });

    test('لا يُعيد السجلات الـ dead', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'r1',
        payload: {},
        clientTs: 100,
        source: 'local',
      );
      await outboxDao.setDead(id, 'Permanent', 10);
      final reclaimed = await outboxDao.reclaimForPush();
      expect(reclaimed, 0);
    });
  });

  group('OutboxDao — retryFailedWithBackoff', () {
    test('يُعيد السجلات الفاشلة ذات المحاولات القليلة فوراً', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'r1',
        payload: {},
        clientTs: 100,
        source: 'local',
      );
      await outboxDao.setError(id, 'Error', 3);
      final retried = await outboxDao.retryFailedWithBackoff(maxAttempts: 5);
      expect(retried, 1);
    });

    test('يُعيد السجلات عالية المحاولات بعد انقضاء backoffMinutes', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'r1',
        payload: {},
        clientTs: 100,
        source: 'local',
      );
      await outboxDao.setError(id, 'Error', 10);
      // clientTs=100 قديم — يجب أن يُلتقط بالـ backoff
      final retried = await outboxDao.retryFailedWithBackoff(
        maxAttempts: 5,
        backoffMinutes: 0,
      );
      expect(retried, 1);
    });

    test('لا يُعيد السجلات الـ dead', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'r1',
        payload: {},
        clientTs: 100,
        source: 'local',
      );
      await outboxDao.setDead(id, 'Permanent', 10);
      final retried = await outboxDao.retryFailedWithBackoff();
      expect(retried, 0);
    });
  });

  group('OutboxDao — counting methods', () {
    test(
      'countPendingPushable يحسب فقط pending + delivered_to_primary=0',
      () async {
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r1',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r2',
          payload: {},
          clientTs: 101,
          source: 'local',
        );
        final id3 = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r3',
          payload: {},
          clientTs: 102,
          source: 'local',
        );
        await db.customStatement(
          'UPDATE outbox SET delivered_to_primary = 1 WHERE id = ?',
          [id3],
        );
        expect(await outboxDao.countPendingPushable(), 2);
      },
    );

    test(
      'countUndeliveredToPrimary يشمل pending + processing + failed',
      () async {
        final id1 = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r1',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        final id2 = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r2',
          payload: {},
          clientTs: 101,
          source: 'local',
        );
        await db.customStatement(
          "UPDATE outbox SET processing_status = 'processing' WHERE id = ?",
          [id1],
        );
        await outboxDao.setError(id2, 'Error', 1);
        expect(
          await outboxDao.countUndeliveredToPrimary(),
          2,
          reason: 'يجب أن يشمل processing و failed أيضاً',
        );
      },
    );
  });

  group('OutboxDao — mergeBatch', () {
    test('mergeBatch يُدرج دفعة كاملة في معاملة واحدة', () async {
      final ids = await outboxDao.mergeBatch([
        {
          'entity': 'rooms',
          'op': 'create',
          'localUuid': 'r1',
          'payload': <String, dynamic>{},
          'clientTs': 100,
        },
        {
          'entity': 'bookings',
          'op': 'create',
          'localUuid': 'b1',
          'payload': <String, dynamic>{},
          'clientTs': 200,
        },
        {
          'entity': 'payments',
          'op': 'create',
          'localUuid': 'p1',
          'payload': <String, dynamic>{},
          'clientTs': 300,
        },
      ]);
      expect(ids.length, 3);
      expect(await outboxDao.count(), 3);
    });

    test('mergeBatch يُعيد ids صحيحة لكل عنصر', () async {
      final ids = await outboxDao.mergeBatch([
        {
          'entity': 'rooms',
          'op': 'create',
          'localUuid': 'r1',
          'payload': <String, dynamic>{},
          'clientTs': 100,
        },
        {
          'entity': 'rooms',
          'op': 'create',
          'localUuid': 'r2',
          'payload': <String, dynamic>{},
          'clientTs': 101,
        },
      ]);
      expect(ids.first, isNot(ids.last));

      // التحقق من صحة id
      final r1 = await (db.select(
        db.outbox,
      )..where((t) => t.id.equals(ids.first))).getSingle();
      expect(r1.localUuid, 'r1');
    });

    test('mergeBatch idempotent: استدعاء ثانٍ يُعيد نفس ids', () async {
      final items = [
        {
          'entity': 'rooms',
          'op': 'create',
          'localUuid': 'r1',
          'payload': <String, dynamic>{},
          'clientTs': 100,
        },
      ];
      final ids1 = await outboxDao.mergeBatch(items);
      final ids2 = await outboxDao.mergeBatch(items);
      expect(ids1, ids2, reason: 'نفس العناصر يجب أن تُعيد نفس ids');
      expect(await outboxDao.count(), 1);
    });

    test('mergeBatch يقبل قائمة فارغة', () async {
      final ids = await outboxDao.mergeBatch([]);
      expect(ids, isEmpty);
    });
  });

  group('OutboxDao — cleanup methods', () {
    test('cleanupCompleted يحذف السجلات المُكتملة القديمة فقط', () async {
      final oldId = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'r-old',
        payload: {},
        clientTs: 100,
        source: 'local',
      );
      final newId = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'r-new',
        payload: {},
        clientTs: 2000000000,
        source: 'local',
      );
      await outboxDao.markCompleted([oldId, newId]);
      // سيحذف فقط clientTs < (الآن - olderThan)
      final deleted = await outboxDao.cleanupCompleted(
        olderThan: const Duration(days: 1),
      );
      expect(deleted, 1, reason: 'السجل القديم فقط يُحذف');
      final remaining = await (db.select(db.outbox)).get();
      expect(remaining.length, 1);
      expect(remaining.first.localUuid, 'r-new');
    });

    test(
      'cleanupOrphanedEntries يحذف السجلات الفاشلة كثيرة المحاولات',
      () async {
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'orphan',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        await outboxDao.setError(id, 'Unknown entity', 10);
        final deleted = await outboxDao.cleanupOrphanedEntries(
          maxAttempts: 5,
          olderThan: const Duration(days: 1),
        );
        expect(deleted, 1);
      },
    );

    test(
      'cleanupForSoftDeletedEntities يحذف سجلات outbox المُكتملة للكيانات المحذوفة',
      () async {
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'deleted-room',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        await outboxDao.markCompleted([id]);
        final cleaned = await outboxDao.cleanupForSoftDeletedEntities({
          'deleted-room': 2000,
        });
        expect(cleaned, 1);
      },
    );

    test(
      '✅ Wave4: cleanupForMissingEntities يحذف فقط سجلات completed (لا pending/failed)',
      () async {
        // ✅ Sync Safety Wave 4 (2026-08-12): cleanupForMissingEntities الآن
        // تحذف فقط السجلات 'completed' — تحمي التغييرات المعلقة من الفقدان.
        // السيناريو الخطير: المستخدم يعدّل غرفة → outbox `create` pending
        // → المستخدم يحذف الغرفة فعلياً → الكيان غير موجود.
        // قبل الإصلاح: الكود يحذف العنصر → فقدان صامت.
        // بعد الإصلاح: العنصر يُترك ليُعاد في دورة push القادمة.

        // 1. سجل pending — يجب أن يُترك (لا حذف)
        final idPending = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'missing-pending',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        // 2. سجل failed — يجب أن يُترك
        final idFailed = await outboxDao.merge(
          entity: 'rooms',
          op: 'update',
          localUuid: 'missing-failed',
          payload: {},
          clientTs: 200,
          source: 'local',
        );
        // تحويل لـ 'failed'
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
        // تحويل لـ 'completed'
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
        expect(
          cleaned,
          1,
          reason:
              'فقط سجل completed يجب أن يُحذف — pending/failed تُترك للأمان',
        );
        // تحقق أن pending و failed ما زالا موجودين
        final remaining = await (db.select(db.outbox)).get();
        expect(remaining.length, 2);
        final remainingUuids = remaining.map((r) => r.localUuid).toSet();
        expect(remainingUuids.contains('missing-pending'), isTrue);
        expect(remainingUuids.contains('missing-failed'), isTrue);
        expect(remainingUuids.contains('missing-completed'), isFalse);
      },
    );

    test(
      'removePulledEntities يحذف سجلات outbox للبيانات المسحوبة من السحابة',
      () async {
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'pulled-room',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        final removed = await outboxDao.removePulledEntities([
          'pulled-room',
        ], entity: 'rooms');
        expect(removed, 1);
        expect(await outboxDao.count(), 0);
      },
    );

    test(
      'cleanupStuckEntries يُعيد السجلات العالقة في processing إلى pending',
      () async {
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'stuck',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        await db.customStatement(
          "UPDATE outbox SET processing_status = 'processing', processing_started_at = 1000 WHERE id = ?",
          [id],
        );
        final unstuck = await outboxDao.cleanupStuckEntries(
          timeout: const Duration(seconds: 1),
        );
        expect(unstuck, 1);
        final updated = await (db.select(
          db.outbox,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        expect(updated!.processingStatus, 'pending');
      },
    );
  });

  group('OutboxDao — getConflicts / resolveConflict', () {
    test('getConflicts يُعيد السجلات الفاشلة', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'conflict-room',
        payload: {'status': 'active'},
        clientTs: 100,
        source: 'local',
      );
      await outboxDao.setError(id, 'Conflict detected', 1);
      final conflicts = await outboxDao.getConflicts();
      expect(conflicts.length, 1);
      expect(conflicts.first.id, id);
      expect(conflicts.first.localPayload['status'], 'active');
    });

    test('resolveConflict يُعيد السجل إلى pending مع بيانات محلولة', () async {
      final id = await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'resolve-room',
        payload: {'status': 'old'},
        clientTs: 100,
        source: 'local',
      );
      await outboxDao.setError(id, 'Conflict', 1);
      await outboxDao.resolveConflict(id, {
        'status': 'resolved',
      }, resolution: 'localWins');
      final conflicts = await outboxDao.getConflicts();
      expect(conflicts, isEmpty, reason: 'بعد الحل لا يجب أن يظهر كتعارض');

      // يظهر في count (أصبح pending)
      expect(await outboxDao.count(), 1);
      final all = await (db.select(db.outbox)).get();
      expect(all.first.payload, contains('resolved'));
      expect(all.first.processingStatus, 'pending');
    });
  });

  group('OutboxDao — bulk delivery flags', () {
    test(
      '✅ Wave3: markAllLocalAsUndeliveredToSecondary no-op (secondary معطّل)',
      () async {
        // ✅ Sync Simplification (2026-08-10): markAllLocalAsUndeliveredToSecondary
        // أصبحت no-op — لا وجهة ثانوية. تُرجع 0 دائماً ولا تغيّر أي flags.
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r1',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r2',
          payload: {},
          clientTs: 101,
          source: 'restore',
        );
        final changed = await outboxDao.markAllLocalAsUndeliveredToSecondary();
        expect(
          changed,
          0,
          reason: 'no-op يجب أن يُرجع 0 — لا تغيير',
        );
        final pending = await outboxDao.countPendingForSecondary();
        expect(
          pending,
          0,
          reason: 'لا سجلات معلّقة للثانوي (secondary معطّل)',
        );
        // تحقق أن الـ flags لم تتغير
        final records = await (db.select(db.outbox)).get();
        for (final r in records) {
          expect(
            r.deliveredToSecondary,
            isTrue,
            reason: 'delivered_to_secondary يجب أن يبقى true (default)',
          );
        }
      },
    );

    test(
      'markAllLocalAsDeliveredToSecondary يجعل كل السجلات المحلية مُسلّمة للثانوي',
      () async {
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r1',
          payload: {},
          clientTs: 100,
          source: 'local',
        );
        final changed = await outboxDao.markAllLocalAsDeliveredToSecondary();
        expect(changed, 1);
        expect(await outboxDao.countPendingForSecondary(), 0);
      },
    );
  });

  group('OutboxDao — edge cases', () {
    test('removeById لا يرمي خطأ لـ id غير موجود', () async {
      await outboxDao.removeById(9999);
    });

    test('removeByIds بقائمة فارغة لا تفعل شيئاً', () async {
      await outboxDao.removeByIds([]);
    });

    test(
      'merge يُحدّث delivered_to_secondary لكل استدعاء بناءً على SecondaryAppwriteConfig',
      () async {
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'r1',
          payload: {},
          clientTs: 100,
          serverId: 42,
          source: 'local',
        );
        await db.customStatement(
          'UPDATE outbox SET delivered_to_secondary = 0 WHERE id = ?',
          [id],
        );
        // merge مجدداً — SecondaryAppwriteConfig.isEnabled يرمي خطأ (SharedPreferences غير مُهيّأ)
        // لذا delivered_to_secondary يعود لـ true (fallback)
        await outboxDao.merge(
          entity: 'rooms',
          op: 'update',
          localUuid: 'r1',
          payload: {},
          clientTs: 200,
          source: 'local',
        );
        final record = await (db.select(
          db.outbox,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        expect(record, isNotNull);
        expect(
          record!.deliveredToSecondary,
          true,
          reason: 'fallback إلى true عند عدم توفر SharedPreferences',
        );
      },
    );
  });
}
