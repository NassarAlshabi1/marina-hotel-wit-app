import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// يفتح اتصال قاعدة البيانات على المنصات الأصلية
/// (Android / iOS / Windows / Linux / macOS).
///
/// المنطق منقول حرفياً من `_open()` السابقة في local_db.dart — لا تغيير
/// سلوكي إطلاقاً على المنصات الأصلية؛ الفصل هنا فقط لتمكين الاستيراد
/// المشروط (web ↔ io) الذي يسمح ببناء PWA بدون dart:ffi.
QueryExecutor openAppDatabaseConnection(String dbFileName) {
  return LazyDatabase(() async {
    // ✅ دعم Windows/Linux/macOS عبر path_provider + sqflite_common_ffi
    // sqflite.getDatabasesPath() لا يعمل على Desktop (Android/iOS فقط)
    final Directory dbDir;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // على Desktop، استخدم ApplicationDocumentsPath
      final appDir = await getApplicationDocumentsDirectory();
      dbDir = appDir;
    } else {
      // على Mobile، استخدم sqflite path
      final sqfliteDir = await sqflite.getDatabasesPath();
      dbDir = Directory(sqfliteDir);
    }
    final file = File(p.join(dbDir.path, dbFileName));
    return NativeDatabase.createInBackground(file);
  });
}
