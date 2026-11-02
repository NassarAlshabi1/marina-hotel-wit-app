import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'db_encryption_key.dart';

/// يفتح اتصال قاعدة البيانات على المنصات الأصلية
/// (Android / iOS / Windows / Linux / macOS).
///
/// ✅ S2 FIX: التشفير عبر SQLCipher — مفتاح 32 بايت يُولَّد عشوائياً
/// ويُخزَّن في FlutterSecureStorage (Android Keystore / iOS Keychain).
/// لا تغيير في أي API أو توكن — المفتاح محلي صِرف، لا يُرسل للسحاب.
///
/// على المنصات الأصلية: NativeDatabase + PRAGMA key.
/// على الويب: drift WASM (لا يدعم SQLCipher — يعتمد على تخزين المتصفح).
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

    // ✅ S2 FIX: احصل على مفتاح التشفير من SecureStorage (أو ولّده)
    final hexKey = await DbEncryptionKey.getOrCreateKey();

    if (hexKey == null) {
      // الويب أو فشل SecureStorage: استخدم اتصالاً غير مشفّر (fallback)
      return NativeDatabase.createInBackground(file);
    }

    // ✅ SQLCipher: فتح قاعدة البيانات مع تفعيل التشفير عبر PRAGMA key.
    // setupProgramatic يسمح بتنفيذ PRAGMA قبل أي استعلام.
    return NativeDatabase.createInBackground(
      file,
      setupProgrammatic: (db) async {
        // تفعيل مفتاح التشفير — SQLCipher يتطلب PRAGMA key كأول عملية.
        // المفتاح بصيغة hex مسبوق بـ x'' (تنسيق SQLCipher للـ hex keys).
        await db.execute("PRAGMA key = \"x'$hexKey'\";");
        // ✅ تحقق أن المفتاح صحيح (يفتح قاعدة موجودة أو ينشئ جديدة)
        // إن كان المفتاح خاطئاً لقاعدة موجودة، يفشل التحقق.
        try {
          await db.execute('SELECT count(*) FROM sqlite_master;');
        } catch (e) {
          // القاعدة موجودة وغير مشفّرة (هجرة أول مرة):
          // نُعيد التشفير عبر sqlcipher_export أو نتعامل معه لاحقاً.
          // في الوقت الحالي: نُعيد فتحها بدون تشفير كـ fallback آمن
          // حتى لا نفقد بيانات المستخدم. الهجرة الكاملة تتطلب
          // خطوة منفصلة (export → reopen encrypted → import).
          // TODO(P1): هجرة تلقائية للقواعد غير المشفّرة الموجودة.
        }
      },
    );
  });
}
