// test/unit/sync_backoff_test.dart
//
// ✅ (2026-11-05) درع انحدار لصمام «المؤشر المحجوب» في محرك السحب الموحّد.
//
// الخلفية:
//   عقد «لا يتقدّم المؤشر فوق الفشل» (2026-11-02) منع الفقدان الصامت، لكنه
//   بلا صمام: مستند واحد يفشل تطبيقه دائماً يُبقي مؤشر المجموعة محجوباً إلى
//   الأبد ⇒ كل دورة تعيد سحب نفس نافذة الدلتا (وتتضخّم) + سجل أخطاء متكرر
//   بلا فائدة. الحل المُختبَر هنا:
//     - الدورتان الأولى والثانية: إعادة محاولة فورية (نفس السلوك السابق).
//     - من الثالثة: تراجع تصاعدي حتى سقف 6 ساعات.
//     - أول نجاح يُصفّر الحالة.
//   ولا يتغيّر **دلالة المؤشر** إطلاقاً: لا يتقدّم فوق فشل أبداً.
//
// الاختبارات بلا شبكة: مهام سحب مزيّفة + ساعة قابلة للاستبدال.

// ignore_for_file: lines_longer_than_80_chars

import 'package:appwrite/models.dart' as models;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_checkpoint_store.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';
import 'package:marina_hotel_mobile/services/sync_core/unified_pull_engine.dart';

models.Document _doc(
  String id, {
  String updatedAt = '2026-11-01T10:00:00.000Z',
}) {
  return models.Document(
    $id: id,
    $sequence: 1,
    $collectionId: 'expenses',
    $databaseId: 'test_db',
    $createdAt: '2026-11-01T00:00:00.000Z',
    $updatedAt: updatedAt,
    $permissions: const <String>[],
    data: <String, dynamic>{
      'localUuid': id,
      'expenseType': 'other',
      'lastModified': 1760000000,
      'vectorClock': '{}',
      'deviceId': 'device-A',
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncPullService pullService;
  late SyncCheckpointStore checkpoints;
  late UnifiedPullEngine engine;
  late int fakeNow;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    pullService = SyncPullService(
      appwriteService: AppwriteService(),
      database: db,
      outboxDao: OutboxDao(db),
    );
    fakeNow = 1760000000;
    checkpoints = SyncCheckpointStore(db, clock: () => fakeNow);
    engine = UnifiedPullEngine(
      checkpoints: checkpoints,
      pullService: pullService,
    );
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 1) جدول التراجع — دالة نقية
  // ═══════════════════════════════════════════════════════════════════════
  group('SyncCheckpointStore.backoffSecondsFor', () {
    test('الدورتان الأولى والثانية بلا تأخير (سلوك ما قبل التراجع)', () {
      expect(SyncCheckpointStore.backoffSecondsFor(0), 0);
      expect(SyncCheckpointStore.backoffSecondsFor(1), 0);
      expect(SyncCheckpointStore.backoffSecondsFor(2), 0);
      expect(SyncCheckpointStore.directRetryCycles, 2);
    });

    test('من الثالثة تتصاعد ثم تُقيَّد بسقف 6 ساعات', () {
      expect(SyncCheckpointStore.backoffSecondsFor(3), 15 * 60);
      expect(SyncCheckpointStore.backoffSecondsFor(4), 30 * 60);
      expect(SyncCheckpointStore.backoffSecondsFor(5), 60 * 60);
      expect(SyncCheckpointStore.backoffSecondsFor(6), 120 * 60);
      expect(
        SyncCheckpointStore.backoffSecondsFor(50),
        SyncCheckpointStore.maxBackoffSeconds,
      );
      expect(SyncCheckpointStore.maxBackoffSeconds, 6 * 60 * 60);
    });

    test('رتيب غير متناقص', () {
      var previous = -1;
      for (var i = 0; i <= 20; i++) {
        final current = SyncCheckpointStore.backoffSecondsFor(i);
        expect(current, greaterThanOrEqualTo(previous));
        previous = current;
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2) حالة التراجع في المخزن
  // ═══════════════════════════════════════════════════════════════════════
  group('SyncCheckpointStore — حالة الفشل/التراجع', () {
    test('الحالة الابتدائية: لا فشل والمحاولة مستحقة فوراً', () async {
      expect(await checkpoints.getConsecutiveFailures('expenses'), 0);
      expect(await checkpoints.getRetryAfterTs('expenses'), 0);
      expect(await checkpoints.isRetryDue('expenses'), isTrue);
    });

    test(
      'أول فشلين: العدّاد يرتفع والمحاولة تبقى مستحقة (تأخير صفر)',
      () async {
        expect(await checkpoints.registerFailure('expenses'), 1);
        expect(await checkpoints.isRetryDue('expenses'), isTrue);

        expect(await checkpoints.registerFailure('expenses'), 2);
        expect(await checkpoints.isRetryDue('expenses'), isTrue);
        expect(await checkpoints.getRetryAfterTs('expenses'), fakeNow);
      },
    );

    test('الفشل الثالث: تراجع 15 دقيقة ثم يستحق بعد انقضائها', () async {
      await checkpoints.registerFailure('expenses');
      await checkpoints.registerFailure('expenses');
      expect(await checkpoints.registerFailure('expenses'), 3);

      expect(await checkpoints.isRetryDue('expenses'), isFalse);
      expect(await checkpoints.getRetryAfterTs('expenses'), fakeNow + 15 * 60);

      fakeNow += 15 * 60 + 1;
      expect(await checkpoints.isRetryDue('expenses'), isTrue);
    });

    test('النجاح يُصفّر العدّاد وموعد المحاولة', () async {
      await checkpoints.registerFailure('expenses');
      await checkpoints.registerFailure('expenses');
      await checkpoints.registerFailure('expenses');

      await checkpoints.registerSuccess('expenses');

      expect(await checkpoints.getConsecutiveFailures('expenses'), 0);
      expect(await checkpoints.getRetryAfterTs('expenses'), 0);
      expect(await checkpoints.isRetryDue('expenses'), isTrue);
    });

    test('reset() يصفّر العدّاد والتراجع مع المؤشر', () async {
      await checkpoints.setLastPullTs('expenses', 1760000500);
      await checkpoints.registerFailure('expenses');
      await checkpoints.registerFailure('expenses');
      await checkpoints.registerFailure('expenses');

      await checkpoints.reset('expenses');

      expect(await checkpoints.getLastPullTs('expenses'), 0);
      expect(await checkpoints.isFullSyncComplete('expenses'), isFalse);
      expect(await checkpoints.getConsecutiveFailures('expenses'), 0);
      expect(await checkpoints.isRetryDue('expenses'), isTrue);
    });

    test('hasAnyCheckpoint: يفرّق بين قاعدة جديدة وقاعدة سُحب منها', () async {
      expect(await checkpoints.hasAnyCheckpoint(), isFalse);
      await checkpoints.setLastPullTs('rooms', 1760000000);
      expect(await checkpoints.hasAnyCheckpoint(), isTrue);
      await checkpoints.resetAll();
      expect(await checkpoints.hasAnyCheckpoint(), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 3) المحرك: التخطي أثناء التراجع + الشفاء
  // ═══════════════════════════════════════════════════════════════════════
  group('UnifiedPullEngine — تراجع المجموعة المتعثرة', () {
    CollectionPullTask failingTask(void Function() onApply) {
      return CollectionPullTask(
        name: 'expenses',
        fetch: (plan) async => <models.Document>[_doc('exp-1')],
        apply: (docs) async {
          onApply();
          throw StateError('apply failed (simulated corrupt record)');
        },
      );
    }

    test('أول فشلين يُعاد سحبهما في الدورة التالية', () async {
      var applyCalls = 0;
      final task = failingTask(() => applyCalls++);

      final first = await engine.run([task]);
      expect(first.failedCollections, ['expenses']);
      expect(applyCalls, 1);

      // لا تأخير بعد الفشل الأول ⇒ الدورة التالية تحاول فعلاً.
      expect(await checkpoints.isRetryDue('expenses'), isTrue);
      final second = await engine.run([task]);
      expect(second.failedCollections, ['expenses']);
      expect(applyCalls, 2);
    });

    test('الفشل الثالث يفتح فترة تراجع: لا طلب شبكة ولا إعادة سحب', () async {
      var applyCalls = 0;
      var fetchCalls = 0;
      final task = CollectionPullTask(
        name: 'expenses',
        fetch: (plan) async {
          fetchCalls++;
          return <models.Document>[_doc('exp-1')];
        },
        apply: (docs) async {
          applyCalls++;
          throw StateError('apply failed (simulated corrupt record)');
        },
      );

      await engine.run([task]);
      await engine.run([task]);
      await engine.run([task]); // الثالث: يفتح التراجع
      expect(applyCalls, 3);
      expect(fetchCalls, 3);
      expect(await checkpoints.isRetryDue('expenses'), isFalse);

      // الدورة الرابعة: متخطاة — لا fetch ولا apply، لكن الفشل يبقى مرئياً.
      final skipped = await engine.run([task]);
      expect(skipped.failedCollections, ['expenses']);
      expect(fetchCalls, 3, reason: 'لا طلب شبكة أثناء فترة التراجع');
      expect(applyCalls, 3);
      // المؤشر لم يتقدّم (لا فقدان صامت) — المجموعة لا تزال غير مكتملة.
      expect(await checkpoints.isFullSyncComplete('expenses'), isFalse);
      expect(await checkpoints.getLastPullTs('expenses'), 0);
    });

    test('بعد انقضاء التراجع تُعاد المحاولة وتنجح ⇒ تُصفَّر الحالة', () async {
      var shouldFail = true;
      var applyCalls = 0;
      final task = CollectionPullTask(
        name: 'expenses',
        fetch: (plan) async => <models.Document>[_doc('exp-1')],
        apply: (docs) async {
          applyCalls++;
          if (shouldFail) {
            throw StateError('apply failed (simulated corrupt record)');
          }
          return docs.length;
        },
      );

      await engine.run([task]);
      await engine.run([task]);
      await engine.run([task]);
      expect(await checkpoints.isRetryDue('expenses'), isFalse);

      // انقضاء فترة التراجع + شفاء السبب (وصول الأب المفقود مثلاً).
      fakeNow += SyncCheckpointStore.maxBackoffSeconds + 1;
      shouldFail = false;

      final healed = await engine.run([task]);
      expect(healed.failedCollections, isEmpty);
      expect(applyCalls, 4, reason: 'محاولة واحدة بعد انقضاء التراجع');
      expect(await checkpoints.getConsecutiveFailures('expenses'), 0);
      expect(await checkpoints.isRetryDue('expenses'), isTrue);
      expect(await checkpoints.getLastPullTs('expenses'), greaterThan(0));
    });

    test('مجموعة متعثرة لا تمنع بقية المجموعات من العمل', () async {
      final applied = <String>[];
      final flaky = CollectionPullTask(
        name: 'expenses',
        fetch: (plan) async => <models.Document>[_doc('exp-1')],
        apply: (docs) async {
          throw StateError('always fails');
        },
      );
      final healthy = CollectionPullTask(
        name: 'rooms',
        fetch: (plan) async => <models.Document>[_doc('room-1')],
        apply: (docs) async {
          applied.addAll(docs.map((d) => d.$id));
          return docs.length;
        },
      );

      // ثلاث دورات لفتح تراجع expenses.
      for (var i = 0; i < 3; i++) {
        final result = await engine.run([flaky, healthy]);
        expect(result.failedCollections, ['expenses']);
        expect(result.recordsPulled, 1);
      }
      expect(applied, ['room-1', 'room-1', 'room-1']);

      // الدورة الرابعة: expenses متخطاة، rooms يعمل كالمعتاد.
      final skippedRun = await engine.run([flaky, healthy]);
      expect(skippedRun.failedCollections, ['expenses']);
      expect(skippedRun.recordsPulled, 1);
      expect(applied.length, 4);
    });
  });
}
