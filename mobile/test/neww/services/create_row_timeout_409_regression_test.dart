// ignore_for_file: lines_longer_than_80_chars
import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_network_helper.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';

/// اختبار انحدار لخطأ الإنتاج (2026-11-24 07:02):
///
/// [TIMEOUT] createRow(sync_logs/d1669973-...) - Timeout after 30s
/// [TIMEOUT] createRow(sync_logs/d1669973-...) - Failed: AppwriteException:
///   document_already_exists ... (409)
///
/// التشخيص: المحاولة الأولى وصلت للسيرفر وأنشأت المستند فعليًا، لكن مهلة
/// العميل (30s) رمت TimeoutException؛ أُعيدت المحاولة بنفس المعرّف الحتمي
/// (localUuid) فأجاب السيرفر 409 — فاعتُبرت الفشل خطأً كاذبًا.
///
/// الإصلاح (2026-11-25):
///   1) withTimeout: 409/already_exists يُسجّل debug (لا ERROR) ويُعاد رميه.
///   2) createRow: يلتقط 409 ويعتبره نجاحًا متكررًا آمنًا (idempotent)
///      ويرجع المستند الموجود بدل رمي الخطأ.
///
/// هذه الاختبارات تعمل دون أي اتصال فعلي (منطق نقي + دوال مُحقنة).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final helper = AppwriteNetworkHelper();

  setUp(helper.resetForTest);
  tearDown(helper.resetForTest);

  group('كاشف 409 في createRow (isDocumentAlreadyExists)', () {
    test('code 409 بلا type → true', () {
      expect(
        AppwriteService.isDocumentAlreadyExistsForTest(
          AppwriteException('conflict', 409),
        ),
        isTrue,
      );
    });

    test('type document_already_exists (كما في سجل الإنتاج) → true', () {
      expect(
        AppwriteService.isDocumentAlreadyExistsForTest(
          AppwriteException(
            "Document with the requested ID 'd1669973-...' already exists.",
            409,
            'document_already_exists',
          ),
        ),
        isTrue,
      );
    });

    test('type conflict وحده → true', () {
      expect(
        AppwriteService.isDocumentAlreadyExistsForTest(
          AppwriteException('c', 409, 'conflict'),
        ),
        isTrue,
      );
    });

    test('الرسالة النصية تحمل document_already_exists → true', () {
      expect(
        AppwriteService.isDocumentAlreadyExistsForTest(
          AppwriteException(
            'document_already_exists in message body',
            400,
          ),
        ),
        isTrue,
      );
    });

    test('400 bad_request ليس 409 → false', () {
      expect(
        AppwriteService.isDocumentAlreadyExistsForTest(
          AppwriteException('bad request', 400, 'general_argument_invalid'),
        ),
        isFalse,
      );
    });

    test('404 document_not_found ليس 409 → false', () {
      expect(
        AppwriteService.isDocumentAlreadyExistsForTest(
          AppwriteException('nf', 404, 'document_not_found'),
        ),
        isFalse,
      );
    });

    test('429 rate limit ليس 409 → false', () {
      expect(
        AppwriteService.isDocumentAlreadyExistsForTest(
          AppwriteException('too many', 429, 'general_rate_limit_exceeded'),
        ),
        isFalse,
      );
    });

    test('500 server error ليس 409 → false', () {
      expect(
        AppwriteService.isDocumentAlreadyExistsForTest(
          AppwriteException('internal', 500),
        ),
        isFalse,
      );
    });
  });

  group('سيناريو الإنتاج: timeout ثم 409 عند إعادة المحاولة', () {
    test(
      'withRetry يعيد المحاولة على TimeoutException ثم يمرر الـ 409 النهائي',
      () async {
        var calls = 0;
        Object? finalError;
        try {
          await helper.withRetryAndTimeout<String>(
            // مضاهاة createRow: المحاولة الأولى timeout (السيرفر استقبلها
            // وأنشأ المستند فعلًا)؛ الثانية تصطدم بوجوده → 409.
            operation: () async {
              calls++;
              if (calls == 1) {
                throw TimeoutException(
                  'simulate 30s client timeout',
                  const Duration(seconds: 30),
                );
              }
              throw AppwriteException(
                "Document with the requested ID 'd1669973-...' already exists.",
                409,
                'document_already_exists',
              );
            },
            maxRetries: 2,
            timeout: const Duration(milliseconds: 300),
            operationName: 'createRow(sync_logs/d1669973)',
          );
        } catch (e) {
          finalError = e;
        }

        // المحاولة الأولى timeout + الثانية 409 (الحد الأقصى) → الخطأ
        // النهائي المرمي هو 409 نفسه (وليس TimeoutException) — وهذا ما
        // يصل createRow ليعامله كنجاح متكرر آمن.
        expect(finalError, isA<AppwriteException>());
        final awExp = finalError as AppwriteException;
        expect(awExp.code, 409);
        expect(awExp.type, contains('document_already_exists'));
        expect(calls, 2);
      },
    );

    test(
      'TimeoutException قابل لإعادة المحاولة — والـ 409 غير قابل فيمرَّر كما هو',
      () {
        final timeoutExp =
            TimeoutException('Operation timeout occurred');
        expect(helper.isRetriableErrorForTest(timeoutExp), isTrue);

        final conflictExp = AppwriteException(
          'already exists',
          409,
          'document_already_exists',
        );
        expect(helper.isRetriableErrorForTest(conflictExp), isFalse);
      },
    );
  });
}
