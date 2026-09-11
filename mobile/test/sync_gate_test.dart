// اختبارات تحصينات P0 (تقرير 2026-09-11) لبوابة المزامنة:
// 1) مهلة العمليات المتعثرة: تحرير تلقائي (watchdog + نقطة tryEnter)
//    مع تذكرة ملكية تمنع المهمة القديمة المتأخرة من سرقة الحيازة الجديدة.
// 2) تسجيل العمليات المرفوضة: عدّاد + سجل محدود + رد نداء — يعمل دائماً.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync/sync_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SyncGate.instance
      ..exit()
      ..resetStats()
      ..stuckTimeout = const Duration(minutes: 5);
    SyncGate.instance.onRejected = null;
  });

  tearDown(() {
    SyncGate.instance
      ..exit()
      ..resetStats()
      ..stuckTimeout = const Duration(minutes: 5);
    SyncGate.instance.onRejected = null;
  });

  group('P0-2: تسجيل العمليات المرفوضة', () {
    test('رفض الدخول يُسجّل في العدّاد والسجل وآخر رفض', () {
      final gate = SyncGate.instance;
      expect(gate.tryEnter(operation: 'pull', source: 'timer'), isTrue);
      expect(
        gate.tryEnter(operation: 'push', source: 'dashboard_button'),
        isFalse,
      );

      expect(gate.rejectedCount, 1);
      final last = gate.lastRejection!;
      expect(last.operation, 'push');
      expect(last.source, 'dashboard_button');
      expect(last.busyOperation, 'pull');
      expect(last.busySource, 'timer');
      expect(gate.rejectionLog.length, 1);

      gate.exit();
      // الخروج لا يمسح الإحصائيات — التشخيص يحتاجها
      expect(gate.rejectedCount, 1);
      expect(gate.rejectionLog.length, 1);
    });

    test('رد النداء onRejected يُستدعى عند كل رفض', () {
      final gate = SyncGate.instance;
      final rejections = <SyncGateRejection>[];
      gate.onRejected = rejections.add;

      gate.tryEnter(operation: 'pull', source: 'timer');
      gate.tryEnter(operation: 'push', source: 'a');
      gate.tryEnter(operation: 'pull', source: 'b');

      expect(rejections.length, 2);
      expect(rejections[0].operation, 'push');
      expect(rejections[1].source, 'b');
    });

    test('سجل الرفض محدود بـ100 عملية بينما العدّاد يتراكم', () {
      final gate = SyncGate.instance;
      gate.tryEnter(operation: 'pull', source: 'timer');
      for (var i = 0; i < 130; i++) {
        expect(gate.tryEnter(operation: 'push', source: 'spam$i'), isFalse);
      }
      expect(gate.rejectedCount, 130);
      expect(gate.rejectionLog.length, 100);
      // الأقدم يُحذف أولاً — أول عنصر في السجل هو المحاولة رقم 31
      expect(gate.rejectionLog.first.source, 'spam30');
      expect(gate.rejectionLog.last.source, 'spam129');
    });

    test('resetStats يصفّر العدادات والسجل دون مس الحيازة', () {
      final gate = SyncGate.instance;
      gate.tryEnter(operation: 'pull', source: 'timer');
      gate.tryEnter(operation: 'push', source: 'x');
      gate.resetStats();
      expect(gate.rejectedCount, 0);
      expect(gate.lastRejection, isNull);
      expect(gate.rejectionLog, isEmpty);
      expect(gate.isBusy, isTrue, reason: 'التصفير لا يمس الحيازة');
    });

    test('stats تتضمن المفاتيح التشخيصية المتوقعة', () {
      final gate = SyncGate.instance;
      gate.tryEnter(operation: 'pull', source: 'timer');
      gate.tryEnter(operation: 'push', source: 'x');
      final stats = gate.stats;
      expect(stats['isBusy'], isTrue);
      expect(stats['operation'], 'pull');
      expect(stats['rejectedCount'], 1);
      expect(stats['stuckReleases'], 0);
      expect(stats['stuckTimeoutSeconds'], 300);
      expect(stats['elapsedMs'], isNotNull);
      expect(stats['lastRejection'], contains('push'));
    });
  });

  group('P0-1: مهلة العمليات المتعثرة', () {
    test('releaseIfStuck بمهلة صريحة: لا يحرر قبلها ويحرر بعدها', () async {
      final gate = SyncGate.instance;
      // الافتراضي 5 دقائق — الـ watchdog لن يتدخل خلال الاختبار
      gate.tryEnter(operation: 'pull', source: 'timer');

      // مهلة صريحة أطول من المنقضي (0s) → لا تحرير
      expect(
        gate.releaseIfStuck(timeout: const Duration(minutes: 10)),
        isFalse,
      );
      expect(gate.isBusy, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      // مهلة صريحة أقصر من المنقضي → تحرير فوري
      expect(
        gate.releaseIfStuck(timeout: const Duration(milliseconds: 50)),
        isTrue,
      );
      expect(gate.isBusy, isFalse);
      expect(gate.stuckReleases, 1);
    });

    test('المؤقت الداخلي يحرر البوابة تلقائياً عند التعثر', () async {
      final gate = SyncGate.instance;
      gate.stuckTimeout = const Duration(milliseconds: 80);
      gate.tryEnter(operation: 'auto_sync', source: 'timer');

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(gate.isBusy, isFalse, reason: 'watchdog يجب أن يحرر تلقائياً');
      expect(gate.stuckReleases, 1);
    });

    test('tryEnter يحرر العملية المتعثرة ويسمح بالدخول الجديد', () async {
      final gate = SyncGate.instance;
      gate.stuckTimeout = const Duration(milliseconds: 80);
      gate.tryEnter(operation: 'pull', source: 'old');

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(gate.tryEnter(operation: 'push', source: 'new'), isTrue);
      expect(gate.state.operation, 'push');
      expect(gate.state.source, 'new');
      expect(gate.stuckReleases, 1);
    });

    test(
      'تذكرة الملكية: المهمة القديمة المتأخرة لا تسرق حيازة الجديدة',
      () async {
        final gate = SyncGate.instance;
        gate.stuckTimeout = const Duration(milliseconds: 80);
        final releaseOldTask = Completer<void>();

        final oldFuture = gate.runGuarded<void>(
          operation: 'pull',
          source: 'old',
          task: () => releaseOldTask.future,
        );

        // المهمة القديمة تعلق → watchdog يحرر البوابة بعد المهلة
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(gate.isBusy, isFalse);

        // عملية جديدة تدخل بنجاح
        expect(gate.tryEnter(operation: 'push', source: 'new'), isTrue);
        final newTicket = gate.state.entryId;
        expect(newTicket, isNotNull);

        // المهمة القديمة تنتهي الآن — يجب ألا تحرر حيازة الجديدة
        releaseOldTask.complete();
        await oldFuture;
        expect(
          gate.isBusy,
          isTrue,
          reason: 'stale exit يجب أن يُتجاهل',
        );
        expect(gate.state.entryId, newTicket);
        expect(gate.state.operation, 'push');

        gate.exit();
        expect(gate.isBusy, isFalse);
      },
    );

    test('releaseIfStuck على بوابة خاملة يرجع false بأمان', () {
      final gate = SyncGate.instance;
      expect(gate.releaseIfStuck(), isFalse);
      expect(gate.isBusy, isFalse);
    });
  });

  group('runGuarded/runGuardedVoid — السلوك الأساسي محفوظ', () {
    test('يرجع null عند انشغال البوابة', () async {
      final gate = SyncGate.instance;
      gate.tryEnter(operation: 'pull', source: 'timer');
      final result = await gate.runGuarded<String>(
        operation: 'push',
        source: 'btn',
        task: () async => 'x',
      );
      expect(result, isNull);
    });

    test('يرجع النتيجة ويحرر البوابة', () async {
      final gate = SyncGate.instance;
      final result = await gate.runGuarded<String>(
        operation: 'push',
        source: 'btn',
        task: () async => 'done',
      );
      expect(result, 'done');
      expect(gate.isBusy, isFalse);
    });

    test('يحرر البوابة حتى عند رمي استثناء', () async {
      final gate = SyncGate.instance;
      await expectLater(
        gate.runGuarded<void>(
          operation: 'pull',
          source: 'btn',
          task: () async => throw StateError('boom'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(gate.isBusy, isFalse);
    });

    test('runGuardedVoid يرجع false عند الرفض وtrue عند التنفيذ', () async {
      final gate = SyncGate.instance;
      gate.tryEnter(operation: 'pull', source: 'timer');
      expect(
        await gate.runGuardedVoid(
          operation: 'push',
          source: 'btn',
          task: () async {},
        ),
        isFalse,
      );
      gate.exit();
      expect(
        await gate.runGuardedVoid(
          operation: 'push',
          source: 'btn',
          task: () async {},
        ),
        isTrue,
      );
      expect(gate.isBusy, isFalse);
    });

    test('entryId يتزايد مع كل دخول والحالة الخاملة بلا تذكرة', () async {
      final gate = SyncGate.instance;
      expect(gate.state.entryId, isNull);

      gate.tryEnter(operation: 'a', source: 'x');
      final t1 = gate.state.entryId!;
      gate.exit();

      gate.tryEnter(operation: 'b', source: 'y');
      final t2 = gate.state.entryId!;
      gate.exit();

      expect(t2, greaterThan(t1));
      expect(gate.state.entryId, isNull);
    });
  });

  group('الدمج مع 4bc479d1: عدّاد الرفض داخل الحالة + isStuck', () {
    test('state.rejectedCount يتراكم خلال الحيازة ويُصفَّر عند دورة جديدة', () {
      final gate = SyncGate.instance;
      gate.tryEnter(operation: 'pull', source: 'timer');
      gate.tryEnter(operation: 'push', source: 'a');
      gate.tryEnter(operation: 'push', source: 'b');
      expect(gate.state.rejectedCount, 2);

      gate.exit();
      expect(gate.state.rejectedCount, 0);

      // دورة حيازة جديدة تبدأ عدّادها من الصفر
      gate.tryEnter(operation: 'pull', source: 'timer2');
      expect(gate.state.rejectedCount, 0);
      gate.exit();
      // بينما العدّاد التراكمي على البوابة يبقى
      expect(gate.rejectedCount, 2);
    });

    test('isStuck/isStuckAt تعكس التعثر حسب العتبة', () async {
      final gate = SyncGate.instance;
      gate.tryEnter(operation: 'pull', source: 'timer');

      expect(gate.state.isStuck, isFalse);
      expect(gate.state.isStuckAt(const Duration(minutes: 10)), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(gate.state.isStuckAt(const Duration(milliseconds: 10)), isTrue);
      expect(gate.state.isStuck, isFalse, reason: 'العتبة الافتراضية 5 دقائق');

      gate.exit();
      expect(gate.state.isStuck, isFalse);
    });
  });
}
