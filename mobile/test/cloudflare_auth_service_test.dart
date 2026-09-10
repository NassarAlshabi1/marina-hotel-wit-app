// اختبارات CloudflareAuthService — شاشة الدخول المتصلة بـ Cloudflare.
// تغطي: النجاح (200+JWT)، رفض البيانات (401)، الحجب (429+retry_after)،
// أخطاء الخادم (5xx)، فشل الشبكة العابر مع إعادة المحاولة، وغياب الضبط.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/services/cloudflare_auth_service.dart';

void main() {
  const base = 'https://worker.example.com';
  String Function() resolve = () => base;

  CloudflareAuthService build(http.Client client) =>
      CloudflareAuthService(client: client, baseUrlResolver: resolve);

  group('CloudflareAuthService.login', () {
    test('نجاح الدخول — يعيد JWT وبيانات المستخدم', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{"token":"jwt-abc","user":{"id":"u1","username":"nassar","role":"admin"}}',
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });

      final result = await build(client).login(
        username: 'nassar',
        password: 'secret',
        deviceId: 'dev-1',
      );

      expect(result.isSuccess, isTrue);
      expect(result.status, CloudflareAuthStatus.success);
      expect(result.token, 'jwt-abc');
      expect(result.userId, 'u1');
      expect(result.username, 'nassar');
      expect(result.role, 'admin');
      expect(requests, hasLength(1));
      expect(requests.single.url.toString(), '$base/api/auth/login');
      expect(requests.single.body, contains('"device_id":"dev-1"'));
    });

    test('بيانات خاطئة 401 — invalidCredentials بلا استثناءات', () async {
      final client = MockClient(
        (_) async => http.Response('{"error":"Invalid credentials"}', 401),
      );

      final result = await build(client).login(
        username: 'nassar',
        password: 'wrong',
      );

      expect(result.status, CloudflareAuthStatus.invalidCredentials);
      expect(result.isSuccess, isFalse);
    });

    test('حجب المحاولات 429 — retry_after_sec صريح بالثواني', () async {
      final client = MockClient((_) async {
        return http.Response(
          '{"error":"Too many login attempts","retry_after":1710000000000,'
          '"retry_after_sec":42}',
          429,
        );
      });

      final result = await build(client).login(
        username: 'nassar',
        password: 'x',
      );

      expect(result.status, CloudflareAuthStatus.rateLimited);
      expect(result.retryAfterSeconds, 42);
      expect(result.userMessage, contains('أعد المحاولة'));
    });

    test(
      'حجب 429 بصيغة قديمة epoch-millis — يطبَّع إلى ثوانٍ متبقية',
      () async {
        final client = MockClient((_) async {
          // resetAt بعد 90 ثانية من الآن (millis) — بلا retry_after_sec.
          final resetAt = DateTime.now().millisecondsSinceEpoch + 90000;
          return http.Response(
            '{"error":"Too many login attempts","retry_after":$resetAt}',
            429,
          );
        });

        final result = await build(client).login(
          username: 'nassar',
          password: 'x',
        );

        expect(result.status, CloudflareAuthStatus.rateLimited);
        expect(result.retryAfterSeconds, isNotNull);
        expect(result.retryAfterSeconds!, greaterThan(60));
        expect(result.retryAfterSeconds!, lessThanOrEqualTo(90));
      },
    );

    test('خطأ خادمي 500 — serverError', () async {
      final client = MockClient(
        (_) async => http.Response('{"error":"Login failed"}', 500),
      );

      final result = await build(client).login(username: 'a', password: 'b');

      expect(result.status, CloudflareAuthStatus.serverError);
    });

    test('فشل شبكة عابر — يعيد المحاولة مرة ثم networkError', () async {
      var attempts = 0;
      final client = MockClient((_) async {
        attempts++;
        throw const SocketException('Connection reset by peer');
      });

      final result = await build(client).login(username: 'a', password: 'b');

      expect(attempts, 2, reason: 'الفشل العابر يستحق إعادة محاولة واحدة');
      expect(result.status, CloudflareAuthStatus.networkError);
      expect(result.isSuccess, isFalse);
    });

    test('Worker غير مضبوط — networkError فوري بلا طلبات', () async {
      resolve = () => '';
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });

      final result = await build(client).login(username: 'a', password: 'b');

      expect(result.status, CloudflareAuthStatus.networkError);
      expect(called, isFalse, reason: 'لا يجب أي طلب شبكي بلا عنوان');
      resolve = () => base;
    });
  });

  group('CloudflareAuthService.checkHealth', () {
    test('يعيد true عند 200 من /api/health', () async {
      final client = MockClient(
        (request) async => http.Response('{"ok":true}', 200),
      );
      expect(await build(client).checkHealth(), isTrue);
    });

    test('يعيد false عند فشل الشبكة', () async {
      final client = MockClient((_) async => throw TimeoutException('t'));
      expect(await build(client).checkHealth(), isFalse);
    });

    test('يعيد false عند غياب الضبط', () async {
      resolve = () => '';
      final client = MockClient((_) async => http.Response('{}', 200));
      expect(await build(client).checkHealth(), isFalse);
      resolve = () => base;
    });
  });
}
