// ═══════════════════════════════════════════════════════════════
//  resilient_http_client_fallback_test.dart
//  ✅ (2026-09-09) عقود المسار البديل بعد إعادة التصميم:
//  «المصادقة TimeoutException» — كان السبب الجذري أن المسار السريع
//  المعلّق (DNS أسود/حجب) لا يُشغّل الـfallback إطلاقاً (كان يُشغَّل
//  لأخطاء DNS فقط)، ومسار IP-in-URL كان مكسوراً بنيوياً (Cloudflare
//  يرفض TLS بلا SNI صحيح). التصميم الجديد: أي فشل سريع خلال مهلة قصيرة
//  → DoH متوازٍ → نفق CONNECT محلي يربط بالـIP مع SNI صحيح.
//  الاختبارات هنا e2e حلقي: خادم HttpServer حقيقي + نفق حقيقي + عميل
//  HttpClient حقيقي عبر findProxy — فقط الـDNS والسوكيت الداخلي محقونان.
//  flutter_test يحجب HTTP الحقيقي افتراضياً → runRealHttp يفتح زوناً
//  بـHttpOverrides.runZoned لاختبارات النفق فقط.
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/services/resilient_http_client.dart';

const testHost = 'marina-hotel-api.adenmarina2.workers.dev';

/// يعيد تفعيل HttpClient الحقيقي داخل الزون (بدلاً من 400 الوهمي).
///
/// ⚠️ يجب `super.createHttpClient` — نداء `HttpClient()` المصنعي داخل
/// `createHttpClient` يستدعي الـoverride من جديد → Stack Overflow لا نهائي.
class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 5);
  }
}

Future<T> runRealHttp<T>(Future<T> Function() body) {
  return HttpOverrides.runZoned(
    body,
    createHttpClient: _RealHttpOverrides().createHttpClient,
  );
}

void main() {
  HttpServer? upstream;
  late int upstreamPort;

  setUpAll(() async {
    // خادم «الوجهة» الحقيقي على loopback — TLS كامل بشهادة CA اختبارية
    // (CN = دومين الـworker) — التحقق من الشهادة حقيقي 100% عميلياً.
    final certChain = 'test/fixtures/tunnel_certs';
    final serverCtx = SecurityContext()
      ..useCertificateChain('$certChain/server.crt')
      ..usePrivateKey('$certChain/server.testkey');
    upstream = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverCtx,
    );
    upstreamPort = upstream!.port;
    upstream!.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      if (req.method == 'POST' && req.uri.path == '/api/auth/login') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'token': 'jwt-x',
            'user': {'username': 'admin', 'role': 'admin'},
            'echo': jsonDecode(body),
          }),
        );
        await req.response.close();
        return;
      }
      if (req.uri.path == '/api/ping') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({'status': 'ok', 'padding': 'x' * 64}),
        );
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await upstream?.close(force: true);
  });

  setUp(() {
    ResilientHttpClient.resetSharedState();
  });

  ResilientHttpClient buildClient({
    required http.Client inner,
    Future<List<String>> Function(String host)? dohResolver,
  }) {
    // العميل يثق بـCA الاختبارية فقط — التحقق من الشهادة + اسم المضيف
    // (عبر SNI داخل النفق) يجري بآلية Dart القياسية دون أي تجاوز.
    final clientCtx = SecurityContext()
      ..setTrustedCertificates('test/fixtures/tunnel_certs/ca.crt');
    return ResilientHttpClient(
      innerClient: inner,
      // الميزانية الكلية لكل محاولة بديلة — الافتراضي 30s؛ نقصرها لصيانة
      // سرعة الاختبار فقط.
      timeout: const Duration(seconds: 10),
      fastTimeout: const Duration(milliseconds: 800),
      dohResolver: dohResolver ?? (_) async => ['127.0.0.1'],
      // النفق يُوجَّه إلى خادم الاختبار الحلقي بغض النظر عن المنفذ القادم
      // في CONNECT (443) — حقن الواجهة فقط.
      tunnelConnector: (ip, port) =>
          Socket.connect(ip, upstreamPort).timeout(const Duration(seconds: 5)),
      fallbackSecurityContext: clientCtx,
    );
  }

  group('ResilientHttpClient tunnel fallback', () {
    test(
      'login POST: fast-path TimeoutException (DNS blackhole) → tunnel fallback succeeds',
      () async {
        var innerCalls = 0;
        final hangingInner = MockClient.streaming((request, bodyStream) async {
          innerCalls++;
          // يحاكي DNS أسود/حجب: يعلق أبداً — مهلة المسار السريع هي التي تطلقه.
          return Completer<http.StreamedResponse>().future;
        });

        final client = buildClient(inner: hangingInner);
        final response = await runRealHttp(
          () => client.post(
            Uri.parse('https://$testHost/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': 'admin',
              'password': 'secret',
              'device_id': 'device-abc',
            }),
          ),
        );

        expect(innerCalls, 1, reason: 'المسار السريع يُجرَّب مرة واحدة فقط');
        expect(response.statusCode, 200);
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        expect(data['token'], 'jwt-x');
        final echo = data['echo'] as Map<String, dynamic>;
        expect(echo['username'], 'admin');
        expect(echo['device_id'], 'device-abc');
        client.close();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'DNS failure (Failed host lookup) → tunnel fallback succeeds',
      () async {
        final dnsDeadInner = MockClient((request) async {
          throw const SocketException('Failed host lookup: no address');
        });

        final client = buildClient(inner: dnsDeadInner);
        final response = await runRealHttp(
          () => client.get(Uri.parse('https://$testHost/api/ping')),
        );

        expect(response.statusCode, 200);
        expect(jsonDecode(response.body)['status'], 'ok');
        client.close();
      },
    );

    test(
      'dead keep-alive socket (SocketException) → tunnel fallback',
      () async {
        var calls = 0;
        final flakyInner = MockClient((request) async {
          calls++;
          if (calls == 1) {
            throw const SocketException(
              'Connection closed while receiving data',
            );
          }
          fail('الطلب الثاني يجب أن يتجاوز المسار السريع عبر الـcooldown');
        });

        final client = buildClient(inner: flakyInner);
        final response = await runRealHttp(
          () => client.get(Uri.parse('https://$testHost/api/ping')),
        );
        expect(response.statusCode, 200);
        client.close();
      },
    );

    test('healthy fast path → no fallback, resolver never called', () async {
      final okInner = MockClient((request) async {
        return http.Response('{"status":"ok"}', 200);
      });
      var resolverCalls = 0;

      final client = buildClient(
        inner: okInner,
        dohResolver: (_) async {
          resolverCalls++;
          return ['127.0.0.1'];
        },
      );
      final response = await client.get(
        Uri.parse('https://$testHost/api/ping'),
      );

      expect(response.statusCode, 200);
      expect(resolverCalls, 0, reason: 'المسار السليم لا يستدعي DoH إطلاقاً');
      client.close();
    });

    test('cooldown: second request skips the hanging fast path', () async {
      var innerCalls = 0;
      final hangingInner = MockClient.streaming((request, bodyStream) async {
        innerCalls++;
        return Completer<http.StreamedResponse>().future;
      });

      final client = buildClient(inner: hangingInner);

      final r1 = await runRealHttp(
        () => client.get(Uri.parse('https://$testHost/api/ping')),
      );
      expect(r1.statusCode, 200);
      expect(innerCalls, 1);

      final r2 = await runRealHttp(
        () => client.get(Uri.parse('https://$testHost/api/ping')),
      );
      expect(r2.statusCode, 200);
      expect(
        innerCalls,
        1,
        reason: 'الـbreaker يمنع إعادة تعليق المسار السريع لمدة 10 دقائق',
      );
      expect(ResilientHttpClient.isFastPathBlockedFor(testHost), isTrue);
      client.close();
    });

    test('DoH returns no IPs → clear SocketException', () async {
      final hangingInner = MockClient.streaming((request, bodyStream) async {
        return Completer<http.StreamedResponse>().future;
      });

      final client = buildClient(
        inner: hangingInner,
        dohResolver: (_) async => <String>[],
      );

      await expectLater(
        client.get(Uri.parse('https://$testHost/api/ping')),
        throwsA(
          isA<SocketException>().having(
            (e) => e.message,
            'message',
            contains('Could not resolve'),
          ),
        ),
      );
      client.close();
    });

    test(
      'fallback reuses last-good route across requests (no hang tax)',
      () async {
        final hangingInner = MockClient.streaming((request, bodyStream) async {
          return Completer<http.StreamedResponse>().future;
        });

        final client = buildClient(inner: hangingInner);
        final sw = Stopwatch()..start();
        await runRealHttp(
          () => client.get(Uri.parse('https://$testHost/api/ping')),
        );
        sw.stop();
        final firstMs = sw.elapsedMilliseconds;

        sw.reset();
        await runRealHttp(
          () => client.get(Uri.parse('https://$testHost/api/ping')),
        );
        sw.stop();

        expect(sw.elapsedMilliseconds, lessThan(firstMs));
        client.close();
      },
    );
  });
}
