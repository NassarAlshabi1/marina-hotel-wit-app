// ═══════════════════════════════════════════════════════════════
//  connection_status_d1_test.dart — ✅ (2026-09-17)
//  طلب المستخدم: «عند فتح التطبيق يفترض يفحص تلقائيا الاتصال مع
//  cloudflare worker d1» — عقود فحص المسار الكامل في
//  ConnectionStatusNotifier: /health للـ Worker ثم /api/health/d1
//  لقاعدة D1 بتوكن الجلسة، + مراقب الإقلاع startupConnectionWatcher.
//  الشبكة محقونة عبر MockClient (بلا طلبات حقيقية).
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/providers/appwrite_providers.dart';
import 'package:marina_hotel_mobile/providers/cloudflare_connection_providers.dart';
import 'package:marina_hotel_mobile/services/connectivity_service.dart';
import 'package:marina_hotel_mobile/services/worker_endpoints.dart';
import 'package:marina_hotel_mobile/utils/env.dart';

void main() {
  setUp(() {
    WorkerEndpoints.resetForTests();
    Env.cloudflareAuthToken = null;
  });

  tearDown(() {
    Env.cloudflareAuthToken = null;
    WorkerEndpoints.resetForTests();
    ConnectivityService.instance.dispose();
  });

  ProviderContainer createContainer(http.Client client) {
    final container = ProviderContainer(
      overrides: [
        connectionStatusProvider.overrideWith(
          (ref) => ConnectionStatusNotifier(ref, client: client),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// موجّه وهمي: /health يجيب 200 دائماً؛ /api/health/d1 يجيب حسب
  /// [d1Status] (200 = استجابة d1:ok كاملة، 401 = جلسة منتهية، غيره = خطأ).
  http.Client workingClient({int d1Status = 200}) {
    return MockClient((request) async {
      if (request.url.path == '/health') {
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      }
      if (request.url.path == '/api/health/d1') {
        if (d1Status != 200) {
          return http.Response(
            jsonEncode(
              d1Status == 401
                  ? {'error': 'Invalid or expired token'}
                  : {'status': 'error', 'd1': 'unreachable'},
            ),
            d1Status,
          );
        }
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'd1': 'ok',
            'latency_ms': 12,
            'server_time': 1789600000,
            'timestamp': 1789600000000,
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
  }

  group('ConnectionStatusNotifier.checkConnection — المسار الكامل', () {
    test(
      'Worker حي + توكن صالح → متصل وD1 مستجيب مع زمن الاستجابة',
      () async {
        Env.cloudflareAuthToken = 'valid-jwt';
        final container = createContainer(workingClient());
        final notifier = container.read(connectionStatusProvider.notifier);

        await notifier.checkConnection();
        final state = container.read(connectionStatusProvider);

        expect(state.isChecking, isFalse);
        expect(state.isConnected, isTrue);
        expect(state.isD1Connected, isTrue);
        expect(state.d1LatencyMs, 12);
        expect(state.d1Error, isNull);
        expect(state.errorMessage, isNull);
        expect(state.lastCheckedAt, isNotNull);
      },
    );

    test(
      'Worker حي بلا توكن جلسة → D1 «لم يُفحص» (null) لا «فاشلاً»',
      () async {
        Env.cloudflareAuthToken = null;
        final container = createContainer(workingClient());
        final notifier = container.read(connectionStatusProvider.notifier);

        await notifier.checkConnection();
        final state = container.read(connectionStatusProvider);

        expect(state.isConnected, isTrue);
        expect(state.isD1Connected, isNull);
        expect(state.lastCheckedAt, isNotNull);
      },
    );

    test('توكن منتهي الصلاحية → D1 فاشل برسالة الجلسة المنتهية', () async {
      Env.cloudflareAuthToken = 'expired-jwt';
      final container = createContainer(workingClient(d1Status: 401));
      final notifier = container.read(connectionStatusProvider.notifier);

      await notifier.checkConnection();
      final state = container.read(connectionStatusProvider);

      expect(state.isConnected, isTrue);
      expect(state.isD1Connected, isFalse);
      expect(state.d1Error, contains('انتهت صلاحية الجلسة'));
    });

    test('D1 خادم يخطئ (503) → D1 فاشل مع كود الحالة', () async {
      Env.cloudflareAuthToken = 'valid-jwt';
      final container = createContainer(workingClient(d1Status: 503));
      final notifier = container.read(connectionStatusProvider.notifier);

      await notifier.checkConnection();
      final state = container.read(connectionStatusProvider);

      expect(state.isConnected, isTrue);
      expect(state.isD1Connected, isFalse);
      expect(state.d1Error, contains('503'));
    });

    test('Worker نفسه غير قابل للوصول → غير متصل وD1 لا يُفحص أصلاً', () async {
      final client = MockClient(
        (request) async => http.Response('boom', 503),
      );
      final container = createContainer(client);
      final notifier = container.read(connectionStatusProvider.notifier);

      await notifier.checkConnection();
      final state = container.read(connectionStatusProvider);

      expect(state.isConnected, isFalse);
      expect(state.errorMessage, contains('فشل الاتصال'));
      expect(state.isD1Connected, isNull);
      expect(state.lastCheckedAt, isNotNull);
    });

    test(
      'استثناء شبكة (حجب/انقطاع) → حالة عدم اتصال صادقة لا انفجار',
      () async {
        final client = MockClient(
          (request) async => throw http.ClientException('blocked', request.url),
        );
        final container = createContainer(client);
        final notifier = container.read(connectionStatusProvider.notifier);

        await notifier.checkConnection();
        final state = container.read(connectionStatusProvider);

        expect(state.isConnected, isFalse);
        expect(state.errorMessage, contains('خطأ في الاتصال'));
        expect(state.lastCheckedAt, isNotNull);
      },
    );
  });

  group('startupConnectionWatcherProvider — فحص الإقلاع التلقائي', () {
    test(
      'تفعيل المراقب عند فتح التطبيق ينفّذ فحصاً فورياً كامل المسار',
      () async {
        Env.cloudflareAuthToken = 'valid-jwt';
        final container = createContainer(workingClient());

        // نقرة «فتح التطبيق»: التفعيل من initState.
        container.read(startupConnectionWatcherProvider);

        // تصريف سلسلة الإقلاع (تهيئة الاتصال ثم الفحص الفوري).
        await pumpEventQueue();

        final state = container.read(connectionStatusProvider);
        expect(
          state.lastCheckedAt,
          isNotNull,
          reason: 'يجب أن يُنفّذ فحص فوري بمجرد التفعيل',
        );
        expect(state.isConnected, isTrue);
        expect(state.isD1Connected, isTrue);
        expect(state.d1LatencyMs, 12);
      },
    );

    test(
      'D1 لم يُفحص عند الإقلاع (لا توكن) → إعادة واحدة بعد 15 ثانية',
      () async {
        Env.cloudflareAuthToken = null;
        var d1Requested = false;
        final client = MockClient((request) async {
          if (request.url.path == '/api/health/d1') {
            d1Requested = true;
            return http.Response(jsonEncode({'d1': 'ok'}), 200);
          }
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        });
        final container = createContainer(client);

        container.read(startupConnectionWatcherProvider);
        await pumpEventQueue();

        // لا توكن → D1 لم يُطلب أصلاً في الفحص الأول.
        expect(d1Requested, isFalse);
        expect(container.read(connectionStatusProvider).isD1Connected, isNull);

        // جلسة الدخول اكتملت أثناء الـ 15 ثانية...
        Env.cloudflareAuthToken = 'valid-jwt';
        // ...المؤقت ينفّذ الإعادة (fakeAsync غير ضروري: ننتظر مباشرة).
        await Future<void>.delayed(const Duration(seconds: 16));
        await pumpEventQueue();

        // لكن العميل الوهمي لا يتحقق من التوكن هنا → استجابة 200 d1:ok
        // تُفسر «متصل» فقط إن نطابق عقد jsonDecode — الطلب أُرسل هو المهم.
        expect(
          d1Requested,
          isTrue,
          reason: 'إعادة الـ 15 ث يجب أن تفحص D1 بعد اكتمال الجلسة',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
