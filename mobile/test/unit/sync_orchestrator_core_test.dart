// ═══════════════════════════════════════════════════════════════
//  sync_orchestrator_core_test.dart — (2026-09-25) رفع التغطية
//
//  قبل هذا الملف: sync_orchestrator.dart تغطيته 0.0% (624 سطراً) —
//  الاختبار الوحيد (unified_sync_orchestrator_test.dart) كان smoke
//  test من سطر واحد. هذا الملف يغطي بالأرقام الحقيقية:
//    * SyncTask: canRetry + nextRetryDelay (تراجع أسي مع سقف 2^5)
//    * SyncTaskResult: مصنعا success/failure والقيم الافتراضية
//    * SyncMetricsData: معدل النجاح، متوسط المدة، نافذة 20 متحركة،
//      reset الفشل المتتالي، toJson
//    * SyncHealth.toJson / DataIntegrityCheck.toJson (عقد JSON)
//    * SyncOrchestrator على DB درِفت في الذاكرة (نمط forTesting):
//      - initialize → idle + قواطع مسجلة
//      - executeTask دون اتصال → فشل مبكر: attempts++ بلا تلويث
//        للمقاييس وبلا كتابة SharedPreferences (العودة قبل الحفظ)
//      - scheduleTask: إدراج + استبدال بنفس id (dedupe) عبر
//        getHealth().pendingTasks
//      - verifyDataIntegrity: checksum مستقر (نفس البيانات → نفس
//        md5) وrecordCount يطابق البذر
//      - pause/resume/dispose (dispose يصفّر الـ singleton)
//
//  ملاحظة صادقة (لا تخمين): مسار «الاتصال متاح» غير قابل للوصول في
//  بيئة الاختبار بلا plugin connectivity — ConnectivityService لا
//  يوفر seam عام لفرض online، لذلك تُختبر هنا المسارات الحتمية
//  offline فقط، وهي المسارات التي تحرس منطق الطوابير.
// ═══════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/circuit_breaker.dart';
import 'package:marina_hotel_mobile/services/sync_orchestrator.dart';
import 'package:marina_hotel_mobile/utils/id.dart';
import 'package:shared_preferences/shared_preferences.dart';

SyncTask _task(
  String id, {
  Duration timeout = const Duration(seconds: 5),
  bool Function()? canExecute,
  int maxRetries = 3,
}) {
  return SyncTask(
    id: id,
    name: 'task-$id',
    priority: SyncPriority.normal,
    strategy: SyncStrategy.delta,
    direction: SyncDirection.push,
    execute: () async => SyncTaskResult.success(duration: Duration.zero),
    canExecute: canExecute,
    timeout: timeout,
    maxRetries: maxRetries,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncTask', () {
    test('canRetry is true only while attempts < maxRetries', () {
      final task = _task('t1', maxRetries: 3);
      expect(task.canRetry, isTrue);
      task.attempts = 3;
      expect(task.canRetry, isFalse);
      task.attempts = 2;
      expect(task.canRetry, isTrue);
    });

    test('nextRetryDelay doubles exponentially from 5s', () {
      final task = _task('t2');
      task.attempts = 0;
      expect(task.nextRetryDelay, const Duration(seconds: 5));
      task.attempts = 1;
      expect(task.nextRetryDelay, const Duration(seconds: 10));
      task.attempts = 2;
      expect(task.nextRetryDelay, const Duration(seconds: 20));
      task.attempts = 3;
      expect(task.nextRetryDelay, const Duration(seconds: 40));
    });

    test('nextRetryDelay clamps the shift at 2^5 (160s)', () {
      final task = _task('t3');
      task.attempts = 5;
      expect(task.nextRetryDelay, const Duration(seconds: 160));
      task.attempts = 99;
      expect(task.nextRetryDelay, const Duration(seconds: 160));
    });

    test('createdAt defaults to now when not provided', () {
      final before = DateTime.now();
      final task = _task('t4');
      final after = DateTime.now();
      expect(task.createdAt.isBefore(before), isFalse);
      expect(task.createdAt.isAfter(after), isFalse);
    });
  });

  group('SyncTaskResult', () {
    test('success factory: success=true with defaults', () {
      final r = SyncTaskResult.success(duration: const Duration(seconds: 1));
      expect(r.success, isTrue);
      expect(r.recordsProcessed, 0);
      expect(r.conflicts, 0);
      expect(r.error, isNull);
      expect(r.metadata, isNull);
      expect(r.duration, const Duration(seconds: 1));
    });

    test('failure factory: carries error and keeps success=false', () {
      final r = SyncTaskResult.failure(
        error: 'boom',
        duration: const Duration(milliseconds: 7),
      );
      expect(r.success, isFalse);
      expect(r.error, 'boom');
      expect(r.duration, const Duration(milliseconds: 7));
    });
  });

  group('SyncMetricsData', () {
    test('fresh metrics are all-zero with zero successRate', () {
      final m = SyncMetricsData();
      expect(m.totalSyncs, 0);
      expect(m.successRate, 0);
      expect(m.avgDuration, Duration.zero);
      expect(m.lastSuccessfulSync, isNull);
      expect(m.lastFailedSync, isNull);
    });

    test('recordSuccess accumulates and resets consecutiveFailures', () {
      final m = SyncMetricsData();
      m.recordFailure(const Duration(seconds: 1));
      m.recordFailure(const Duration(seconds: 1));
      expect(m.consecutiveFailures, 2);
      m.recordSuccess(const Duration(seconds: 2), 5, 1);
      expect(m.consecutiveFailures, 0);
      expect(m.totalSyncs, 3);
      expect(m.successfulSyncs, 1);
      expect(m.failedSyncs, 2);
      expect(m.totalRecordsProcessed, 5);
      expect(m.totalConflicts, 1);
      expect(m.lastSuccessfulSync, isNotNull);
      expect(m.successRate, closeTo(1 / 3, 1e-9));
    });

    test('avgDuration is the mean of the rolling window', () {
      final m = SyncMetricsData();
      m.recordSuccess(const Duration(seconds: 2), 0, 0);
      m.recordSuccess(const Duration(seconds: 4), 0, 0);
      expect(m.avgDuration, const Duration(seconds: 3));
    });

    test('recentDurations keeps at most 20 entries (oldest dropped)', () {
      final m = SyncMetricsData();
      for (var i = 1; i <= 25; i++) {
        m.recordSuccess(Duration(seconds: i), 0, 0);
      }
      expect(m.recentDurations.length, 20);
      // سقطت 5 أقدم قيم (1s..5s) — الباقي 6s..25s ومتوسطه 15.5s
      expect(m.recentDurations.first, const Duration(seconds: 6));
      expect(m.recentDurations.last, const Duration(seconds: 25));
      expect(m.avgDuration, const Duration(milliseconds: 15500));
    });

    test('toJson exposes the documented contract keys', () {
      final m = SyncMetricsData();
      m.recordSuccess(const Duration(milliseconds: 250), 3, 0);
      final json = m.toJson();
      expect(json['totalSyncs'], 1);
      expect(json['successfulSyncs'], 1);
      expect(json['failedSyncs'], 0);
      expect(json['successRate'], 1.0);
      expect(json['totalRecordsProcessed'], 3);
      expect(json['avgDurationMs'], 250);
      expect(json['consecutiveFailures'], 0);
      expect(json['lastSuccessfulSync'], isNotNull);
    });
  });

  group('SyncHealth & DataIntegrityCheck JSON contracts', () {
    test(
      'SyncHealth.toJson serializes enums as names and datetimes as ISO',
      () {
        const health = SyncHealth(
          isHealthy: true,
          successRate: 0.5,
          consecutiveFailures: 0,
          avgSyncDuration: Duration(seconds: 2),
          pendingTasks: 3,
          outboxCount: 4,
          circuitStates: {'appwrite': CircuitState.closed},
        );
        final json = health.toJson();
        expect(json['isHealthy'], isTrue);
        expect(json['successRate'], 0.5);
        expect(json['avgSyncDurationMs'], 2000);
        expect(json['pendingTasks'], 3);
        expect(json['outboxCount'], 4);
        expect(json['circuitStates'], {'appwrite': 'closed'});
        expect(json['lastSuccessfulSync'], isNull);
        expect(json['lastFailedSync'], isNull);
      },
    );

    test('DataIntegrityCheck.toJson round-trips its fields', () {
      final ts = DateTime(2026, 9, 25, 10, 30);
      final check = DataIntegrityCheck(
        tableName: 'payments',
        checksum: 'abc123',
        recordCount: 42,
        timestamp: ts,
      );
      final json = check.toJson();
      expect(json['tableName'], 'payments');
      expect(json['checksum'], 'abc123');
      expect(json['recordCount'], 42);
      expect(json['timestamp'], ts.toIso8601String());
    });
  });

  group('SyncOrchestrator (drift in-memory, offline-deterministic)', () {
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      SyncOrchestrator.instance.dispose();
      await db.close();
    });

    test('initialize reaches idle and registers circuit breakers', () async {
      await SyncOrchestrator.instance.initialize(db);
      expect(SyncOrchestrator.instance.state, OrchestratorState.idle);
      expect(
        SyncOrchestrator.instance.getCircuitBreaker('appwrite').state,
        CircuitState.closed,
      );
      expect(
        SyncOrchestrator.instance.getCircuitBreaker('google_drive').state,
        CircuitState.closed,
      );
      // اسم غير مسجل → قاطع جديد افتراضي (مغلق)
      expect(
        SyncOrchestrator.instance.getCircuitBreaker('unknown').state,
        CircuitState.closed,
      );
      // إعادة initialize من حالة idle → مسموح (الحارس يرفض غير idle/disposed
      // فقط) وتكتمل مجدداً إلى idle
      await SyncOrchestrator.instance.initialize(db);
      expect(SyncOrchestrator.instance.state, OrchestratorState.idle);
    });

    test(
      'executeTask offline fails fast: attempts++ but metrics untouched',
      () async {
        await SyncOrchestrator.instance.initialize(db);
        final task = _task('offline_1');
        final result = await SyncOrchestrator.instance.executeTask(task);

        expect(result.success, isFalse);
        expect(result.error, 'لا يوجد اتصال بالإنترنت');
        expect(task.attempts, 1);
        expect(task.lastAttempt, isNotNull);
        // العودة المبكرة قبل تسجيل المقاييس → لا تلويث
        expect(SyncOrchestrator.instance.metrics.totalSyncs, 0);
        // والعودة قبل الحفظ → لا مفتاح مقاييس في SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('sync_orchestrator_metrics'), isNull);
      },
    );

    test(
      'offline gate short-circuits before canExecute is consulted',
      () async {
        await SyncOrchestrator.instance.initialize(db);
        var gateConsulted = false;
        final task = _task(
          'gated_1',
          canExecute: () {
            gateConsulted = true;
            return false;
          },
        );
        final result = await SyncOrchestrator.instance.executeTask(task);
        expect(result.success, isFalse);
        expect(gateConsulted, isFalse, reason: 'offline gate runs first');
      },
    );

    test(
      'scheduleTask dedupes by id and getHealth reports pendingTasks',
      () async {
        await SyncOrchestrator.instance.initialize(db);
        await SyncOrchestrator.instance.scheduleTask(_task('dup_1'));
        await SyncOrchestrator.instance.scheduleTask(_task('dup_1'));

        final health = await SyncOrchestrator.instance.getHealth();
        expect(health.pendingTasks, 1, reason: 'same id replaces, not appends');
        expect(health.outboxCount, 0);
        expect(health.isHealthy, isTrue);
        expect(health.successRate, 0);
        expect(health.circuitStates['appwrite'], CircuitState.closed);
        expect(health.toJson()['circuitStates']['appwrite'], 'closed');
      },
    );

    test(
      'verifyDataIntegrity returns stable checksums and real counts',
      () async {
        await SyncOrchestrator.instance.initialize(db);

        // بذر غرفة واحدة حتى يكون recordCount>0 وليس كل الجداول فارغة
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion(
                localUuid: Value(IdGen.uuid()),
                roomNumber: const Value('101'),
                type: const Value('single'),
                price: const Value(200.0),
                status: const Value('متاحة'),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
              ),
            );

        final first = await SyncOrchestrator.instance.verifyDataIntegrity();
        final second = await SyncOrchestrator.instance.verifyDataIntegrity();

        final roomCheck = first.where((c) => c.tableName == 'rooms').toList();
        expect(roomCheck, hasLength(1), reason: 'rooms table audited');
        expect(roomCheck.first.recordCount, 1);
        expect(roomCheck.first.checksum, isNotEmpty);

        // نفس البيانات → نفس الـ checksum (استقرار بصمة السلامة)
        final secondRoom = second.firstWhere((c) => c.tableName == 'rooms');
        expect(secondRoom.checksum, roomCheck.first.checksum);
        expect(secondRoom.recordCount, 1);

        // بقية الجداول المدققة تُفحص على DB سليمة بلا أخطاء تُسقطها
        expect(
          second.map((c) => c.tableName),
          containsAll(<String>['payments', 'expenses']),
        );
      },
    );

    test(
      'pause/resume cycle: idle → paused → idle, double-pause is no-op',
      () async {
        await SyncOrchestrator.instance.initialize(db);

        SyncOrchestrator.instance.pause();
        expect(SyncOrchestrator.instance.state, OrchestratorState.paused);
        SyncOrchestrator.instance.resume();
        // resume يطلق _processTasks كـ unawaited — offline يخرج فوراً ويعيد idle
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(SyncOrchestrator.instance.state, OrchestratorState.idle);

        // pause من paused (غير syncing/idle) → no-op
        SyncOrchestrator.instance.pause();
        SyncOrchestrator.instance.pause();
        expect(SyncOrchestrator.instance.state, OrchestratorState.paused);
      },
    );

    test('dispose sets disposed state and resets the singleton', () async {
      final orchestrator = SyncOrchestrator.instance;
      await orchestrator.initialize(db);
      orchestrator.dispose();
      expect(orchestrator.state, OrchestratorState.disposed);
      // singleton أُصفّر → الوصول التالي ينشئ نسخة جديدة عذراء
      expect(SyncOrchestrator.instance, isNot(same(orchestrator)));
      expect(SyncOrchestrator.instance.state, OrchestratorState.idle);
    });
  });
}
