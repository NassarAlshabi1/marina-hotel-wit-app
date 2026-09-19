// ═══════════════════════════════════════════════════════════════
//  cloudflare_ai_service_test.dart — ✅ (2026-09-20)
//  طلب المستخدم: «توكن ai worker اضفة الى ai» — عقود رفع توكن الـ
//  Worker الحي مع طلبات AI: كانت الخدمة تقرأ 'auth_token' القديم
//  (PHP API) حصراً فتخرج الطلبات بلا Authorization صالحة → 401.
//  العقود هنا تثبت سلسلة أولوية التوكن وترويسة Bearer الفعلية عبر
//  MockClient (بلا شبكة حقيقية).
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/services/cloudflare_ai_service.dart';
import 'package:marina_hotel_mobile/utils/env.dart';

void main() {
  setUp(() {
    CloudflareAiService.debugHttpClient = null;
    CloudflareAiService.debugTokenResolver = null;
    Env.cloudflareAuthToken = null;
  });

  tearDown(() {
    CloudflareAiService.debugHttpClient = null;
    CloudflareAiService.debugTokenResolver = null;
    Env.cloudflareAuthToken = null;
  });

  group('resolveWorkerToken — سلسلة أولوية التوكن', () {
    test('توكن المدير الحي يتفوق على نسخة Env المرآتية', () {
      expect(
        CloudflareAiService.resolveWorkerToken(
          managerToken: 'worker-jwt',
          envToken: 'env-jwt',
        ),
        'worker-jwt',
      );
    });

    test('غياب توكن المدير → نسخة Env المرآتية', () {
      expect(
        CloudflareAiService.resolveWorkerToken(
          managerToken: null,
          envToken: 'env-jwt',
        ),
        'env-jwt',
      );
    });

    test('القيم الفارغة/الفراغات تُعامَل كغياب (لا ترويسة ناقصة)', () {
      expect(
        CloudflareAiService.resolveWorkerToken(
          managerToken: '',
          envToken: '   ',
        ),
        isNull,
      );
    });

    test('القيم تُقصّ من الحواف قبل الرفع', () {
      expect(
        CloudflareAiService.resolveWorkerToken(managerToken: '  worker-jwt  '),
        'worker-jwt',
      );
    });

    test('كلا المصدرين غائب → null', () {
      expect(
        CloudflareAiService.resolveWorkerToken(
          managerToken: null,
          envToken: null,
        ),
        isNull,
      );
    });

    test('المصادر الحية الافتراضية: Env وحدها تُقرأ في بيئة الاختبار', () {
      // مدير المزامنة لم يسجّل دخولاً في الاختبار (token=null)، فالمصدر
      // الحي الوحيد هنا هو النسخة المرآتية — نفس ما يحدث لاطلاق قبل
      // اكتمال دخول الإقلاع.
      Env.cloudflareAuthToken = 'mirrored-live-jwt';
      expect(
        CloudflareAiService.resolveWorkerToken(),
        'mirrored-live-jwt',
      );
    });
  });

  group('طلب AI عبر MockClient — التوكن في الترويسة', () {
    test('Bearer توكن الـ Worker يُرفَق مع الطلب', () async {
      String? capturedAuth;
      String? capturedBody;
      CloudflareAiService.debugHttpClient = MockClient((request) async {
        capturedAuth = request.headers['authorization'];
        capturedBody = request.body;
        return http.Response(
          jsonEncode({'answer': 'الإشغال 80%'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      CloudflareAiService.debugTokenResolver = () async => 'worker-jwt';

      final result = await CloudflareAiService.instance.ask('ما نسبة الإشغال؟');

      expect(result.answer, 'الإشغال 80%');
      expect(capturedAuth, 'Bearer worker-jwt');
      expect(capturedBody, isNotNull);
      expect(
        (jsonDecode(capturedBody!) as Map<String, dynamic>)['prompt'],
        'ما نسبة الإشغال؟',
      );
    });

    test('confirm يرسل الخطة مع confirm=true بنفس التوكن', () async {
      String? capturedAuth;
      Map<String, dynamic>? capturedBody;
      CloudflareAiService.debugHttpClient = MockClient((request) async {
        capturedAuth = request.headers['authorization'];
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'answer': 'أُضيف المصروف',
            'requires_confirmation': false,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      CloudflareAiService.debugTokenResolver = () async => 'worker-jwt';

      final plan = <String, dynamic>{
        'kind': 'add_expense',
        'expenseType': 'ديزل',
        'amountPerDay': 40000,
        'dateFrom': '2026-09-01',
        'dateTo': '2026-09-19',
        'explanation': 'مصروف ديزل يومي',
      };
      await CloudflareAiService.instance.confirm(plan);

      expect(capturedAuth, 'Bearer worker-jwt');
      expect(capturedBody, isNotNull);
      expect(capturedBody!['confirm'], isTrue);
      expect(capturedBody!['plan'], isA<Map<String, dynamic>>());
    });

    test(
      'غياب أي توكن → الطلب بلا ترويسة Authorization (السلوك السابق)',
      () async {
        bool? hadAuthHeader;
        CloudflareAiService.debugHttpClient = MockClient((request) async {
          hadAuthHeader = request.headers.containsKey('authorization');
          return http.Response(
            jsonEncode({'answer': 'تم'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        CloudflareAiService.debugTokenResolver = () async => null;

        final result = await CloudflareAiService.instance.ask('مرحبا');

        expect(result.answer, 'تم');
        expect(hadAuthHeader, isFalse);
      },
    );

    test('رسالة خطأ الخادم (401) تظهر كما هي — لا ابتلاع صامت', () async {
      CloudflareAiService.debugHttpClient = MockClient(
        (request) async => http.Response(
          jsonEncode({'error': 'صلاحية المدير مطلوبة'}),
          401,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      CloudflareAiService.debugTokenResolver = () async => 'stale-jwt';

      await expectLater(
        CloudflareAiService.instance.ask('أضف مصروف'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('صلاحية المدير مطلوبة'),
          ),
        ),
      );
    });
  });
}
