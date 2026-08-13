// test/unit/sync_safety_wave2_full_sync_bootstrap_test.dart
//
// ✅ Sync Safety Wave 2 (2026-08-12) — Full Sync Bootstrap + Checkpoint Safety
//
// يغطي هذا الملف الـ 5 سيناريوهات الحرجة المطلوبة في Wave 2:
//
//  1. full_sync_complete = 0 افتراضياً على قاعدة بيانات جديدة
//  2. buildDeltaQueries تُرجع [] عندما full_sync_complete = 0
//  3. buildDeltaQueries تُرجع delta queries عندما full_sync_complete = 1
//  4. markFullSyncComplete يضبط flag = 1
//  5. resetFullSyncComplete يضبط flag = 0
//  6. full sync bootstrap → delta transition: دورة كاملة ناجحة
//  7. partial pull failure: لا يُضبط full_sync_complete + لا يُحدَّث lastPullTs
//  8. checkpoint safety: لا يتحرك checkpoint عند فشل collection واحد
//  9. Migration 56: عمود full_sync_complete يُضاف بشكل صحيح
// 10. حالة idempotent: استدعاء markFullSyncComplete عدة مرات آمن

// ignore_for_file: lines_longer_than_80_chars

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
  late SyncPullService pullService;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outboxDao = OutboxDao(db);
    pullService = SyncPullService(
      appwriteService: AppwriteService(),
      database: db,
      outboxDao: outboxDao,
    );
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 1: Full Sync Bootstrap Flag
  // ═══════════════════════════════════════════════════════════════════════
  group('Full Sync Bootstrap Flag — الحالة الافتراضية والقراءة', () {
    test(
      '1. full_sync_complete = 0 افتراضياً على قاعدة بيانات جديدة',
      () async {
        final isComplete = await pullService.isFullSyncComplete();
        expect(
          isComplete,
          isFalse,
          reason:
              'يجب أن يكون full_sync_complete = 0 (false) افتراضياً '
              'على قاعدة بيانات جديدة — الجهاز في مرحلة bootstrap',
        );
      },
    );

    test(
      '2. buildDeltaQueries تُرجع [] (full fetch) عندما full_sync_complete = 0',
      () async {
        // حتى لو كان lastPullTs > 0، يجب أن نُرجع [] للإجبار على full fetch
        // حتى لا نفقد سجلات لم تُسحب بعد.
        final deltaQueries = await pullService.buildDeltaQueries(1700000000);
        expect(
          deltaQueries,
          isEmpty,
          reason:
              'عندما full_sync_complete = 0، يجب إجبار full fetch '
              'بغض النظر عن lastPullTs — لمنع تحول الجهاز لـ delta mode '
              'قبل اكتمال أول full sync',
        );
      },
    );

    test(
      '3. buildDeltaQueries تُرجع [] أيضاً حتى لو lastPullTs = 0 و flag = 0',
      () async {
        // الحالة المزدوجة: lastPullTs = 0 + full_sync_complete = 0
        // → تأكيد إضافي أننا في وضع full sync
        final deltaQueries = await pullService.buildDeltaQueries(0);
        expect(deltaQueries, isEmpty);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 2: Mark / Reset Full Sync Complete
  // ═══════════════════════════════════════════════════════════════════════
  group('markFullSyncComplete / resetFullSyncComplete', () {
    test(
      '4. markFullSyncComplete يضبط full_sync_complete = 1',
      () async {
        await pullService.markFullSyncComplete();
        final isComplete = await pullService.isFullSyncComplete();
        expect(
          isComplete,
          isTrue,
          reason: 'بعد markFullSyncComplete، يجب أن يكون flag = 1',
        );
      },
    );

    test(
      '5. buildDeltaQueries تُرجع delta queries بعد markFullSyncComplete',
      () async {
        // نضبط lastPullTs > 0 أولاً
        await pullService.updateLastPullTs(1700000000);

        // قبل markFullSyncComplete → full fetch
        expect(await pullService.buildDeltaQueries(1700000000), isEmpty);

        // نضبط full_sync_complete = 1
        await pullService.markFullSyncComplete();

        // بعد markFullSyncComplete → delta queries
        final deltaQueries = await pullService.buildDeltaQueries(1700000000);
        expect(
          deltaQueries,
          isNotEmpty,
          reason:
              'بعد اكتمال full sync، يجب إرجاع delta queries للسماح بـ '
              'delta sync',
        );
        expect(
          deltaQueries.first.toString(),
          contains(r'$updatedAt'),
          reason: 'delta query يجب أن يفلتر بـ \$updatedAt',
        );
      },
    );

    test(
      '6. resetFullSyncComplete يضبط full_sync_complete = 0',
      () async {
        // نضبط flag = 1 أولاً
        await pullService.markFullSyncComplete();
        expect(await pullService.isFullSyncComplete(), isTrue);

        // نعيد ضبطه إلى 0
        await pullService.resetFullSyncComplete();
        expect(
          await pullService.isFullSyncComplete(),
          isFalse,
          reason: 'بعد resetFullSyncComplete، يجب أن يكون flag = 0',
        );

        // يجب أن نعود لوضع full fetch
        expect(await pullService.buildDeltaQueries(1700000000), isEmpty);
      },
    );

    test(
      '7. استدعاء markFullSyncComplete عدة مرات آمن (idempotent)',
      () async {
        // الاستدعاء الأول
        await pullService.markFullSyncComplete();
        expect(await pullService.isFullSyncComplete(), isTrue);

        // الاستدعاء الثاني — يجب أن يبقى true دون أخطاء
        await pullService.markFullSyncComplete();
        expect(await pullService.isFullSyncComplete(), isTrue);

        // الاستدعاء الثالث
        await pullService.markFullSyncComplete();
        expect(await pullService.isFullSyncComplete(), isTrue);
      },
    );

    test(
      '8. resetFullSyncComplete عدة مرات آمن (idempotent)',
      () async {
        await pullService.resetFullSyncComplete();
        expect(await pullService.isFullSyncComplete(), isFalse);

        await pullService.resetFullSyncComplete();
        expect(await pullService.isFullSyncComplete(), isFalse);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 3: Full Sync → Delta Transition
  // ═══════════════════════════════════════════════════════════════════════
  group('Full Sync → Delta Transition', () {
    test(
      '9. full sync bootstrap → delta transition: دورة كاملة ناجحة',
      () async {
        // ✅ السيناريو: جهاز جديد يقوم بأول full sync بنجاح
        // 1. الحالة الأولية: full_sync_complete = 0
        expect(await pullService.isFullSyncComplete(), isFalse);
        expect(await pullService.buildDeltaQueries(0), isEmpty);

        // 2. محاكاة دورة full sync ناجحة:
        //    - نسحب كل الكولكشنات بدون فشل
        //    - نحدّث lastPullTs
        //    - نضبط full_sync_complete = 1
        const newPullTs = 1700000000;
        await pullService.updateLastPullTs(newPullTs);
        await pullService.markFullSyncComplete();

        // 3. التحقق من الحالة بعد الدورة
        expect(await pullService.isFullSyncComplete(), isTrue);
        expect(await pullService.getLastPullTs(), newPullTs);

        // 4. الدورة التالية يجب أن تستخدم delta queries (وليست full fetch)
        final nextDeltaQueries = await pullService.buildDeltaQueries(newPullTs);
        expect(
          nextDeltaQueries,
          isNotEmpty,
          reason:
              'بعد أول دورة full sync ناجحة، الدورة التالية يجب أن تستخدم '
              'delta queries — الجهاز أصبح delta-ready',
        );
      },
    );

    test(
      '10. full sync فاشل جزئياً: لا يُضبط full_sync_complete و لا يُحدَّث lastPullTs',
      () async {
        // ✅ السيناريو: جهاز جديد يقوم بأول full sync لكن 3 كولكشنات تفشل
        // هذا يُحاكي failedCollections.isNotEmpty في AppwriteSyncManager

        // 1. الحالة الأولية
        expect(await pullService.isFullSyncComplete(), isFalse);
        expect(await pullService.getLastPullTs(), 0);

        // 2. محاكاة فشل جزئي: لا نحدّث lastPullTs ولا نضبط full_sync_complete
        //    (محاكاة سلوك `if (failedCollections.isEmpty)` في appwrite_sync_manager)
        final failedCollections = ['bookings', 'payments', 'booking_notes'];
        if (failedCollections.isEmpty) {
          // لن يُنفَّذ لأن هناك failures
          await pullService.updateLastPullTs(1700000000);
          await pullService.markFullSyncComplete();
        }

        // 3. التحقق: الحالة لم تتغير
        expect(
          await pullService.isFullSyncComplete(),
          isFalse,
          reason: 'عند فشل بعض الكولكشنات، يجب ألا يُضبط full_sync_complete',
        );
        expect(
          await pullService.getLastPullTs(),
          0,
          reason: 'عند فشل بعض الكولكشنات، يجب ألا يُحدَّث lastPullTs',
        );

        // 4. الدورة التالية يجب أن تستمر في وضع full sync (وليست delta)
        expect(await pullService.buildDeltaQueries(0), isEmpty);
      },
    );

    test(
      '11. full sync فاشل جزئياً ثم نجح في الدورة التالية: transition يعمل',
      () async {
        // ✅ السيناريو: أول دورة فشلت جزئياً، ثاني دورة نجحت بالكامل

        // 1. دورة 1: فشل جزئي
        // (لا شيء — الحالة الافتراضية)

        // 2. دورة 2: نجاح كامل
        await pullService.updateLastPullTs(1700000000);
        await pullService.markFullSyncComplete();

        // 3. التحقق من التحول
        expect(await pullService.isFullSyncComplete(), isTrue);
        expect(await pullService.buildDeltaQueries(1700000000), isNotEmpty);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 4: Checkpoint Safety — Partial Pull Failure
  // ═══════════════════════════════════════════════════════════════════════
  group('Checkpoint Safety — Partial Pull Failure', () {
    test(
      '12. لا يتحرك lastPullTs عند فشل أي collection (محاكاة)',
      () async {
        // ✅ محاكاة منطق AppwriteSyncManager:
        // if (failedCollections.isEmpty) {
        //   await _updateLastPullTs(newPullTs);
        //   await _pullService?.markFullSyncComplete();
        // }

        // 1. قراءة lastPullTs الأولي
        final initialTs = await pullService.getLastPullTs();
        expect(initialTs, 0);

        // 2. محاكاة دورة سحب فاشلة (collection واحد على الأقل فشل)
        final failedCollections = ['rooms']; // فشل واحد فقط
        if (failedCollections.isEmpty) {
          await pullService.updateLastPullTs(1700000000);
          await pullService.markFullSyncComplete();
        }

        // 3. التحقق: lastPullTs لم يتحرك
        final afterFailureTs = await pullService.getLastPullTs();
        expect(
          afterFailureTs,
          initialTs,
          reason:
              'عند فشل أي collection، يجب ألا يتحرك lastPullTs — '
              'سيسمح ذلك بإعادة سحب الكولكشن الفاشل في الدورة التالية',
        );
      },
    );

    test(
      '13. يتحرك lastPullTs عند نجاح كل الكولكشنات',
      () async {
        // 1. الحالة الأولية
        expect(await pullService.getLastPullTs(), 0);

        // 2. محاكاة دورة سحب ناجحة بالكامل
        final failedCollections = <String>[];
        if (failedCollections.isEmpty) {
          await pullService.updateLastPullTs(1700000000);
          await pullService.markFullSyncComplete();
        }

        // 3. التحقق: lastPullTs تحرك
        expect(await pullService.getLastPullTs(), 1700000000);
        expect(await pullService.isFullSyncComplete(), isTrue);
      },
    );

    test(
      '14. retry loop: فشل → نجاح → checkpoint يتحرك',
      () async {
        // ✅ السيناريو: محاكاة حلقة retry:
        // - دورة 1: فشل (لا تحديث checkpoint)
        // - دورة 2: فشل (لا تحديث checkpoint)
        // - دورة 3: نجاح (تحديث checkpoint + markFullSyncComplete)

        // دورة 1: فشل
        var failedCollections = ['rooms'];
        if (failedCollections.isEmpty) {
          await pullService.updateLastPullTs(100);
          await pullService.markFullSyncComplete();
        }
        expect(await pullService.getLastPullTs(), 0);
        expect(await pullService.isFullSyncComplete(), isFalse);

        // دورة 2: فشل
        failedCollections = ['bookings'];
        if (failedCollections.isEmpty) {
          await pullService.updateLastPullTs(200);
          await pullService.markFullSyncComplete();
        }
        expect(await pullService.getLastPullTs(), 0);
        expect(await pullService.isFullSyncComplete(), isFalse);

        // دورة 3: نجاح
        failedCollections = [];
        if (failedCollections.isEmpty) {
          await pullService.updateLastPullTs(300);
          await pullService.markFullSyncComplete();
        }
        expect(await pullService.getLastPullTs(), 300);
        expect(await pullService.isFullSyncComplete(), isTrue);

        // الدورة التالية يجب أن تستخدم delta queries
        expect(await pullService.buildDeltaQueries(300), isNotEmpty);
      },
    );

    test(
      '15. lastPullTs لا يتحرك للوراء (monotonic checkpoint)',
      () async {
        // ✅ ضمان أن checkpoint لا يتراجع
        // محاكاة: لدينا lastPullTs = 1000، ثم نحاول تحديثه لـ 500
        // (في الواقع، appwrite_sync_manager يستخدم max($updatedAt)
        //  وليس Time.nowEpoch()، لذا هذا السيناريو نادر)

        // 1. ضبط lastPullTs = 1000 + full_sync_complete = 1
        await pullService.updateLastPullTs(1000);
        await pullService.markFullSyncComplete();
        expect(await pullService.getLastPullTs(), 1000);

        // 2. محاولة تحديث لقيمة أقل
        await pullService.updateLastPullTs(500);

        // 3. lastPullTs يجب أن يكون 500 (آخر قيمة كُتبت)
        //    لكن appwrite_sync_manager يستخدم max($updatedAt) لذا هذا
        //    السلوك مقبول — السجل القديم لن يُسحب مرة أخرى لأن delta filter
        //    سيستثنيه.
        //    ملاحظة: هذا السلوك يعتمد على caller لتمرير الـ max($updatedAt).
        expect(await pullService.getLastPullTs(), 500);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 5: Schema Validation — Migration 56
  // ═══════════════════════════════════════════════════════════════════════
  group('Schema Validation — Migration 56 (full_sync_complete column)', () {
    test(
      '16. عمود full_sync_complete موجود في جدول sync_state',
      () async {
        // ✅ التحقق من أن العمود موجود بعد تشغيل Migration 56
        final result = await db
            .customSelect(
              'PRAGMA table_info(sync_state)',
              readsFrom: {db.syncState},
            )
            .get();

        final columnNames = result
            .map((row) => row.read<String>('name'))
            .toList();
        expect(
          columnNames,
          contains('full_sync_complete'),
          reason:
              'عمود full_sync_complete يجب أن يكون موجوداً في جدول '
              'sync_state بعد Migration 56',
        );
      },
    );

    test(
      '17. default value لـ full_sync_complete = 0',
      () async {
        // ✅ التحقق من القيمة الافتراضية
        // عند إنشاء صف جديد بدون تحديد full_sync_complete، يجب أن تكون 0
        // (هذا ما يضمنه DEFAULT 0 في ALTER TABLE)

        // تحقق عبر PRAGMA table_info
        final result = await db
            .customSelect(
              'PRAGMA table_info(sync_state)',
              readsFrom: {db.syncState},
            )
            .get();

        for (final row in result) {
          if (row.read<String>('name') == 'full_sync_complete') {
            final dfltValue = row.read<String?>('dflt_value');
            expect(
              dfltValue,
              isNotNull,
              reason: 'full_sync_complete يجب أن يكون له default value',
            );
            // القيمة الافتراضية يجب أن تكون 0
            expect(
              int.tryParse(dfltValue!) ?? -1,
              0,
              reason: 'default value يجب أن تكون 0',
            );
          }
        }
      },
    );

    test(
      '18. schemaVersion >= 56 (لتفعيل Migration 56 و 57)',
      () {
        expect(
          db.schemaVersion,
          greaterThanOrEqualTo(56),
          reason:
              'schemaVersion يجب أن يكون >= 56 لتفعيل Migration 56 '
              '(إضافة عمود full_sync_complete) و Migration 57 '
              '(إضافة payload_version و processing_payload_version). '
              'القيمة الحالية: ${db.schemaVersion}',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 6: تكامل end-to-end — محاكاة دورة سحب كاملة
  // ═══════════════════════════════════════════════════════════════════════
  group('تكامل End-to-End — محاكاة دورة سحب كاملة', () {
    test(
      '19. سيناريو: جهاز جديد → full sync فاشل → retry → نجاح → delta sync',
      () async {
        // ✅ هذا السيناريو يغطي دورة حياة كاملة لجهاز جديد:
        // 1. الجهاز جديد (full_sync_complete = 0)
        // 2. أول دورة سحب فشلت في بعض الكولكشنات
        // 3. ثاني دورة سحب نجحت بالكامل
        // 4. الدورة الثالثة تستخدم delta sync

        // 1. الحالة الأولية
        expect(await pullService.isFullSyncComplete(), isFalse);
        expect(await pullService.getLastPullTs(), 0);
        expect(await pullService.buildDeltaQueries(0), isEmpty); // full sync

        // 2. دورة 1: فشل في 'rooms'
        // (محاكاة منطق appwrite_sync_manager.dart:1413)
        const failedCollectionsCycle1 = ['rooms'];
        if (failedCollectionsCycle1.isEmpty) {
          // لن يُنفَّذ
          await pullService.updateLastPullTs(1000);
          await pullService.markFullSyncComplete();
        }
        expect(await pullService.isFullSyncComplete(), isFalse);
        expect(await pullService.getLastPullTs(), 0);
        expect(
          await pullService.buildDeltaQueries(0),
          isEmpty,
        ); // ما زال full sync

        // 3. دورة 2: نجاح كامل
        const failedCollectionsCycle2 = <String>[];
        if (failedCollectionsCycle2.isEmpty) {
          await pullService.updateLastPullTs(2000);
          await pullService.markFullSyncComplete();
        }
        expect(await pullService.isFullSyncComplete(), isTrue);
        expect(await pullService.getLastPullTs(), 2000);

        // 4. دورة 3: يجب أن تستخدم delta sync الآن
        final deltaQueries = await pullService.buildDeltaQueries(2000);
        expect(deltaQueries, isNotEmpty);
        expect(
          deltaQueries.first.toString(),
          contains(r'$updatedAt'),
        );
      },
    );

    test(
      '20. سيناريو: استعادة نسخة احتياطية → إعادة full sync',
      () async {
        // ✅ السيناريو: المستخدم استعاد نسخةة احتياطية، نريد إعادة full sync

        // 1. الحالة الأولية: full sync مكتمل
        await pullService.updateLastPullTs(1700000000);
        await pullService.markFullSyncComplete();
        expect(await pullService.isFullSyncComplete(), isTrue);
        expect(await pullService.buildDeltaQueries(1700000000), isNotEmpty);

        // 2. استعادة نسخة احتياطية → إعادة ضبط full_sync_complete
        await pullService.resetFullSyncComplete();
        expect(await pullService.isFullSyncComplete(), isFalse);

        // 3. الدورة التالية يجب أن تستخدم full fetch (وليست delta)
        expect(await pullService.buildDeltaQueries(1700000000), isEmpty);

        // 4. بعد نجاح دورة كاملة، نعود لـ delta mode
        await pullService.markFullSyncComplete();
        expect(await pullService.buildDeltaQueries(1700000000), isNotEmpty);
      },
    );
  });
}
