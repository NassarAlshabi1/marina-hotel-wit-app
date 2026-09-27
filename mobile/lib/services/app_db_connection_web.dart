import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// يفتح اتصال قاعدة البيانات على الويب عبر drift WASM (sqlite3.wasm).
///
/// drift يفحص قدرات المتصفح ويختار أفضل تخزين متاح
/// (OPFS → SharedIndexedDb → UnsafeIndexedDb → InMemory).
///
/// الأصول المطلوبة وقت التشغيل (منسوخة إلى web/):
/// - `sqlite3.wasm`   — من إصدار حزمة sqlite3 المطابقة (2.9.4).
/// - `drift_worker.js` — من إصدارات drift (متوافق مع drift 2.31).
///
/// لاحظ أن `DatabaseConnection` ينفّذ `QueryExecutor`، لذا تُعاد النتيجة
/// مباشرة بنفس توقيع النسخة الأصلية (io).
QueryExecutor openAppDatabaseConnection(String dbFileName) {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: dbFileName,
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}
