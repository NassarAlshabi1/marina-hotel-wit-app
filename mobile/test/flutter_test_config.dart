// test/flutter_test_config.dart
//
// ✅ تهيئة عامة لكل الاختبارات — تُشغَّل قبل أي test
// يحل مشكلة segfault في drift/SQLite على CI (Linux)
//
// السبب: NativeDatabase.memory() من drift يحتاج sqlite3 native library
// التي يجب تهيئتها عبر sqfliteFfiInit() قبل أي استخدام
// بدون هذا، تحدث segmentation faults على CI Ubuntu runners
//
// المرجع: https://github.com/simolus3/drift/issues/358

import 'dart:async';
import 'dart:io' show Directory;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // ✅ تهيئة SQLite FFI مرة واحدة قبل كل الاختبارات
  // هذا يمنع segmentation faults في drift/NativeDatabase.memory()
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // ✅ تهيئة SharedPreferences mock للاختبارات
  // عدة خدمات (AutoBackupManager, AppwriteConfigManager, etc.) تستدعي
  // SharedPreferences.getInstance() بدون try/catch، مما يسبب
  // MissingPluginException في الاختبارات التي لا تُهيِّئ الـ binding.
  // setMockInitialValues({}) يُسجّل mock channel يدعم GET/SET/REMOVE.
  // ignore: deprecated_member_use
  SharedPreferences.setMockInitialValues({});

  // ✅ Mock لـ path_provider — يُسجّل MethodChannel mock يُرجع مساراً مؤقتاً
  // هذا يمنع MissingPluginException عند استدعاء:
  //   - getApplicationDocumentsDirectory (يستخدمه Appwrite ClientIO._getCookiePath)
  //   - getTemporaryDirectory (يستخدمه Appwrite لـ cookie storage)
  //   - getApplicationSupportDirectory
  //
  // المشكلة كانت: اختبارات test/performance/ تُبنى شاشات حقيقية (DashboardScreen)
  // التي تستدعي AppwriteService في initState → ClientIO.init() → path_provider
  // بدون هذا الـ mock، تفشل الاختبارات بـ MissingPluginException على CI.
  //
  // نُرجع مساراً مؤقتاً حقيقياً (Directory.systemTemp.createTempSync) ليكون
  // قابلاً للكتابة في CI Linux runners.
  final tempDir = await Directory.systemTemp.createTemp('marina_test_');
  final tempPath = tempDir.path;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getTemporaryDirectory':
        case 'getApplicationSupportDirectory':
        case 'getLibraryDirectory':
        case 'getDownloadsDirectory':
          return tempPath;
        default:
          return null;
      }
    },
  );

  // ✅ Mock لـ package_info_plus — يمنع MissingPluginException عند استدعاء
  // PackageInfo.fromPlatform() الذي يستخدمه:
  //   - appVersionProvider (في dashboard_screen.dart)
  //   - CrashlyticsService (لتسجيل إصدار التطبيق)
  //   - PostHogService (لتتبع الإصدار)
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/package_info'),
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getAll':
          return <String, dynamic>{
            'appName': 'Marina Hotel Test',
            'packageName': 'com.aden.marina.test',
            'version': '1.0.0',
            'buildNumber': '1',
            'buildSignature': '',
            'installerStore': null,
          };
        default:
          return null;
      }
    },
  );

  await testMain();

  // ✅ تنظيف المجلد المؤقت بعد انتهاء جميع الاختبارات
  try {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  } catch (_) {
    // silent — cleanup is best-effort
  }
}
