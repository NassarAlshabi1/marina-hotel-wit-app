// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

/// اختبارات smoke عملية للتحقق من أن OutboxDao.setDead يعمل فعلاً مع DB.
///
/// تستخدم Drift NativeDatabase.memory() — DB مؤقتة في الذاكرة لا تحتاج
/// ملفات على القرص. تنشأ لكل اختبار وتُدمَّر في النهاية.
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

  group('OutboxDao — Dead State (smoke test مع DB حقيقي)', () {
    test(
      'P0-2: setDead ينقل السجل لحالة dead نهائية',
      () async {
        // 1) أضف سجل outbox جديد
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'test-room-001',
          payload: {'roomNumber': '101'},
          clientTs: DateTime.now().millisecondsSinceEpoch,
          source: 'local',
        );

        // 2) ضعه في dead
        await outboxDao.setDead(id, 'Permanent (400): Bad Request', 5);

        // 3) تحقّق أن countDead = 1
        final deadCount = await outboxDao.countDead();
        expect(deadCount, 1,
            reason: 'بعد setDead على سجل واحد، countDead يجب أن يكون 1');

        // 4) تحقّق أن listDead يُرجع السجل
        final deadList = await outboxDao.listDead();
        expect(deadList.length, 1);
        expect(deadList.first.id, id);
        expect(deadList.first.processingStatus, 'dead');
        expect(deadList.first.lastError, 'Permanent (400): Bad Request');
        expect(deadList.first.attempts, 5);

        // 5) تأكّد أن count لا يحسبه (لأنه لم يعد 'pending' أو 'failed')
        final pendingCount = await outboxDao.count(sources: const ['local']);
        expect(pendingCount, 0,
            reason: 'السجل dead يجب ألا يُحسب ضمن pending/failed');
      },
    );

    test(
      'P0-2: reviveFromDead يُعيد السجل لحالة pending',
      () async {
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'test-room-002',
          payload: {'roomNumber': '102'},
          clientTs: DateTime.now().millisecondsSinceEpoch,
          source: 'local',
        );

        await outboxDao.setDead(id, 'Test dead', 10);
        expect(await outboxDao.countDead(), 1);

        // revive
        await outboxDao.reviveFromDead(id);

        // يجب أن يختفي من dead
        expect(await outboxDao.countDead(), 0,
            reason: 'بعد reviveFromDead، countDead يجب أن يكون 0');

        // ويظهر في pending (لأن revive يضع processing_status='pending')
        // ✅ ملاحظة: count() يحسب 'pending'+'failed'، لذلك يجب أن يكون 1
        final pendingCount = await outboxDao.count(sources: const ['local']);
        expect(pendingCount, 1,
            reason: 'السجل يجب أن يعود لـ pending بعد revive — '
                'ملاحظة: حتى لو delivered_to_secondary=true، count() '
                'يحسب السجل لأنه يفحص processing_status فقط');
      },
    );

    test(
      'P0-1: السجلات الـ dead لا تُلتقط بواسطة _takeUndeliveredBatch',
      () async {
        // أنشئ 3 سجلات: 1 pending، 1 failed، 1 dead
        // ✅ ملاحظة: merge() يضع delivered_to_secondary=true افتراضياً إذا
        // لم تكن SecondaryAppwriteConfig مهيّأة (SharedPreferences غير متاح
        // في الاختبارات). لذلك نضعها يدوياً لـ 0 (false) لمحاكاة
        // Secondary مُفعّل يحتاج للرفع.
        final id1 = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'room-pending',
          payload: {},
          clientTs: DateTime.now().millisecondsSinceEpoch,
          source: 'local',
        );
        final id2 = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'room-failed',
          payload: {},
          clientTs: DateTime.now().millisecondsSinceEpoch + 1,
          source: 'local',
        );
        final id3 = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'room-dead',
          payload: {},
          clientTs: DateTime.now().millisecondsSinceEpoch + 2,
          source: 'local',
        );

        // محاكاة Secondary مُفعّل: ضع delivered_to_secondary=0 يدوياً
        await db.customStatement(
          'UPDATE outbox SET delivered_to_secondary = 0 WHERE id IN (?, ?, ?)',
          [id1, id2, id3],
        );

        // ضع id2 في failed، id3 في dead
        await outboxDao.setError(id2, 'Transient error', 1);
        await outboxDao.setDead(id3, 'Permanent', 5);

        // ✅ الحالة المتوقّعة:
        // - id1: pending (delivered_to_secondary=0)
        // - id2: failed (attempts=1, delivered_to_secondary=0)
        // - id3: dead (attempts=5, delivered_to_secondary=0)

        // ✅ تأكّد أن count(sources:['local']) = 2 (pending + failed)
        // dead لا يُحسب
        final liveCount = await outboxDao.count(sources: const ['local']);
        expect(liveCount, 2,
            reason: 'pending + failed = 2 (dead مستبعد)');

        // ✅ تأكّد أن countDead = 1
        expect(await outboxDao.countDead(), 1);

        // ✅ محاكاة استعلام SecondarySyncManager._takeUndeliveredBatch:
        // WHERE delivered_to_secondary=0 AND processing_status IN ('pending','failed')
        //   AND attempts < 10
        // يجب أن يلتقط id1 و id2 فقط، وليس id3 (dead)
        final claimed = await db.customSelect(
          'SELECT id, processing_status, attempts FROM outbox '
          'WHERE delivered_to_secondary = 0 '
          "AND processing_status IN ('pending', 'failed') "
          'AND attempts < 10 '
          'ORDER BY client_ts ASC',
          readsFrom: {db.outbox},
        ).get();

        final claimedIds = claimed.map((r) => r.read<int>('id')).toSet();
        expect(claimedIds, contains(id1), reason: 'pending يجب أن يُلتقط');
        expect(claimedIds, contains(id2), reason: 'failed يجب أن يُلتقط');
        expect(claimedIds, isNot(contains(id3)),
            reason: 'dead يجب ألا يُلتقط — هذا جوهر إصلاح P0-2');
      },
    );

    test(
      'P0-1: السجلات الـ failed مع attempts >= maxAttempts لا تُلتقط',
      () async {
        // أنشئ سجل failed مع attempts = 10 (يساوي maxAttempts)
        final id = await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'room-max-attempts',
          payload: {},
          clientTs: DateTime.now().millisecondsSinceEpoch,
          source: 'local',
        );

        // محاكاة Secondary مُفعّل
        await db.customStatement(
          'UPDATE outbox SET delivered_to_secondary = 0 WHERE id = ?',
          [id],
        );

        // ضع attempts = 10 (يساوي maxAttempts في SecondarySyncManager)
        await outboxDao.setError(id, 'Max attempts reached', 10);

        // ✅ محاكاة استعلام _takeUndeliveredBatch مع فلتر attempts < 10
        final claimed = await db.customSelect(
          'SELECT id FROM outbox '
          'WHERE delivered_to_secondary = 0 '
          "AND processing_status IN ('pending', 'failed') "
          'AND attempts < 10 '
          'ORDER BY client_ts ASC',
          readsFrom: {db.outbox},
        ).get();

        final claimedIds = claimed.map((r) => r.read<int>('id')).toSet();
        expect(claimedIds, isNot(contains(id)),
            reason: 'السجل مع attempts=10 يجب ألا يُلتقط (filter: attempts<10) '
                '— هذا جوهر إصلاح P0-2');
      },
    );
  });
}
