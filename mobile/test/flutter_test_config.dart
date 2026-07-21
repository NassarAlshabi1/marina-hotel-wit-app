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

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // ✅ تهيئة SQLite FFI مرة واحدة قبل كل الاختبارات
  // هذا يمنع segmentation faults في drift/NativeDatabase.memory()
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // إخفاء تحذيرات overflow في الـ logs (غير حرجة في CI)
  // Flutter.binding.deferFirstFrame = true;

  await testMain();
}
