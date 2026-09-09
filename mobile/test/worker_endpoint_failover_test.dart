// ═══════════════════════════════════════════════════════════════
//  worker_endpoint_failover_test.dart
//  ✅ (2026-09-09) عقود «دعم عدّة عناوين Worker مع تبديل تلقائي»
//  (طلب المستخدم — حالة حجب workers.dev في اليمن):
//  A) WorkerEndpoints: تطبيع الإدخال، ترتيب المرشحين، عزل الطلبات
//     خارج عائلة الـworker، تثبيت الفائز sticky + استعادته، الترجيع
//     عند الفشل، فرض المخصّص عند التحميل.
//  B) ResilientHttpClient endpoint rotation: فشل اتصالي على نقطة
//     (reset/timeout/handshake — أي استثناء) → إعادة كتابة الطلب
//     (نفس الجسم والترويسات) على المرشح التالي → نجاح موثق بالـ
//     callbacks. + e2e حلقي: نفق CONNECT حقيقي + TLS حقيقي على
//     المرشح الثاني بعد موت المسارين للمرشح الأول.
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/services/resilient_http_client.dart';
import 'package:marina_hotel_mobile/services/worker_endpoints.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String builtinHost = 'marina-hotel-api.adenmarina2.workers.dev';

/// يعيد تفعيل HttpClient الحقيقي داخل الزون (اختبارات النفق فقط).
///
/// ⚠️ يجب `super.createHttpClient` — نداء `HttpClient()` المصنعي داخل
/// `createHttpClient` يستدعي الـoverride من جديد → Stack Overflow لا نهائي
/// (فخ موثق في resilient_http_client_fallback_test.dart).
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
  setUp(() {
    ResilientHttpClient.resetSharedState();
    WorkerEndpoints.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('WorkerEndpoints.normalizeCustomUrl', () {
    test('يضيف https ويقص المسار والزخارف', () {
      expect(
        WorkerEndpoints.normalizeCustomUrl('api.mydomain.com'),
        'https://api.mydomain.com',
      );
      expect(
        WorkerEndpoints.normalizeCustomUrl(' https://Api.MyDomain.com/ '),
        'https://api.mydomain.com',
      );
      expect(
        WorkerEndpoints.normalizeCustomUrl('api.mydomain.com:8443'),
        'https://api.mydomain.com:8443',
      );
    });

    test('الفارغ يعيد null والفاسد يرمي FormatException', () {
      expect(WorkerEndpoints.normalizeCustomUrl(null), isNull);
      expect(WorkerEndpoints.normalizeCustomUrl('   '), isNull);
      expect(
        () => WorkerEndpoints.normalizeCustomUrl('no-tld'),
        throwsFormatException,
      );
      expect(
        () => WorkerEndpoints.normalizeCustomUrl('http://api.mydomain.com'),
        throwsFormatException,
      );
      expect(
        () => WorkerEndpoints.normalizeCustomUrl('https://h.com/api/ping'),
        throwsFormatException,
      );
    });
  });

  group('WorkerEndpoints registry', () {
    test('الافتراضي: المدمج فعّالاً ومرشح وحيد (لا تدوير)', () async {
      await WorkerEndpoints.load();
      expect(WorkerEndpoints.active, 'https://$builtinHost');
      final url = Uri.parse('https://$builtinHost/api/sync/pull');
      expect(WorkerEndpoints.candidatesFor(url), hasLength(1));
    });

    test('نطاق مخصّص: أولوية دائمة في المرشحين مهما كان عنوان الطلب', () async {
      await WorkerEndpoints.load();
      final saved = await WorkerEndpoints.setCustomUrl('api.mydomain.com');
      expect(saved, 'https://api.mydomain.com');
      expect(WorkerEndpoints.active, 'https://api.mydomain.com');

      // طلب بُني على المدمج → المدمج أولاً ثم المخصّص.
      final fromBuiltin = WorkerEndpoints.candidatesFor(
        Uri.parse('https://$builtinHost/x'),
      );
      expect(fromBuiltin.map((u) => u.host).toList(), <String>[
        builtinHost,
        'api.mydomain.com',
      ]);

      // طلب بُني على المخصّص → المخصّص أولاً ثم المدمج.
      final fromCustom = WorkerEndpoints.candidatesFor(
        Uri.parse('https://api.mydomain.com/x'),
      );
      expect(fromCustom.map((u) => u.host).toList(), <String>[
        'api.mydomain.com',
        builtinHost,
      ]);
    });

    test('طلبات خارج عائلة الـworker معزولة (لا تدوير أبداً)', () async {
      await WorkerEndpoints.load();
      await WorkerEndpoints.setCustomUrl('api.mydomain.com');
      final cands = WorkerEndpoints.candidatesFor(
        Uri.parse('https://api.cloudflare.com/client/v4/accounts'),
      );
      expect(cands, hasLength(1));
      expect(cands.single.host, 'api.cloudflare.com');
    });

    test('فشل يرجّع للمدمج ونجاح يعيد المخصّص (sticky)', () async {
      await WorkerEndpoints.load();
      await WorkerEndpoints.setCustomUrl('api.mydomain.com');

      WorkerEndpoints.reportFailure(Uri.parse('https://api.mydomain.com'));
      expect(WorkerEndpoints.active, 'https://$builtinHost');

      // نجاح تقريره قد يحمل مساراً — يجب أن يُخزَّن كقاعدة نقية.
      WorkerEndpoints.reportSuccess(
        Uri.parse('https://api.mydomain.com/api/sync/pull'),
      );
      expect(WorkerEndpoints.active, 'https://api.mydomain.com');
    });

    test('sticky يُحفظ في prefs ويُستعاد (محاكاة إعادة تشغيل)', () async {
      await WorkerEndpoints.load();
      await WorkerEndpoints.setCustomUrl('api.mydomain.com');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(WorkerEndpoints.customUrlKey),
        'https://api.mydomain.com',
      );
      expect(
        prefs.getString(WorkerEndpoints.activeUrlKey),
        'https://api.mydomain.com',
      );

      WorkerEndpoints.resetForTests();
      await WorkerEndpoints.load();
      expect(WorkerEndpoints.active, 'https://api.mydomain.com');
    });

    test('التحميل يفرض المخصّص على sticky قديم للمدمج (إشارة الحجب)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        WorkerEndpoints.customUrlKey: 'https://api.mydomain.com',
        WorkerEndpoints.activeUrlKey: 'https://$builtinHost',
      });
      await WorkerEndpoints.load();
      expect(WorkerEndpoints.active, 'https://api.mydomain.com');
    });

    test('مسح النطاق المخصّص يعيد للمدمج ويُمسح من prefs', () async {
      await WorkerEndpoints.load();
      await WorkerEndpoints.setCustomUrl('api.mydomain.com');
      final cleared = await WorkerEndpoints.setCustomUrl(null);
      expect(cleared, isNull);
      expect(WorkerEndpoints.active, 'https://$builtinHost');
      expect(WorkerEndpoints.hasCustom, isFalse);
    });
  });

  group('ResilientHttpClient endpoint rotation', () {
    test('فشل اتصالي على المرشح الأول → إعادة كتابة الطلب على الثاني '
        '(نفس المسار/الجسم/الترويسات) + توثيق نجاح/فشل', () async {
      final seenPaths = <String>[];
      final seenBodies = <String>[];
      final seenAuth = <String?>[];
      final failures = <Uri>[];
      final successes = <Uri>[];

      final inner = MockClient((request) async {
        seenPaths.add(request.url.path);
        seenBodies.add(request.body);
        seenAuth.add(request.headers['Authorization']);
        if (request.url.host == 'primary.test') {
          throw const SocketException('connection reset (SNI blocked)');
        }
        return http.Response('{"status":"ok"}', 200);
      });

      final client = ResilientHttpClient(
        innerClient: inner,
        fastTimeout: const Duration(milliseconds: 500),
        timeout: const Duration(seconds: 3),
        // بلا DoH — فشل النفق فوري ومحدد (لا شبكة حقيقية في الوحدة).
        dohResolver: (_) async => const <String>[],
        systemResolver: (_) async => const <String>[],
        endpointPlanner: (url) => <Uri>[
          Uri.parse('https://primary.test'),
          Uri.parse('https://secondary.test'),
        ],
        onEndpointSuccess: successes.add,
        onEndpointFailure: failures.add,
      );

      final response = await client.post(
        Uri.parse('https://primary.test/api/auth/login'),
        headers: {'Authorization': 'Bearer tok'},
        body: jsonEncode({'username': 'u'}),
      );

      expect(response.statusCode, 200);
      expect(response.body, '{"status":"ok"}');
      expect(seenPaths, <String>['/api/auth/login', '/api/auth/login']);
      expect(seenBodies.first, seenBodies.last);
      expect(seenAuth, everyElement('Bearer tok'));
      expect(failures.map((u) => u.host).toList(), <String>['primary.test']);
      expect(successes.map((u) => u.host).toList(), <String>['secondary.test']);
    });

    test(
      'مضيف غير مسجّل في المخطط → قائمة وحيدة (سلوك سابق بلا تدوير)',
      () async {
        var calls = 0;
        final inner = MockClient((request) async {
          calls++;
          throw const SocketException('down');
        });
        final failures = <Uri>[];
        final client = ResilientHttpClient(
          innerClient: inner,
          fastTimeout: const Duration(milliseconds: 200),
          dohResolver: (_) async => const <String>[],
          systemResolver: (_) async => const <String>[],
          endpointPlanner: WorkerEndpoints.candidatesFor,
          onEndpointFailure: failures.add,
        );
        // api.cloudflare.com ليست نقطة worker — لا تدوير ولا callbacks.
        await expectLater(
          client.get(Uri.parse('https://api.cloudflare.com/x')),
          throwsA(isA<SocketException>()),
        );
        expect(calls, 1);
        expect(failures, isEmpty);
      },
    );

    test('الجميع يفشل → آخر خطأ اتصالي يصل المُنادي كما هو', () async {
      final inner = MockClient((request) async {
        throw TimeoutException('blackhole');
      });
      final client = ResilientHttpClient(
        innerClient: inner,
        fastTimeout: const Duration(milliseconds: 150),
        timeout: const Duration(milliseconds: 300),
        // بلا DoH: فشل النفق فوري SocketException — محدد بلا شبكة.
        dohResolver: (_) async => const <String>[],
        systemResolver: (_) async => const <String>[],
        endpointPlanner: (url) => <Uri>[
          Uri.parse('https://a.test'),
          Uri.parse('https://b.test'),
        ],
      );
      await expectLater(
        client.get(Uri.parse('https://a.test/api/ping')),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('Wiring الإنتاجي: WorkerEndpoints ↔ ResilientHttpClient', () {
    test(
      'فشل المخصّص يبدّل الفعّال، والطلب التالي يُبنى عليه مباشرة',
      () async {
        await WorkerEndpoints.load();
        await WorkerEndpoints.setCustomUrl('api.mydomain.com');

        final hits = <String>[];
        final inner = MockClient((request) async {
          hits.add(request.url.host);
          if (request.url.host == 'api.mydomain.com') {
            throw const SocketException('custom domain misconfigured');
          }
          return http.Response('{"status":"ok"}', 200);
        });

        // نفس التوصيل الذي يجريه createResilientHttpClient.
        final client = ResilientHttpClient(
          innerClient: inner,
          fastTimeout: const Duration(milliseconds: 300),
          dohResolver: (_) async => const <String>[],
          systemResolver: (_) async => const <String>[],
          endpointPlanner: WorkerEndpoints.candidatesFor,
          onEndpointSuccess: WorkerEndpoints.reportSuccess,
          onEndpointFailure: WorkerEndpoints.reportFailure,
        );

        // الطلب الأول بُني على الفعّال (المخصّص) → فشل → تدوير → نجاح مدمج.
        final base1 = WorkerEndpoints.active;
        final r1 = await client.get(Uri.parse('$base1/api/ping'));
        expect(r1.statusCode, 200);
        expect(hits, <String>['api.mydomain.com', builtinHost]);
        expect(WorkerEndpoints.active, 'https://$builtinHost');

        // الطلب الثاني بُني على الفعّال الجديد (المدمج) → نجاح مباشر.
        final base2 = WorkerEndpoints.active;
        final r2 = await client.get(Uri.parse('$base2/api/ping'));
        expect(r2.statusCode, 200);
        expect(hits.last, builtinHost);
      },
    );
  });

  group('e2e: تدوير فوق النفق بـTLS حقيقي', () {
    HttpServer? upstream;
    late int upstreamPort;

    setUpAll(() async {
      const certChain = 'test/fixtures/tunnel_certs';
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
        if (req.uri.path == '/api/ping') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'status': 'ok'}));
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

    test('مسار سريع ميت على الجميع + منفذ المرشح الأول مغلق → '
        'النفق يوصل المرشح الثاني بشهادة صحيحة', () async {
      await runRealHttp(() async {
        final clientCtx = SecurityContext()
          ..setTrustedCertificates('test/fixtures/tunnel_certs/ca.crt');
        var innerCalls = 0;
        final deadInner = MockClient.streaming((request, bodyStream) async {
          innerCalls++;
          throw SocketException('fast path dead ($innerCalls)');
        });

        final client = ResilientHttpClient(
          innerClient: deadInner,
          timeout: const Duration(seconds: 10),
          fastTimeout: const Duration(milliseconds: 300),
          dohResolver: (_) async => <String>['127.0.0.1'],
          tunnelConnector: (ip, port) =>
              Socket.connect(ip, port).timeout(const Duration(seconds: 5)),
          fallbackSecurityContext: clientCtx,
          endpointPlanner: (url) => <Uri>[
            Uri.parse('https://127.0.0.1:1'), // منفذ مغلق — رفض فوري
            Uri.parse('https://$builtinHost:$upstreamPort'),
          ],
        );

        final response = await client.get(
          Uri.parse('https://127.0.0.1:1/api/ping'),
        );
        expect(response.statusCode, 200);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['status'], 'ok');
      });
    });
  });
}
