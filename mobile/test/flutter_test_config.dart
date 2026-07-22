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

  await testMain();
}
