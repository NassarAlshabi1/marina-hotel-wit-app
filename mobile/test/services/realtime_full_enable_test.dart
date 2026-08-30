// ============================================================================
//  اختبارات تفعيل Realtime الكامل (2026-08-31) — طبقة AppwriteRealtimeSync
// ============================================================================
//  ما تثبته بالتنفيذ (لا بالمحاكاة):
//   R1  قرار الوضع الافتراضي: WebSocket مفعّل افتراضياً (كان false) —
//       وأثر المفاتيح الثلاثة (sync الرئيسي / realtime الرئيسي / WS).
//   R2  حدث من نفس الجهاز → يُتجاهل تماماً (لا سحب، لا شارة).
//   R3  حدث غير بيانات (permissions.update) → يُتجاهل.
//   R4  حدث بيانات من جهاز آخر → بعد الدّيبونس: شارة UI + **سحب فعلي**
//       (trigger حقن) — وعند نجاحه تُصفَّر الشارات (السحب طبّق التغييرات).
//   R5  تهيئة السحب (cooldown): عاصفة أحداث داخل التهيئة → سحب واحد
//       يغطي المتراكم، ولا سحب ثانٍ إلا بعد انتهاء التهيئة (trailing).
//   R6  حدث أثناء دورة جارية (in-flight) → يُطابَر ويُنفَّذ متابعة بعد
//       انتهاء الدورة — لا يُفقد أي تغيير.
//   R7  فشل/تخطّي السحب (trigger يعيد false) → محاولة متابعة مجدولة —
//       التغييرات لا تبقى معلقة بلا محاولة.
//   R8  stop() الإرادي: لا سحب بعد التوقف، وensureStarted يحترمه؛
//       resetForTesting يعيد الحالة للحياد بين الاختبارات.
//   R9  وضع fallback (WS معطّل): علامة UI كل 30 ثانية وسحب فعلي خفيف
//       عند بلوغ الفاصل المُعدَّل للاختبار.
//
//  التشغيل:
//    flutter test test/services/realtime_full_enable_test.dart
// ============================================================================

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_realtime_sync.dart';
import 'package:marina_hotel_mobile/services/sync_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final realtime = AppwriteRealtimeSync();

  setUp(() {
    realtime.resetForTesting();
  });

  group('R1: قرار الوضع — WebSocket مفعّل افتراضياً', () {
    test('كل المفاتيح غائبة → websocket (التفعيل الكامل افتراضياً)', () {
      expect(
        AppwriteRealtimeSync.resolveRealtimeMode(
          appwriteSyncEnabled: null,
          realtimeSyncEnabled: null,
          wsEnabled: null,
        ),
        RealtimeMode.websocket,
      );
    });

    test('ws=false صراحة → fallback (سحب خفيف دوري بلا WebSocket)', () {
      expect(
        AppwriteRealtimeSync.resolveRealtimeMode(
          appwriteSyncEnabled: null,
          realtimeSyncEnabled: null,
          wsEnabled: false,
        ),
        RealtimeMode.fallback,
      );
    });

    test('المفتاح المرئي realtime=false → disabled', () {
      expect(
        AppwriteRealtimeSync.resolveRealtimeMode(
          appwriteSyncEnabled: null,
          realtimeSyncEnabled: false,
          wsEnabled: null,
        ),
        RealtimeMode.disabled,
      );
    });

    test('المفتاح الرئيسي sync=false → disabled (أعلى في السلسلة)', () {
      expect(
        AppwriteRealtimeSync.resolveRealtimeMode(
          appwriteSyncEnabled: false,
          realtimeSyncEnabled: true,
          wsEnabled: true,
        ),
        RealtimeMode.disabled,
      );
    });
  });

  group('R2/R3: تصفية الأحداث', () {
    test('R2: حدث من نفس الجهاز → لا سحب ولا شارة', () {
      realtime.currentDeviceIdForTesting = 'device-A';
      var triggerCalls = 0;
      realtime.setSyncTrigger(() async {
        triggerCalls++;
        return true;
      });

      realtime.handleRemoteDataChange(
        events: ['databases.main.collections.bookings.documents.create'],
        payload: {
          'device_id': 'device-A', // نفس الجهاز الحالي
          r'$updatedAt': '2026-08-31T10:00:00.000Z',
        },
      );

      expect(realtime.hasRemoteChanges.value, isFalse);
      expect(realtime.pendingRemoteChangesCount.value, 0);
      expect(triggerCalls, 0);
    });

    test('R3: حدث غير بيانات (permissions.update) → يُتجاهل', () {
      realtime.currentDeviceIdForTesting = 'device-A';
      var triggerCalls = 0;
      realtime.setSyncTrigger(() async {
        triggerCalls++;
        return true;
      });

      realtime.handleRemoteDataChange(
        events: [
          'databases.main.collections.bookings.documents.permissions.update',
        ],
        payload: {'device_id': 'device-B'},
      );

      expect(realtime.hasRemoteChanges.value, isFalse);
      expect(triggerCalls, 0);
    });
  });

  group('R4: حدث بيانات من جهاز آخر → سحب فعلي', () {
    test('الديبونس يجمّع ثم يُطلق سحباً واحداً ويصفّر الشارات عند النجاح', () {
      fakeAsync((async) {
        realtime.resetForTesting();
        realtime.currentDeviceIdForTesting = 'device-A';
        realtime.debugEventDebounce = const Duration(milliseconds: 10);
        var triggerCalls = 0;
        realtime.setSyncTrigger(() async {
          triggerCalls++;
          return true;
        });

        realtime.handleRemoteDataChange(
          events: ['databases.main.collections.payments.documents.create'],
          payload: {
            'device_id': 'device-B',
            r'$updatedAt': '2026-08-31T10:00:00.000Z',
          },
        );

        // قبل انتهاء الديبونس: لا شيء بعد.
        expect(triggerCalls, 0);
        expect(realtime.hasRemoteChanges.value, isFalse);

        async.elapse(const Duration(milliseconds: 30));
        async.flushMicrotasks();

        // بعد الديبونس: شارة UI + سحب فعلي واحد.
        expect(
          triggerCalls,
          1,
          reason: 'حدث Realtime يجب أن يُطلق سحباً فعلياً فورياً',
        );
        expect(
          realtime.hasRemoteChanges.value,
          isFalse,
          reason: 'السحب نجح → الشارات صُفّرت (التغييرات طُبّقت)',
        );
        expect(realtime.pendingRemoteChangesCount.value, 0);
      });
    });

    test('آخر طابع خادم يتتبع \$updatedAt للحدث', () {
      realtime.resetForTesting();
      realtime.currentDeviceIdForTesting = 'device-A';
      realtime.handleRemoteDataChange(
        events: ['databases.main.collections.rooms.documents.update'],
        payload: {
          'device_id': 'device-B',
          r'$updatedAt': '2026-08-31T11:30:00.000Z',
        },
      );
      expect(realtime.lastKnownServerUpdate, isNotNull);
      expect(
        realtime.lastKnownServerUpdate!.toUtc().toIso8601String(),
        startsWith('2026-08-31T11:30:00'),
      );
    });
  });

  group('R5: تهيئة السحب (cooldown) ضد العواصف', () {
    test('عاصفة داخل التهيئة → سحب واحد عند انتهاء التهيئة يغطي المتراكم', () {
      fakeAsync((async) {
        realtime.resetForTesting();
        realtime.currentDeviceIdForTesting = 'device-A';
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        realtime.debugPullCooldown = const Duration(milliseconds: 100);

        var triggerCalls = 0;
        realtime.setSyncTrigger(() async {
          triggerCalls++;
          return true;
        });

        // سحب أول فوري.
        realtime.handleRemoteDataChange(
          events: ['databases.main.collections.bookings.documents.create'],
          payload: {'device_id': 'device-B'},
        );
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(triggerCalls, 1);

        // عاصفة: 5 أحداث داخل فترة التهيئة — لا سحب فوري إضافي.
        for (var i = 0; i < 5; i++) {
          realtime.handleRemoteDataChange(
            events: ['databases.main.collections.bookings.documents.update'],
            payload: {'device_id': 'device-B'},
          );
          async.elapse(const Duration(milliseconds: 10));
          async.flushMicrotasks();
          expect(
            triggerCalls,
            1,
            reason: 'داخل التهيئة: لا سحب جديد قبل بلوغ الفاصل',
          );
        }

        // انتهاء التهيئة → السحب المؤجل (trailing) يغطي كل المتراكم مرة واحدة.
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        expect(
          triggerCalls,
          2,
          reason: 'سحب trailing واحد بعد التهيئة — السحب delta يغطي الكل',
        );
      });
    });
  });

  group('R6/R7: الحماية من الفقد (in-flight + تخطّي)', () {
    test('R6: حدث أثناء دورة جارية → متابعة بعد انتهائها مباشرة', () {
      fakeAsync((async) {
        realtime.resetForTesting();
        realtime.currentDeviceIdForTesting = 'device-A';
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        realtime.debugPullCooldown = Duration.zero;

        final firstGate = Completer<bool>();
        var triggerCalls = 0;
        realtime.setSyncTrigger(() {
          triggerCalls++;
          if (triggerCalls == 1) {
            // دورة أولى طويلة (شبكة بطيئة محاكاةً).
            return firstGate.future;
          }
          return Future<bool>.value(true);
        });

        realtime.handleRemoteDataChange(
          events: ['databases.main.collections.bookings.documents.create'],
          payload: {'device_id': 'device-B'},
        );
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(triggerCalls, 1);
        expect(realtime.triggerInFlightForTesting, isTrue);

        // حدث جديد أثناء الدورة الجارية → يُطابَر فقط.
        realtime.handleRemoteDataChange(
          events: ['databases.main.collections.debts.documents.create'],
          payload: {'device_id': 'device-B'},
        );
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(triggerCalls, 1, reason: 'لا سحب متوازٍ — يُطابَر للبحث');
        expect(realtime.pendingRemoteChangesCount.value, 2);

        // انتهاء الدورة الأولى → المتابعة المطابَرة تُنفَّذ فوراً.
        firstGate.complete(true);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 5));
        async.flushMicrotasks();
        expect(
          triggerCalls,
          2,
          reason: 'التغيير الذي وصل أثناء الدورة يُسحب بعد انتهائها',
        );
      });
    });

    test('R7: trigger يعيد false (سحب تخطّى) → محاولة متابعة مجدولة', () {
      fakeAsync((async) {
        realtime.resetForTesting();
        realtime.currentDeviceIdForTesting = 'device-A';
        realtime.debugEventDebounce = const Duration(milliseconds: 5);
        realtime.debugPullCooldown = const Duration(milliseconds: 50);

        var calls = 0;
        final results = <bool>[];
        realtime.setSyncTrigger(() async {
          calls++;
          results.add(calls == 1 ? false : true); // الأولى: السحب تخطّى
          return results.last;
        });

        realtime.handleRemoteDataChange(
          events: ['databases.main.collections.bookings.documents.create'],
          payload: {'device_id': 'device-B'},
        );
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(calls, 1);
        // السحب تخطّى → الشارة تبقى مرفوعة (التغييرات لم تُطبّق).
        expect(realtime.hasRemoteChanges.value, isTrue);

        // المتابعة المُجدولة تنطلق بعد التهيئة.
        async.elapse(const Duration(milliseconds: 60));
        async.flushMicrotasks();
        expect(calls, 2, reason: 'متابعة واحدة محدودة — لا حلقة لا نهائية');
        expect(
          realtime.hasRemoteChanges.value,
          isFalse,
          reason: 'المتابعة نجحت → الشارات صُفّرت',
        );
      });
    });
  });

  group('R8: التوقف الإرادي وضمان الاستئناف', () {
    test(
      'بعد stop(): الأحداث لا تُطلق سحباً وensureStarted يبقى صامتاً',
      () async {
        realtime.resetForTesting();
        realtime.currentDeviceIdForTesting = 'device-A';
        var triggerCalls = 0;
        realtime.setSyncTrigger(() async {
          triggerCalls++;
          return true;
        });

        await realtime.stop();
        await realtime.ensureStarted(); // يجب أن يحترم intentionallyStopped
        expect(realtime.isListening, isFalse);

        realtime.handleRemoteDataChange(
          events: ['databases.main.collections.bookings.documents.create'],
          payload: {'device_id': 'device-B'},
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          triggerCalls,
          0,
          reason: 'لا سحب من أحداث جديدة بعد stop() قبل أي start() جديد',
        );
      },
    );
  });

  group('R9: وضع fallback — علامة + سحب خفيف دوري', () {
    test('WS معطّل → fallback polling يُطلق سحباً فعلياً دورياً', () {
      fakeAsync((async) {
        realtime.resetForTesting();
        SharedPreferences.setMockInitialValues({
          'appwrite_realtime_ws_enabled': false, // فرض الوضع اليدوي
        });

        var triggerCalls = 0;
        realtime.setSyncTrigger(() async {
          triggerCalls++;
          return true;
        });

        unawaited(realtime.start());
        async.flushMicrotasks();

        expect(
          realtime.fallbackPollingActiveForTesting,
          isTrue,
          reason: 'WS معطّل → وضع fallback يعمل',
        );

        // تكت (30 ثانية) أولى: علامة UI فقط.
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(
          triggerCalls,
          0,
          reason: 'قبل بلوغ فاصل السحب الخفيف: لا سحب بعد',
        );
        expect(realtime.hasRemoteChanges.value, isTrue);

        // فاصل السحب الخفيف (مختصر للاختبار إلى 60 ثانية = تكتان).
        realtime.debugFallbackPullInterval = const Duration(minutes: 1);
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(
          triggerCalls,
          1,
          reason: 'الـ fallback يُطلق سحباً فعلياً دورياً وليس شارة فقط',
        );

        // تكت التالي: الفاصل = 30 ثانية (يساوي تيك واحد) → سحب ثانٍ.
        realtime.debugFallbackPullInterval = const Duration(seconds: 30);
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(triggerCalls, 2);

        unawaited(realtime.stop());
        async.flushMicrotasks();
        expect(realtime.fallbackPollingActiveForTesting, isFalse);
      });
    });
  });

  test('الثوابت: التهيئة والفواصل ضمن حدود معقولة', () {
    // حماية من تعديل يكسر ضبط المعدل: التهيئة ≥ 5 ث (لا إغراق) و≤ 60 ث
    // (يبقى "فورياً" بإحساس المستخدم)، والفاصل الاحتياطي ≥ دقيقة.
    expect(
      SyncConstants.realtimeEventPullCooldown.inSeconds,
      allOf(greaterThanOrEqualTo(5), lessThanOrEqualTo(60)),
    );
    expect(
      SyncConstants.realtimeFallbackPullInterval.inMinutes,
      greaterThanOrEqualTo(1),
    );
    // التفعيل الكامل يجب ألا يلمس حارس الدقيقتين لمداخل الشاشات/المؤقتات.
    expect(SyncConstants.minPullGap, const Duration(minutes: 2));
  });
}
