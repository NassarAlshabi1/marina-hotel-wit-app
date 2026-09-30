// ═══════════════════════════════════════════════════════════════
//  connection_client_freshness_test.dart — (2026-09-30)
//  انحدار: شارة الاتصال كانت تحمرّ دائماً بعد فترة استخدام — عميل
//  http.Client واحد لعمر الجلسة يحتفظ بوصلات keep-alive ميتة بصمت.
//  العقد: كل checkConnection يبني عميلاً جديداً ويغلقه بعده.
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/providers/appwrite_providers.dart';
import 'package:marina_hotel_mobile/services/worker_endpoints.dart';
import 'package:marina_hotel_mobile/utils/env.dart';

/// عميل عدّاد: يحصي الطلبات ويسجّل الإغلاق ثم يفوّض للداخلي.
class _TrackingClient extends http.BaseClient {
  _TrackingClient(this.inner);

  final http.Client inner;
  int requests = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    return inner.send(request);
  }

  @override
  void close() {
    closed = true;
    inner.close();
    super.close();
  }
}

void main() {
  setUp(() {
    WorkerEndpoints.resetForTests();
    Env.cloudflareAuthToken = null;
  });

  tearDown(() {
    Env.cloudflareAuthToken = null;
    WorkerEndpoints.resetForTests();
  });

  http.Client healthyMock() {
    return MockClient((request) async {
      if (request.url.path == '/health') {
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      }
      return http.Response('not found', 404);
    });
  }

  test('فحصان متتاليان = عميلان جديدان مغلقان (لا إعادة استخدام)', () async {
    final created = <_TrackingClient>[];
    final container = ProviderContainer(
      overrides: [
        connectionStatusProvider.overrideWith(
          (ref) => ConnectionStatusNotifier(
            ref,
            clientFactory: () {
              final tracker = _TrackingClient(healthyMock());
              created.add(tracker);
              return tracker;
            },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(connectionStatusProvider.notifier);
    await notifier.checkConnection();
    await notifier.checkConnection();

    expect(container.read(connectionStatusProvider).isConnected, isTrue);
    expect(created, hasLength(2));
    for (final tracker in created) {
      // أول مرشح يجيب 200 → طلب واحد فقط (/health) لكل فحص.
      expect(tracker.requests, 1);
      expect(tracker.closed, isTrue);
    }
  });

  test('العميل المحقون يُعاد استخدامه (توافق الاختبارات القديمة)', () async {
    var factoryCalls = 0;
    final injected = healthyMock();
    final container = ProviderContainer(
      overrides: [
        connectionStatusProvider.overrideWith(
          (ref) => ConnectionStatusNotifier(
            ref,
            client: injected,
            clientFactory: () {
              factoryCalls++;
              return healthyMock();
            },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(connectionStatusProvider.notifier);
    await notifier.checkConnection();
    await notifier.checkConnection();

    expect(container.read(connectionStatusProvider).isConnected, isTrue);
    expect(factoryCalls, 0);
  });
}
