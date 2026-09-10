import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/google_drive_sign_in_manager.dart';

void main() {
  group('describeGoogleSignInFailure — ترجمة رموز ApiException', () {
    test('رمز 10 DEVELOPER_ERROR يُذكر بالشهادة واسم الحزمة', () {
      final message = describeGoogleSignInFailure(
        PlatformException(
          code: 'sign_in_failed',
          message:
              'com.google.android.gms.common.api.ApiException: 10: DEVELOPER_ERROR',
        ),
      );
      expect(message, contains('رمز 10'));
      expect(message, contains(kRegisteredSigningSha1));
      expect(message, contains(kRegisteredPackageName));
    });

    test('رمز 7 NETWORK_ERROR يوجّه للشبكة', () {
      final message = describeGoogleSignInFailure(
        PlatformException(
          code: 'network_error',
          message: 'com.google.android.gms.common.api.ApiException: 7',
        ),
      );
      expect(message, contains('رمز 7'));
      expect(message, contains('خوادم Google'));
    });

    test('network_error بلا نص ApiException — يُترجم عبر رمز المنصة', () {
      final message = describeGoogleSignInFailure(
        PlatformException(code: 'network_error'),
      );
      expect(message, contains('رمز 7'));
    });

    test('sign_in_canceled بلا نص ApiException — يُترجم إلغاءً', () {
      final message = describeGoogleSignInFailure(
        PlatformException(code: 'sign_in_canceled'),
      );
      expect(message, contains('رمز 12501'));
      expect(message, contains('أُلغي'));
    });

    test('رمز 12501 الإلغاء من واجهة Google', () {
      final message = describeGoogleSignInFailure(
        PlatformException(
          code: 'sign_in_failed',
          message: 'ApiException: 12501: SIGN_IN_CANCELLED',
        ),
      );
      expect(message, contains('أُلغي تسجيل الدخول'));
    });

    test('رمز 12500 يوجّه لشاشة موافقة OAuth والنطاقات', () {
      final message = describeGoogleSignInFailure(
        'ApiException: 12500',
      );
      expect(message, contains('OAuth'));
      expect(message, contains('drive.appdata'));
      expect(message, contains('Test user'));
    });

    test('رمز 4 SIGN_IN_REQUIRED يطلب إعادة الدخول', () {
      final message = describeGoogleSignInFailure(
        PlatformException(code: 'sign_in_required'),
      );
      expect(message, contains('رمز 4'));
    });

    test('user_recoverable_auth يطلب تفويضاً جديداً', () {
      final message = describeGoogleSignInFailure(
        PlatformException(code: 'user_recoverable_auth'),
      );
      expect(message, contains('تفويضاً'));
    });

    test('channel-error يذكر خدمات Google Play', () {
      final message = describeGoogleSignInFailure(
        PlatformException(code: 'channel-error'),
      );
      expect(message, contains('خدمات Google Play'));
    });

    test('سبب null (الخطأ مسكوم بالكامل) يعطي رسالة قابلة للتنفيذ', () {
      final message = describeGoogleSignInFailure(null);
      expect(message, isNotEmpty);
      expect(message, contains('أعد المحاولة'));
    });

    test('نص عربي عشوائي غير معروف يمر ضمن رسالة سياق', () {
      final message = describeGoogleSignInFailure('خطأ غامض 42');
      expect(message, contains('خطأ غامض 42'));
    });

    test('رمز غير معروف 9999 لا يعطّل الترجمة', () {
      final message = describeGoogleSignInFailure(
        'ApiException: 9999: MYSTERY',
      );
      expect(message, isNotEmpty);
      expect(message, contains('فشل غير متوقع'));
    });
  });

  group('GoogleDriveSignInManager — عقد lastError', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      // بلا معالجات قنوات: أي استدعاء للمنصة يرمي MissingPluginException —
      // بيئة hermetic تحاكي غياب خدمات Google دون أي IO حقيقي.
    });

    test('فشل القناة يُسجَّل في lastError ويبقى العقد null', () async {
      final manager = GoogleDriveSignInManager.instance;
      final silent = await manager.signInSilently();
      expect(silent, isNull);
      // بلا معالجات قنوات: MissingPluginException من قناة init —
      // المهم أن السبب لم يُبتلع وأصبح مرئياً.
      expect(manager.lastError, isNotNull);

      final interactive = await manager.signIn();
      expect(interactive, isNull);
      expect(manager.lastError, isNotNull);

      // الترجمة تعمل على الخطأ المسجّل مباشرة
      final translated = describeGoogleSignInFailure(manager.lastError);
      expect(translated, isNotEmpty);
    });
  });
}
