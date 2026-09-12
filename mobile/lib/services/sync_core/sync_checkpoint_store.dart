import 'package:drift/drift.dart' as drift;

import '../local_db.dart';

/// ✅ Unified Pull (2026-08-31): Checkpoint لكل مجموعة في جدول SQLite مخصص.
///
/// جدول `sync_checkpoints` يُنشأ عبر SQL خام (نفس نمط `sync_mirror` الموجود
/// في DeltaSyncService) — بدون الحاجة لإعادة توليد `local_db.g.dart`
/// (codegen) أو الاعتماد على دورة Drift كاملة.
///
/// **المشكلة التي يحلها**: كان المؤشر (checkpoint) عاماً واحداً لكل الجداول
/// (صف SyncState id=1) — أي تغيير في جدول نشط (مثل bookings) يحرّك المؤشر،
/// و`full_sync_complete` عام أيضاً: فشل مجموعة صغيرة يمنع تحديث المؤشر
/// نهائياً → دورة سحب كاملة لكل الجداول من جديد.
///
/// **الحل**: مؤشر مستقل لكل collection:
///   - أول تثبيت = Full pull لكل مجموعة (checkpoint = 0 / flag = 0).
///   - بعد نجاح سحب المجموعة = Delta فقط (`$updatedAt > checkpoint`).
///   - فشل مجموعة لا يؤثر على مؤشرات المجموعات الأخرى.
///   - الجدول الساكن = صفر سجلات مسحوبة (استعلام فارغ رخيص فقط).
class SyncCheckpointStore {
  SyncCheckpointStore(this.db);

  final AppDatabase db;

  bool _tableReady = false;

  /// اسم الجدول المخصص.
  static const String tableName = 'sync_checkpoints';

  Future<void> _ensureTable() async {
    if (_tableReady) return;
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS $tableName ('
      'collection_name TEXT NOT NULL PRIMARY KEY, '
      'last_pull_ts INTEGER NOT NULL DEFAULT 0, '
      'full_sync_complete INTEGER NOT NULL DEFAULT 0, '
      'updated_at INTEGER NOT NULL DEFAULT 0'
      ')',
    );
    _tableReady = true;
  }

  /// يقرأ آخر timestamp لسحب المجموعة (بالثواني).
  ///
  /// يعيد 0 إذا لم يوجد checkpoint (أول تثبيت → Full pull).
  Future<int> getLastPullTs(String collectionName) async {
    await _ensureTable();
    try {
      final rows = await db
          .customSelect(
            'SELECT last_pull_ts FROM $tableName WHERE collection_name = ?',
            variables: [drift.Variable.withString(collectionName)],
          )
          .get();
      if (rows.isEmpty) return 0;
      final ts = rows.first.read<int>('last_pull_ts');
      // تطبيع دفاعي: لو خُزّنت القيمة بالميلي ثانية نحوّلها للثواني.
      return ts > 10000000000 ? ts ~/ 1000 : ts;
    } catch (_) {
      // فشل القراءة → 0 = Full pull (سلوك آمن تحفظي).
      return 0;
    }
  }

  /// يحدّث آخر timestamp لسحب المجموعة (بالثواني — سلطة الخادم max($updatedAt)).
  ///
  /// يضع full_sync_complete = 1 ضمنياً (السحب نجح → المجموعة خرجت من bootstrap).
  Future<void> setLastPullTs(String collectionName, int ts) async {
    await _ensureTable();
    await db.customStatement(
      'INSERT INTO $tableName '
      '(collection_name, last_pull_ts, full_sync_complete, updated_at) '
      'VALUES (?, ?, 1, ?) '
      'ON CONFLICT(collection_name) DO UPDATE SET '
      'last_pull_ts = excluded.last_pull_ts, '
      'full_sync_complete = 1, updated_at = excluded.updated_at',
      [collectionName, ts, _nowSec()],
    );
  }

  /// هل اكتمل أول Full Sync لهذه المجموعة؟
  ///
  /// false → المجموعة في وضع bootstrap ويُجبر Full pull لها فقط
  /// (بدل إجبار كل الجداول كما كان يحدث مع العلامة العامة).
  Future<bool> isFullSyncComplete(String collectionName) async {
    await _ensureTable();
    try {
      final rows = await db
          .customSelect(
            'SELECT full_sync_complete FROM $tableName '
            'WHERE collection_name = ?',
            variables: [drift.Variable.withString(collectionName)],
          )
          .get();
      if (rows.isEmpty) return false;
      return rows.first.read<int>('full_sync_complete') == 1;
    } catch (_) {
      // تحفظياً: نُجبر Full sync عند عدم القدرة على القراءة.
      return false;
    }
  }

  /// يضع علامة اكتمال أول Full Sync للمجموعة (idempotent — يحافظ على المؤشر).
  Future<void> markFullSyncComplete(String collectionName) async {
    await _ensureTable();
    await db.customStatement(
      'INSERT INTO $tableName '
      '(collection_name, last_pull_ts, full_sync_complete, updated_at) '
      'VALUES (?, 0, 1, ?) '
      'ON CONFLICT(collection_name) DO UPDATE SET '
      'full_sync_complete = 1, updated_at = excluded.updated_at',
      [collectionName, _nowSec()],
    );
  }

  /// يعيد ضبط checkpoint المجموعة (Full sync مطلوب لها في الدورة القادمة).
  ///
  /// يُستدعى عند: فشل متكرر، استعادة نسخة احتياطية، أو اكتشاف عدم تطابق schema.
  Future<void> reset(String collectionName) async {
    await _ensureTable();
    await db.customStatement(
      'UPDATE $tableName SET last_pull_ts = 0, full_sync_complete = 0, '
      'updated_at = ? WHERE collection_name = ?',
      [_nowSec(), collectionName],
    );
  }

  /// يعيد ضبط كل المجموعات (مثلاً: تسجيل خروج + دخول بمستخدم جديد).
  Future<void> resetAll() async {
    await _ensureTable();
    await db.customStatement('DELETE FROM $tableName');
  }

  int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
