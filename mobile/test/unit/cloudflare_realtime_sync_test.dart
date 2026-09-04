// ═══════════════════════════════════════════════════════════════
//  cloudflare_realtime_sync_test.dart — plan phase 3.4
//
//  تغطية منطق Realtime العميلي بلا شبكة (FakeAsync يتحكم بالمؤقتات):
//   - تحليل الرسائل (tryParse) وفلتر الصدى (echo filter)
//   - طابور الأحداث: debounce يدمج الدفعات، cooldown يقيّد المعدل،
//     حارس in-flight + trailing queue، إعادة المتابعة عند الفشل
//   - تسلسل backoff الأُسّي وسقفه
//   - دورة حياة الشارة (resetRemoteChangesFlag / stop)
// ═══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/cloudflare_realtime_sync.dart';

void main() {
  tearDown(() {
    CloudflareRealtimeSync().resetForTest();
  });

  CloudflareRealtimeMessage change({
    required String entity,
    String? deviceId,
    String operation = 'update',
  }) {
    return CloudflareRealtimeMessage(
      type: 'change',
      entity: entity,
      entityId: '$entity-1',
      operation: operation,
      deviceId: deviceId,
      timestamp: 1700000000,
    );
  }

  group('CloudflareRealtimeMessage.tryParse', () {
    test('parses a valid change message', () {
      const raw =
          '{"type":"change","entity":"rooms","entityId":"r1",'
          '"operation":"update","deviceId":"device-B","timestamp":123}';
      final msg = CloudflareRealtimeMessage.tryParse(raw);
      expect(msg, isNotNull);
      expect(msg!.type, 'change');
      expect(msg.entity, 'rooms');
      expect(msg.entityId, 'r1');
      expect(msg.operation, 'update');
      expect(msg.deviceId, 'device-B');
      expect(msg.timestamp, 123);
    });

    test('tolerates missing optional fields', () {
      const raw = '{"type":"presence","entity":"*"}';
      final msg = CloudflareRealtimeMessage.tryParse(raw);
      expect(msg, isNotNull);
      expect(msg!.entityId, '');
      expect(msg.deviceId, isNull);
      expect(msg.timestamp, 0);
    });

    test('rejects malformed JSON, non-strings, and missing type/entity', () {
      expect(CloudflareRealtimeMessage.tryParse('{not json'), isNull);
      expect(CloudflareRealtimeMessage.tryParse('42'), isNull);
      expect(CloudflareRealtimeMessage.tryParse(null), isNull);
      expect(CloudflareRealtimeMessage.tryParse([1, 2]), isNull);
      expect(CloudflareRealtimeMessage.tryParse('{"entity":"rooms"}'), isNull);
      expect(
        CloudflareRealtimeMessage.tryParse('{"type":"change"}'),
        isNull,
      );
    });
  });

  group('computeBackoffDelay', () {
    test('doubles exponentially from 1s and caps at 60s', () {
      expect(
        CloudflareRealtimeSync.computeBackoffDelay(0),
        const Duration(seconds: 1),
      );
      expect(
        CloudflareRealtimeSync.computeBackoffDelay(1),
        const Duration(seconds: 2),
      );
      expect(
        CloudflareRealtimeSync.computeBackoffDelay(2),
        const Duration(seconds: 4),
      );
      expect(
        CloudflareRealtimeSync.computeBackoffDelay(5),
        const Duration(seconds: 32),
      );
      expect(
        CloudflareRealtimeSync.computeBackoffDelay(6),
        const Duration(seconds: 60),
      ); // cap
      expect(
        CloudflareRealtimeSync.computeBackoffDelay(10),
        const Duration(seconds: 60),
      ); // cap
      expect(
        CloudflareRealtimeSync.computeBackoffDelay(-3),
        const Duration(seconds: 1),
      ); // clamped
    });
  });

  group('event queue (no network)', () {
    test('foreign change event fires exactly one debounced pull per burst', () {
      fakeAsync((async) {
        final realtime = CloudflareRealtimeSync();
        realtime.resetForTest();
        int pulls = 0;
        realtime.setSyncTrigger(() async {
          pulls++;
          return true;
        });

        realtime.handleIncomingMessage(
          change(entity: 'rooms', deviceId: 'device-B'),
        );
        expect(pulls, 0); // debounce window still open
        async.elapse(const Duration(milliseconds: 600));
        expect(pulls, 1);
      });
    });

    test('a burst of N events merges into a single pull', () {
      fakeAsync((async) {
        final realtime = CloudflareRealtimeSync();
        realtime.resetForTest();
        int pulls = 0;
        realtime.setSyncTrigger(() async {
          pulls++;
          return true;
        });

        for (int i = 0; i < 10; i++) {
          realtime.handleIncomingMessage(
            change(entity: 'bookings', deviceId: 'device-B'),
          );
        }
        async.elapse(const Duration(seconds: 1));
        expect(pulls, 1); // 10 events = 1 cycle (debounce merge)
      });
    });

    test('own-device echo is ignored (no pull, no badge)', () {
      fakeAsync((async) {
        final realtime = CloudflareRealtimeSync();
        realtime.resetForTest();
        realtime.initialize(deviceId: 'my-device');
        int pulls = 0;
        realtime.setSyncTrigger(() async {
          pulls++;
          return true;
        });

        realtime.handleIncomingMessage(
          change(entity: 'rooms', deviceId: 'my-device'),
        );
        async.elapse(const Duration(seconds: 1));
        expect(pulls, 0);
        expect(realtime.pendingRemoteChangesCount.value, 0);
        expect(realtime.hasRemoteChanges.value, false);
      });
    });

    test('presence/lock/unlock never trigger a pull', () {
      fakeAsync((async) {
        final realtime = CloudflareRealtimeSync();
        realtime.resetForTest();
        int pulls = 0;
        realtime.setSyncTrigger(() async {
          pulls++;
          return true;
        });

        realtime.handleIncomingMessage(
          const CloudflareRealtimeMessage(
            type: 'presence',
            entity: '*',
            entityId: '',
            deviceId: 'device-B',
            timestamp: 1,
          ),
        );
        realtime.handleIncomingMessage(
          const CloudflareRealtimeMessage(
            type: 'lock',
            entity: 'rooms',
            entityId: 'r1',
            deviceId: 'device-B',
            timestamp: 2,
          ),
        );
        async.elapse(const Duration(seconds: 2));
        expect(pulls, 0);
      });
    });

    test('cooldown: a second burst inside the window trails, not floods', () {
      fakeAsync((async) {
        final realtime = CloudflareRealtimeSync();
        realtime.resetForTest();
        int pulls = 0;
        realtime.setSyncTrigger(() async {
          pulls++;
          return true;
        });

        realtime.handleIncomingMessage(
          change(entity: 'rooms', deviceId: 'device-B'),
        );
        async.elapse(const Duration(milliseconds: 600));
        expect(pulls, 1);

        // داخل نافذة cooldown (15s) — يُجدول trailing ولا يُسحب فوراً
        realtime.handleIncomingMessage(
          change(entity: 'rooms', deviceId: 'device-B'),
        );
        async.elapse(const Duration(seconds: 1));
        expect(pulls, 1);

        // انقضاء cooldown → trailing pull واحد
        async.elapse(const Duration(seconds: 15));
        expect(pulls, 2);
      });
    });

    test('in-flight guard: events during a slow pull queue one trailing', () {
      fakeAsync((async) {
        final realtime = CloudflareRealtimeSync();
        realtime.resetForTest();
        final completer = Completer<bool>();
        int started = 0;
        realtime.setSyncTrigger(() {
          started++;
          return completer.future;
        });

        realtime.handleIncomingMessage(
          change(entity: 'rooms', deviceId: 'device-B'),
        );
        async.elapse(const Duration(milliseconds: 600));
        expect(started, 1);

        // حدث أثناء السحب الطويل → طابور trailing فقط
        realtime.handleIncomingMessage(
          change(entity: 'payments', deviceId: 'device-B'),
        );
        async.elapse(const Duration(seconds: 1));
        expect(started, 1); // لا سحوبات متزامنة

        completer.complete(true);
        async.elapse(const Duration(seconds: 16));
        expect(started, 2); // trailing بعد انقضاء cooldown
      });
    });

    test('failed pull (false) schedules a follow-up instead of swallowing', () {
      fakeAsync((async) {
        final realtime = CloudflareRealtimeSync();
        realtime.resetForTest();
        final results = <bool>[false, true];
        int pulls = 0;
        realtime.setSyncTrigger(() async {
          pulls++;
          return results[pulls - 1];
        });

        realtime.handleIncomingMessage(
          change(entity: 'rooms', deviceId: 'device-B'),
        );
        async.elapse(const Duration(milliseconds: 600));
        expect(pulls, 1);

        // فشل → متابعة بعد cooldown
        async.elapse(const Duration(seconds: 16));
        expect(pulls, 2);
      });
    });

    test('successful pull consumes the UI badge (perf contract)', () {
      fakeAsync((async) {
        final realtime = CloudflareRealtimeSync();
        realtime.resetForTest();
        realtime.setSyncTrigger(() async => true);

        realtime.handleIncomingMessage(
          change(entity: 'rooms', deviceId: 'device-B'),
        );
        expect(realtime.hasRemoteChanges.value, true);
        expect(realtime.pendingRemoteChangesCount.value, 1);

        async.elapse(const Duration(milliseconds: 600));
        expect(realtime.hasRemoteChanges.value, false);
        expect(realtime.pendingRemoteChangesCount.value, 0);
      });
    });
  });

  group('lifecycle', () {
    test('stop() clears pending debounce and resets the badge', () {
      fakeAsync((async) {
        final realtime = CloudflareRealtimeSync();
        realtime.resetForTest();
        int pulls = 0;
        realtime.setSyncTrigger(() async {
          pulls++;
          return true;
        });

        realtime.handleIncomingMessage(
          change(entity: 'rooms', deviceId: 'device-B'),
        );
        expect(realtime.hasRemoteChanges.value, true);
        realtime.stop();

        async.elapse(const Duration(seconds: 2));
        expect(pulls, 0); // debounce cancelled — لا سحب بعد الإيقاف
        expect(realtime.hasRemoteChanges.value, false);
        expect(realtime.pendingRemoteChangesCount.value, 0);
        expect(realtime.isListening, false);
      });
    });

    test(
      'manual resetRemoteChangesFlag clears badge without touching pull',
      () {
        final realtime = CloudflareRealtimeSync();
        realtime.resetForTest();
        realtime.handleIncomingMessage(
          change(entity: 'rooms', deviceId: 'device-B'),
        );
        expect(realtime.pendingRemoteChangesCount.value, 1);
        realtime.resetRemoteChangesFlag();
        expect(realtime.pendingRemoteChangesCount.value, 0);
        expect(realtime.hasRemoteChanges.value, false);
      },
    );

    test('start without configuration schedules bounded retries, no crash', () {
      fakeAsync((async) {
        final realtime = CloudflareRealtimeSync();
        realtime.resetForTest();
        realtime.configure(
          baseUrl: 'https://worker.example.com',
          tokenProvider: () async => null, // لم يكتمل login بعد
        );

        realtime.start();
        // 6 محاولات بأُسّية ثم استسلام — لا استثناءات ولا شبكة
        async.elapse(const Duration(minutes: 5));
        expect(realtime.isListening, true);
        expect(realtime.isConnected, false);
      });
    });
  });
}
