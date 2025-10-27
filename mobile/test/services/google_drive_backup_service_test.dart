import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/google_drive_backup_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

// ملاحظات:
// - هذه الاختبارات تتحقق من سلوك تكامل Google Sign-In بعد إصلاح ApiException: 10
// - تم إنشاء فصول Mock/Stub بسيطة بدون توليد آلي لتسهيل التحكم في السيناريوهات
// - نلتقط رسائل debugPrint للتحقق من السجلات العربية الصحيحة

class TestGoogleSignInAccount implements GoogleSignInAccount {
  TestGoogleSignInAccount(this._email);
  final String _email;

  @override
  String get email => _email;

  @override
  Future<Map<String, String>> get authHeaders async => {
        'Authorization': 'Bearer test-token',
      };

  // خصائص/دوال أخرى غير مستخدمة في الخدمة تُعاد افتراضيات
  @override
  String? get displayName => null;

  @override
  String? get id => 'test-id';

  @override
  String? get photoUrl => null;

  @override
  Future<GoogleSignInAuthentication> get authentication async =>
      const GoogleSignInAuthentication(idToken: 'id', accessToken: 'access');

  @override
  Future<void> clearAuthCache() async {}

  @override
  Map<String, String> get idHeaders => const {};

  @override
  Future<bool> canAccessScopes(List<String> scopes) async => true;

  @override
  Future<bool> requestScopes(List<String> scopes) async => true;
}

class TestGoogleSignIn extends GoogleSignIn {
  TestGoogleSignIn({this.silentResult, this.interactiveResult, this.throwOnCall})
      : super(scopes: const <String>[]);

  final GoogleSignInAccount? silentResult;
  final GoogleSignInAccount? interactiveResult;
  final Object? throwOnCall;

  GoogleSignInAccount? _current;
  bool signOutCalled = false;

  @override
  GoogleSignInAccount? get currentUser => _current;

  @override
  Future<GoogleSignInAccount?> signInSilently({bool suppressErrors = true}) async {
    if (throwOnCall != null) {
      throw throwOnCall!;
    }
    _current = silentResult;
    return silentResult;
  }

  @override
  Future<GoogleSignInAccount?> signIn() async {
    if (throwOnCall != null) {
      throw throwOnCall!;
    }
    _current = interactiveResult;
    return interactiveResult;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    _current = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object?>{});
  });

  group('تهيئة GoogleSignIn', () {
    test('عدم وجود serverClientId وعدم وجود forceCodeForRefreshToken مع وجود النطاق الصحيح', () async {
      final service = GoogleDriveBackupService();
      final config = service.debugDescribeSignInConfig();

      expect(config['serverClientId'], isNull);
      expect(config['forceCodeForRefreshToken'], false);
      expect(config['scopes'], [drive.DriveApi.driveFileScope]);
    });
  });

  group('اختبار دالة _getArabicErrorMessage', () {
    test('رسالة ApiException: 10 (DEVELOPER_ERROR)', () {
      final service = GoogleDriveBackupService();
      final msg = service.getArabicErrorMessageForTest(Exception('ApiException: 10 (DEVELOPER_ERROR)'));
      expect(msg.contains('DEVELOPER_ERROR 10'), true);
    });

    test('رسالة sign_in_failed', () {
      final service = GoogleDriveBackupService();
      expect(service.getArabicErrorMessageForTest(Exception('sign_in_failed')), contains('فشل'));
    });

    test('رسالة network_error', () {
      final service = GoogleDriveBackupService();
      expect(service.getArabicErrorMessageForTest(Exception('network_error')), contains('الشبكة'));
    });

    test('رسالة sign_in_canceled', () {
      final service = GoogleDriveBackupService();
      expect(service.getArabicErrorMessageForTest(Exception('sign_in_canceled')), contains('إلغاء'));
    });

    test('رسالة sign_in_required', () {
      final service = GoogleDriveBackupService();
      expect(service.getArabicErrorMessageForTest(Exception('sign_in_required')), contains('مطلوب'));
    });

    test('رسالة للأخطاء غير المتوقعة', () {
      final service = GoogleDriveBackupService();
      expect(service.getArabicErrorMessageForTest(Exception('weird_error')), contains('غير متوقع'));
    });
  });

  group('تسجيل الدخول الناجح', () {
    test('تسجيل الدخول الصامت silently', () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      final service = GoogleDriveBackupService();
      final account = TestGoogleSignInAccount('silent@test.com');
      final fakeSignIn = TestGoogleSignIn(silentResult: account);
      service.overrideGoogleSignIn(fakeSignIn);

      final result = await service.signInForDrive();

      expect(result, isNotNull);
      expect(result!.email, 'silent@test.com');
      expect(service.hasDriveApi, true);
      expect(logs.any((l) => l.contains('تم تسجيل الدخول بنجاح')), true);
      expect(logs.any((l) => l.contains('silent@test.com')), true);

      debugPrint = originalDebugPrint;
    });

    test('تسجيل الدخول التفاعلي', () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      final service = GoogleDriveBackupService();
      final account = TestGoogleSignInAccount('interactive@test.com');
      final fakeSignIn = TestGoogleSignIn(silentResult: null, interactiveResult: account);
      service.overrideGoogleSignIn(fakeSignIn);

      final result = await service.signInForDrive();

      expect(result, isNotNull);
      expect(result!.email, 'interactive@test.com');
      expect(service.hasDriveApi, true);
      expect(logs.any((l) => l.contains('تم تسجيل الدخول بنجاح')), true);

      debugPrint = originalDebugPrint;
    });
  });

  group('حالات فشل تسجيل الدخول', () {
    test('محاكاة PlatformException مع كود 10', () async {
      final service = GoogleDriveBackupService();
      final fakeSignIn = TestGoogleSignIn(throwOnCall: const PlatformException(code: '10', message: 'DEVELOPER_ERROR'));
      service.overrideGoogleSignIn(fakeSignIn);

      try {
        await service.signInForDrive();
        fail('يجب أن يرمي استثناء');
      } catch (e) {
        final msg = e.toString();
        expect(msg, contains('DEVELOPER_ERROR'));
        expect(msg, contains('10'));
      }
    });

    test('محاكاة خطأ الشبكة', () async {
      final service = GoogleDriveBackupService();
      final fakeSignIn = TestGoogleSignIn(throwOnCall: Exception('network_error'));
      service.overrideGoogleSignIn(fakeSignIn);

      try {
        await service.signInForDrive();
        fail('يجب أن يرمي استثناء');
      } catch (e) {
        expect(e.toString(), contains('الشبكة'));
      }
    });

    test('محاكاة إلغاء المستخدم لتسجيل الدخول', () async {
      final service = GoogleDriveBackupService();
      final fakeSignIn = TestGoogleSignIn(throwOnCall: Exception('sign_in_canceled'));
      service.overrideGoogleSignIn(fakeSignIn);

      try {
        await service.signInForDrive();
        fail('يجب أن يرمي استثناء');
      } catch (e) {
        expect(e.toString(), contains('إلغاء'));
      }
    });
  });

  group('تسجيل الخروج', () {
    test('إعادة تعيين DriveApi والـ backupFolderId واستدعاء signOut()', () async {
      final service = GoogleDriveBackupService();
      final account = TestGoogleSignInAccount('logout@test.com');
      final fakeSignIn = TestGoogleSignIn(silentResult: account);
      service.overrideGoogleSignIn(fakeSignIn);

      await service.signInForDrive();
      expect(service.hasDriveApi, true);

      await service.signOut();
      expect(service.hasDriveApi, false);
      expect(fakeSignIn.signOutCalled, true);

      // التأكد أن استدعاء عمليات Drive بلا تسجيل يسبب خطأ
      expect(
        () => service.getOrCreateBackupFolder(),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('اختبار التكامل: تهيئة -> تسجيل دخول -> استخدام DriveApi -> تسجيل خروج', () {
    test('السيناريو الكامل الأساسي', () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      final service = GoogleDriveBackupService();
      final account = TestGoogleSignInAccount('all@test.com');
      final fakeSignIn = TestGoogleSignIn(silentResult: null, interactiveResult: account);
      service.overrideGoogleSignIn(fakeSignIn);

      // تهيئة ضمنيًا تتم عبر المُنشئ
      final config = service.debugDescribeSignInConfig();
      expect(config['scopes'], [drive.DriveApi.driveFileScope]);

      // تسجيل الدخول (سيتحول للتفاعلي)
      final result = await service.signInForDrive();
      expect(result, isNotNull);
      expect(service.hasDriveApi, true);

      // لا نستدعي واجهة Drive الحقيقية في الاختبار، فقط نتحقق من السجلات
      expect(logs.any((l) => l.contains('تم تسجيل الدخول بنجاح')), true);

      // تسجيل الخروج
      await service.signOut();
      expect(service.hasDriveApi, false);

      debugPrint = originalDebugPrint;
    });
  });
}
