import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  test(
    'نجاح تسجيل الدخول للمسؤول admin/admin دون انتظار الشبكة',
    () async {
      final notifier = AuthNotifier();
      await notifier.login('admin', 'admin');
      expect(notifier.state.isAuthenticated, true);
      expect(notifier.state.currentUser?.username, 'admin');
      expect(notifier.state.currentUser?.permissions.contains('all'), true);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test('فشل تسجيل الدخول لبيانات خاطئة', () async {
    final notifier = AuthNotifier();
    await notifier.login('admin', 'wrong');
    expect(notifier.state.isAuthenticated, false);
    expect(notifier.state.error, isNotNull);
  });
}
