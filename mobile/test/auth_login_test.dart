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
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              return Directory.systemTemp.path;
            }
            return null;
          },
        );

    await SecondaryAppwriteConfig.ensureInitialized();
  });

  // ✅ P0-2 FIX (2026-08-06 Audit): تحديث الاختبارات لتطابق كلمات المرور
  // القوية الجديدة (كانت admin/admin و m/1، الآن قوية مع must_change_password).
  test('نجاح تسجيل الدخول للمسؤول بكلمة المرور القوية', () async {
    final notifier = AuthNotifier();
    await notifier.login('admin', 'MarinaAdmin2026!SecureXK7pZ3wR');
    expect(notifier.state.isAuthenticated, true);
    expect(notifier.state.currentUser?.username, 'admin');
    expect(notifier.state.currentUser?.permissions.contains('all'), true);
  });

  test('فشل تسجيل الدخول بكلمة المرور القديمة admin/admin', () async {
    // ✅ P0-2: كلمات المرور القديمة الضعيفة لم تعد صالحة
    final notifier = AuthNotifier();
    await notifier.login('admin', 'admin');
    expect(notifier.state.isAuthenticated, false);
    expect(notifier.state.error, isNotNull);
  });

  test('فشل تسجيل الدخول لبيانات خاطئة', () async {
    final notifier = AuthNotifier();
    await notifier.login('admin', 'wrong');
    expect(notifier.state.isAuthenticated, false);
    expect(notifier.state.error, isNotNull);
  });

  test('m يسجل دخول بكلمة المرور القوية بدون صلاحيات افتراضيًا', () async {
    final notifier = AuthNotifier();
    await notifier.login('m', 'MarinaSupervisor2026!Tk9mZ4vQ');
    expect(notifier.state.isAuthenticated, true);
    expect(notifier.state.currentUser?.username, 'm');
    expect(notifier.state.currentUser?.permissions.isEmpty, true);
  });
}
