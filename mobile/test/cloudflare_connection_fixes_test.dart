// ═══════════════════════════════════════════════════════════════
//  cloudflare_connection_fixes_test.dart — ✅ (2026-09-29)
//  عقود إصلاحات تشخيص «فشل اتصال Worker/D1»
//  (mobile/CLOUDFLARE_WORKER_D1_CONNECTION_DIAGNOSIS_2026-09-29.md):
//
//  C2 — فحص البطاقة مراقب لا حَكَم: لا يُنزّل الجسر العامل لبطء عابر،
//       ويرقّي فقط على دليل إيجابي (200) — ويدمج الفحوص المتزامنة.
//  C3 — ميزانية لكل مرشح غير أخير: مرشح معلّق (إسقاط SNI صامت) لا
//       يستهلك مهلة المُنادي قبل الوصول إلى الجسر؛ والمحاولة المتروكة
//       لا تكمل إلى النفق.
//  C4 — sticky قديم على workers.dev يبدأ على الجسر بعد الترقية.
//  C5 — الدخول يعيد المحاولة على 429 (Retry-After) و5xx العابرة فقط.
//  C7 — نوع فشل D1 صادق + إبطال التوكن المرفوض (401).
//
//  الشبكة كلها محقونة (MockClient/Completer) — بلا طلبات حقيقية.
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/providers/appwrite_providers.dart';
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/resilient_http_client.dart';
import 'package:marina_hotel_mobile/services/worker_endpoints.dart';
import 'package:marina_hotel_mobile/utils/env.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _relayUrl = 'https://marina-hotel-api-relay.pages.dev';
const String _relayHost = 'marina-hotel-api-relay.pages.dev';
final String _builtinUrl = WorkerEndpoints.builtin;
final String _builtinHost = Uri.parse(WorkerEndpoints.builtin).host;

http.Response _jsonResponse(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WorkerEndpoints.resetForTests();
    WorkerEndpoints.setRelayForTests(_relayUrl);
    ResilientHttpClient.resetSharedState();
    Env.cloudflareAuthToken = null;
  });

  tearDown(() {
    Env.cloudflareAuthToken = null;
    WorkerEndpoints.resetForTests();
    ResilientHttpClient.resetSharedState();
  });

  // ─── C4 ─────────────────────────────────────────────────────
  group('C4 — ترقية sticky القديم إلى الجسر عند التحميل', () {
    test('sticky = workers.dev + جسر مفعّل بلا مخصّص → البداية على الجسر '
        '(في الذاكرة فقط — لا يُكتب إلى prefs قبل نجاح فعلي)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        WorkerEndpoints.activeUrlKey: _builtinUrl,
      });
      await WorkerEndpoints.load();
      expect(WorkerEndpoints.active, _relayUrl);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(WorkerEndpoints.activeUrlKey),
        _builtinUrl,
        reason: 'الترقية عند التحميل ظنية — النجاح وحده ما يُحفظ',
      );
    });

    test('الجسر معطّل → sticky المدمج يبقى كما هو (لا تغيير سلوك)', () async {
      WorkerEndpoints.setRelayForTests('');
      SharedPreferences.setMockInitialValues(<String, Object>{
        WorkerEndpoints.activeUrlKey: _builtinUrl,
      });
      await WorkerEndpoints.load();
      expect(WorkerEndpoints.active, _builtinUrl);
    });

    test('نطاق مخصّص موجود → المخصّص يتقدم (العقد السابق محفوظ)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        WorkerEndpoints.customUrlKey: 'https://api.mydomain.com',
        WorkerEndpoints.activeUrlKey: _builtinUrl,
      });
      await WorkerEndpoints.load();
      expect(WorkerEndpoints.active, 'https://api.mydomain.com');
    });
  });

  // ─── C2 + C7 ────────────────────────────────────────────────
  group('C2/C7 — فحص البطاقة: مراقب لا حَكَم + نوع فشل صادق', () {
    ProviderContainer containerWith(http.Client client) {
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

    test('الجسر (الفعّال) يفشل عابراً والمدمج محجوب → لا تنزيل: '
        'الفعّال يبقى الجسر', () async {
      await WorkerEndpoints.load();
      expect(WorkerEndpoints.active, _relayUrl);

      final hits = <String>[];
      // الفعّال لحظة كل طلب — يكشف أي تنزيل وسيط (لا النهائي فقط):
      // تنزيلان متتاليان على مرشحين قد يلتفّان عائدين للجسر فيخفيان الخلل.
      final activeDuring = <String>[];
      final container = containerWith(
        MockClient((request) async {
          hits.add(request.url.host);
          activeDuring.add(WorkerEndpoints.active);
          throw http.ClientException('timeout-ish', request.url);
        }),
      );

      await container.read(connectionStatusProvider.notifier).checkConnection();

      final state = container.read(connectionStatusProvider);
      expect(state.isConnected, isFalse);
      expect(hits, <String>[_relayHost, _builtinHost]);
      expect(activeDuring, everyElement(_relayUrl));
      expect(
        WorkerEndpoints.active,
        _relayUrl,
        reason: 'فشل فحص البطاقة ليس دليلاً كافياً لتنزيل نقطة المزامنة',
      );
    });

    test('sticky على المدمج المحجوب + الجسر يعمل → متصل، ترقية الجسر، '
        'وD1 يُفحص على نفس القاعدة التي أجابت', () async {
      WorkerEndpoints.setRelayForTests('');
      SharedPreferences.setMockInitialValues(<String, Object>{
        WorkerEndpoints.activeUrlKey: _builtinUrl,
      });
      await WorkerEndpoints.load();
      WorkerEndpoints.setRelayForTests(_relayUrl); // الجسر يظهر بعد التحميل
      expect(WorkerEndpoints.active, _builtinUrl);

      Env.cloudflareAuthToken = 'valid-jwt';
      final d1Hosts = <String>[];
      final container = containerWith(
        MockClient((request) async {
          if (request.url.host == _builtinHost) {
            throw http.ClientException('SNI blocked', request.url);
          }
          if (request.url.path == '/api/health/d1') {
            d1Hosts.add(request.url.host);
            return _jsonResponse({'d1': 'ok', 'latency_ms': 9});
          }
          return _jsonResponse({'status': 'ok'});
        }),
      );

      await container.read(connectionStatusProvider.notifier).checkConnection();

      final state = container.read(connectionStatusProvider);
      expect(state.isConnected, isTrue);
      expect(state.isD1Connected, isTrue);
      expect(state.d1LatencyMs, 9);
      expect(d1Hosts, <String>[_relayHost]);
      expect(WorkerEndpoints.active, _relayUrl);
    });

    test('فحوص متزامنة تُدمج في طلب واحد لكل مرحلة', () async {
      await WorkerEndpoints.load();
      var healthCalls = 0;
      final gate = Completer<void>();
      final container = containerWith(
        MockClient((request) async {
          healthCalls++;
          await gate.future;
          return _jsonResponse({'status': 'ok'});
        }),
      );
      final notifier = container.read(connectionStatusProvider.notifier);

      final a = notifier.checkConnection();
      final b = notifier.checkConnection();
      final c = notifier.checkConnection();
      gate.complete();
      await Future.wait([a, b, c]);

      expect(healthCalls, 1);
      expect(container.read(connectionStatusProvider).isConnected, isTrue);
    });

    test('401 → نوع auth + إبطال التوكن المرفوض نفسه', () async {
      await WorkerEndpoints.load();
      Env.cloudflareAuthToken = 'rejected-jwt';
      final container = containerWith(
        MockClient((request) async {
          if (request.url.path == '/api/health/d1') {
            return _jsonResponse({'error': 'Invalid or expired token'}, 401);
          }
          return _jsonResponse({'status': 'ok'});
        }),
      );

      await container.read(connectionStatusProvider.notifier).checkConnection();

      final state = container.read(connectionStatusProvider);
      expect(state.isD1Connected, isFalse);
      expect(state.d1Failure, D1ProbeFailure.auth);
      expect(state.d1Error, contains('انتهت صلاحية الجلسة'));
      expect(Env.cloudflareAuthToken, isNull);
      expect(
        d1FailureHeadline(state.d1Failure),
        contains('جلسة المزامنة مرفوضة'),
      );
      expect(d1FailureHeadline(state.d1Failure), isNot(contains('D1')));
    });

    test('429 → نوع rateLimited مع Retry-After — لا «D1 لا تستجيب»', () async {
      await WorkerEndpoints.load();
      Env.cloudflareAuthToken = 'valid-jwt';
      final container = containerWith(
        MockClient((request) async {
          if (request.url.path == '/api/health/d1') {
            return http.Response(
              jsonEncode({'error': 'Rate limit exceeded'}),
              429,
              headers: {'retry-after': '17'},
            );
          }
          return _jsonResponse({'status': 'ok'});
        }),
      );

      await container.read(connectionStatusProvider.notifier).checkConnection();

      final state = container.read(connectionStatusProvider);
      expect(state.d1Failure, D1ProbeFailure.rateLimited);
      expect(state.d1Error, contains('17'));
      expect(Env.cloudflareAuthToken, 'valid-jwt');
      expect(d1FailureHeadline(state.d1Failure), contains('كثرة طلبات'));
    });

    test('503 → نوع unavailable بعنوان «D1 لا تستجيب»', () async {
      await WorkerEndpoints.load();
      Env.cloudflareAuthToken = 'valid-jwt';
      final container = containerWith(
        MockClient((request) async {
          if (request.url.path == '/api/health/d1') {
            return _jsonResponse({'d1': 'unreachable'}, 503);
          }
          return _jsonResponse({'status': 'ok'});
        }),
      );

      await container.read(connectionStatusProvider.notifier).checkConnection();

      final state = container.read(connectionStatusProvider);
      expect(state.d1Failure, D1ProbeFailure.unavailable);
      expect(d1FailureHeadline(state.d1Failure), contains('D1 لا تستجيب'));
    });
  });

  // ─── C3 ─────────────────────────────────────────────────────
  group('C3 — ميزانية التدوير لكل مرشح غير أخير', () {
    test('rotationDeadline: 12ث لكل مرشح سابق + ميزانية الأخير', () {
      const last = Duration(seconds: 15);
      expect(
        ResilientHttpClient.rotationDeadline(1, lastCandidateBudget: last),
        last,
      );
      expect(
        ResilientHttpClient.rotationDeadline(2, lastCandidateBudget: last),
        const Duration(seconds: 27),
      );
      expect(
        ResilientHttpClient.rotationDeadline(3, lastCandidateBudget: last),
        const Duration(seconds: 39),
      );
    });

    test('المرشح الأول يعلّق بصمت → الثاني يُجرَّب ضمن مهلة المُنادي، '
        'والأول يُنزَّل، والمحاولة المتروكة لا تصل إلى DoH/النفق', () async {
      await WorkerEndpoints.load();
      // الفعّال = المدمج (سيناريو ما بعد الترقية/التنزيل).
      WorkerEndpoints.reportSuccess(Uri.parse(_builtinUrl));
      expect(WorkerEndpoints.active, _builtinUrl);

      final dohLookups = <String>[];
      final hang = Completer<http.StreamedResponse>();
      final client = ResilientHttpClient(
        innerClient: _RoutingClient((request) {
          if (request.url.host == _builtinHost) return hang.future;
          return Future.value(
            http.StreamedResponse(
              Stream.value(utf8.encode('{"token":"t"}')),
              200,
            ),
          );
        }),
        // المسار السريع أطول من الميزانية: بدون C3 كان الطلب ينتظره
        // ثم DoH ثم النفق قبل أي تدوير.
        fastTimeout: const Duration(milliseconds: 600),
        candidateBudget: const Duration(milliseconds: 150),
        dohResolver: (host) async {
          dohLookups.add(host);
          return const <String>[];
        },
        systemResolver: (_) async => const <String>[],
        endpointPlanner: WorkerEndpoints.candidatesFor,
        onEndpointSuccess: WorkerEndpoints.reportSuccess,
        onEndpointFailure: WorkerEndpoints.reportFailure,
      );
      addTearDown(client.close);

      final sw = Stopwatch()..start();
      final response = await client
          .post(Uri.parse('$_builtinUrl/api/auth/login'), body: '{}')
          // مهلة مُنادٍ أقصر بكثير من مسار المرشح الأول الكامل.
          .timeout(const Duration(seconds: 2));
      sw.stop();

      expect(response.statusCode, 200);
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
      expect(WorkerEndpoints.active, _relayUrl);

      // انتظر انتهاء المسار السريع المتروك: يجب ألا يكمل إلى DoH.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(
        dohLookups,
        isNot(contains(_builtinHost)),
        reason: 'المحاولة المتروكة لا تبدأ النفق (تنافس المرشح التالي)',
      );
    });

    test('المرشح الأخير لا يُقطع بالميزانية (لا بديل بعده)', () async {
      await WorkerEndpoints.load(); // الفعّال = الجسر، الأخير = المدمج
      final client = ResilientHttpClient(
        innerClient: _RoutingClient((request) async {
          if (request.url.host == _relayHost) {
            throw http.ClientException('relay down', request.url);
          }
          // المدمج (الأخير) بطيء لكن ينجح — أبطأ من الميزانية.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return http.StreamedResponse(Stream.value(utf8.encode('ok')), 200);
        }),
        fastTimeout: const Duration(seconds: 2),
        candidateBudget: const Duration(milliseconds: 100),
        dohResolver: (_) async => const <String>[],
        systemResolver: (_) async => const <String>[],
        endpointPlanner: WorkerEndpoints.candidatesFor,
        onEndpointSuccess: WorkerEndpoints.reportSuccess,
        onEndpointFailure: WorkerEndpoints.reportFailure,
      );
      addTearDown(client.close);

      final r = await client.get(Uri.parse('$_relayUrl/health'));
      expect(r.statusCode, 200);
      expect(WorkerEndpoints.active, _builtinUrl);
    });
  });

  // ─── C5 ─────────────────────────────────────────────────────
  group('C5 — إعادة محاولة الدخول على الرموز العابرة فقط', () {
    late AppDatabase db;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'cloudflare_sync_local_override': true,
      });
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Future<List<int>> runLogin(List<http.Response> script) async {
      final served = <int>[];
      var i = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/api/auth/login')) {
          final r = script[i < script.length ? i : script.length - 1];
          i++;
          served.add(r.statusCode);
          return r;
        }
        return http.Response('not found', 404);
      });
      final manager = CloudflareSyncManager()..reset();
      manager.configureForTesting(database: db, httpClient: client);
      await manager.initialize(database: db);
      return served;
    }

    test('429 مع Retry-After قصير ثم 200 → جلسة صالحة', () async {
      final served = await runLogin([
        http.Response(
          jsonEncode({'error': 'Too many login attempts'}),
          429,
          headers: {'retry-after': '1'},
        ),
        _jsonResponse({'token': 'jwt-after-429'}),
      ]);
      expect(served, <int>[429, 200]);
      expect(Env.cloudflareAuthToken, 'jwt-after-429');
    });

    test('503 عابر (الجسر/الحافة) ثم 200 → جلسة صالحة', () async {
      final served = await runLogin([
        _jsonResponse({'error': 'unavailable'}, 503),
        _jsonResponse({'token': 'jwt-after-503'}),
      ]);
      expect(served, <int>[503, 200]);
      expect(Env.cloudflareAuthToken, 'jwt-after-503');
    });

    test('Retry-After أطول من السقف → لا انتظار داخل الدورة', () async {
      final served = await runLogin([
        http.Response('{}', 429, headers: {'retry-after': '120'}),
        _jsonResponse({'token': 'never'}),
      ]);
      expect(served, <int>[429]);
      expect(Env.cloudflareAuthToken, isNull);
    });

    test('401 نهائي → محاولة واحدة فقط (لا طرق كلمة مرور خاطئة)', () async {
      final served = await runLogin([
        _jsonResponse({'error': 'Invalid credentials'}, 401),
        _jsonResponse({'token': 'never'}),
      ]);
      expect(served, <int>[401]);
      expect(Env.cloudflareAuthToken, isNull);
    });
  });
}

/// عميل داخلي يوجّه كل طلب إلى [handler] كـ StreamedResponse مباشرة —
/// يسمح بمستقبل لا يكتمل أبداً (تعليق صامت) بخلاف MockClient.
class _RoutingClient extends http.BaseClient {
  _RoutingClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
