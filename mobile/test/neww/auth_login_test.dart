import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/secondary_appwrite_config.dart';
import 'package:marina_hotel_mobile/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    // Mock path_provider لتجنب MissingPluginException من appwrite client
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io.path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              return Directory.systemTemp.path;
            }
            return null;
          },
        );

    await SecondaryAppwriteConfig.ensureInitialized();
  });

  test('رفض كلمة المرور الافتراضية القديمة للحساب المحلي admin', () async {
    final notifier = AuthNotifier(restoreSessionOnCreate: false);
    addTearDown(notifier.dispose);
    await notifier.login('admin', 'admin');
    expect(notifier.state.isAuthenticated, false);
    expect(notifier.state.error, isNotNull);
  });

  test('فشل تسجيل الدخول لبيانات خاطئة', () async {
    final notifier = AuthNotifier(restoreSessionOnCreate: false);
    addTearDown(notifier.dispose);
    await notifier.login('admin', 'wrong');
    expect(notifier.state.isAuthenticated, false);
    expect(notifier.state.error, isNotNull);
  });
}
