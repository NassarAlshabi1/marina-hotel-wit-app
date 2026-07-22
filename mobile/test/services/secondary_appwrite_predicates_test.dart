// ignore_for_file: lines_longer_than_80_chars
import 'package:appwrite/appwrite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/secondary_appwrite_service.dart';

/// اختبارات وحدوية لمصنّفات أخطاء upsert/delete في SecondaryAppwriteService
/// ولتطبيع المعرّف البديل (بدون شرطات).
///
/// هذه الدوالّ هي قلب المسار الظاهر في سجلات الإنتاج:
///   update → 404 (isNotFound) → altId → create
///   update → 409 (isAlreadyExists) → update
///   update → 429 (isRateLimit) → انتظار ثم create
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isNotFoundError', () {
    test('code 404 → true', () {
      expect(SecondaryAppwriteService.isNotFoundError(AppwriteException('x', 404)), isTrue);
    });

    test('type document_not_found → true', () {
      expect(
        SecondaryAppwriteService.isNotFoundError(AppwriteException('missing', 400, 'document_not_found')),
        isTrue,
      );
    });

    test('رسالة تحتوي document_not_found → true', () {
      // كما في السجل: "Document with the requested ID ... could not be found."
      expect(
        SecondaryAppwriteService.isNotFoundError(
          AppwriteException("document_not_found: Document with the requested ID 'abc' could not be found."),
        ),
        isTrue,
      );
    });

    test('409 ليس not-found → false', () {
      expect(SecondaryAppwriteService.isNotFoundError(AppwriteException('exists', 409)), isFalse);
    });

    test('429 ليس not-found → false', () {
      expect(SecondaryAppwriteService.isNotFoundError(AppwriteException('rate', 429)), isFalse);
    });
  });

  group('isAlreadyExistsError', () {
    test('code 409 → true', () {
      expect(SecondaryAppwriteService.isAlreadyExistsError(AppwriteException('x', 409)), isTrue);
    });

    test('type document_already_exists → true', () {
      expect(
        SecondaryAppwriteService.isAlreadyExistsError(AppwriteException('dup', 400, 'document_already_exists')),
        isTrue,
      );
    });

    test('type conflict → true', () {
      expect(SecondaryAppwriteService.isAlreadyExistsError(AppwriteException('c', 400, 'conflict')), isTrue);
    });

    test('404 ليس already-exists → false', () {
      expect(SecondaryAppwriteService.isAlreadyExistsError(AppwriteException('missing', 404)), isFalse);
    });
  });

  group('isRateLimitError', () {
    test('code 429 → true', () {
      expect(SecondaryAppwriteService.isRateLimitError(AppwriteException('too many', 429)), isTrue);
    });

    test('type rate_limit → true', () {
      expect(SecondaryAppwriteService.isRateLimitError(AppwriteException('x', 400, 'rate_limit')), isTrue);
    });

    test('type general_rate_limit_exceeded → true', () {
      expect(
        SecondaryAppwriteService.isRateLimitError(AppwriteException('x', 400, 'general_rate_limit_exceeded')),
        isTrue,
      );
    });

    test('404 ليس rate-limit → false', () {
      expect(SecondaryAppwriteService.isRateLimitError(AppwriteException('missing', 404)), isFalse);
    });
  });

  group('المصنّفات متعارضة صحيحاً (لا تتداخل خطأً)', () {
    test('404 حصراً not-found (ليس exists/rate)', () {
      final e = AppwriteException('missing', 404, 'document_not_found');
      expect(SecondaryAppwriteService.isNotFoundError(e), isTrue);
      expect(SecondaryAppwriteService.isAlreadyExistsError(e), isFalse);
      expect(SecondaryAppwriteService.isRateLimitError(e), isFalse);
    });

    test('429 حصراً rate-limit (ليس not-found/exists)', () {
      final e = AppwriteException('too many', 429);
      expect(SecondaryAppwriteService.isRateLimitError(e), isTrue);
      expect(SecondaryAppwriteService.isNotFoundError(e), isFalse);
      expect(SecondaryAppwriteService.isAlreadyExistsError(e), isFalse);
    });

    test('409 حصراً exists (ليس not-found/rate)', () {
      final e = AppwriteException('dup', 409, 'document_already_exists');
      expect(SecondaryAppwriteService.isAlreadyExistsError(e), isTrue);
      expect(SecondaryAppwriteService.isNotFoundError(e), isFalse);
      expect(SecondaryAppwriteService.isRateLimitError(e), isFalse);
    });
  });

  group('altDocumentId (تطبيع المعرّف بدون شرطات)', () {
    test('UUID بشرطات → يُزيلها', () {
      expect(
        SecondaryAppwriteService.altDocumentId('a3069099-8e9c-4291-991e-6aeb60730d17'),
        'a30690998e9c4291991e6aeb60730d17',
      );
    });

    test('معرّف بلا شرطات → سلسلة فارغة (لا بديل)', () {
      expect(SecondaryAppwriteService.altDocumentId('a30690998e9c4291991e6aeb60730d17'), '');
    });

    test('سلسلة فارغة → فارغة', () {
      expect(SecondaryAppwriteService.altDocumentId(''), '');
    });

    test('يُزيل كل الشرطات لا الأولى فقط', () {
      expect(SecondaryAppwriteService.altDocumentId('x-y-z'), 'xyz');
    });
  });
}
