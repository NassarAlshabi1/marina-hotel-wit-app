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
///
/// ✅ Resumable Full Sync (2026-09-21): عمودان جديدان يجعلان السحب الكامل
/// قابلاً للاستئناف صفحة-بصفحة دون فقدان بيانات:
///   - `full_sync_cursor` — آخر `$id` تم **تطبيقه محلياً** بنجاح. عند استئناف
///     دورة سحب (بعد انقطاع إنترنت/قتل التطبيق/نفاد المهلة) نكمل من
///     `cursorAfter($id)` بدل البدء من الصفر.
///   - `full_sync_max_updated` — أقصى `$updatedAt` شوهد خلال السحب الكامل
///     الجاري؛ يُثبَّت كمؤشر Delta نهائي **فقط عند اكتمال السحب** (نفاد
///     المستندات)، لا عند أول سقف جزئي.
///
///   المشكلة القديمة (P0): السقف الجزئي (مثلاً 1000 لـ booking_nights) كان
///   يُثبّت checkpoint من أول 1000 سجل بأقدم `$id` ثم `full_sync_complete=1`
///   → كل الدورات اللاحقة Delta فقط → السجلات الأقدم من المؤشر لا تُسحب
///   أبداً → فقدان صامت لليالي التاريخية (فندق 20 غرفة × سنة ≈ 7000 ليلة).
///   الحل: المؤشر لا يُثبّت إلا عند النفاد الفعلي للمستندات.
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
      'full_sync_cursor TEXT, '
      'full_sync_max_updated INTEGER NOT NULL DEFAULT 0, '
      'updated_at INTEGER NOT NULL DEFAULT 0'
      ')',
    );
    // ✅ ترقية التثبيتات القائمة: CREATE TABLE IF NOT EXISTS لا يضيف أعمدة
    // لجدول موجود — ننفّذ ALTER محمية (فشل "duplicate column" = مضافة سلفاً).
    await _tryAlter('ALTER TABLE $tableName ADD COLUMN full_sync_cursor TEXT');
    await _tryAlter(
      'ALTER TABLE $tableName ADD COLUMN full_sync_max_updated INTEGER '
      'NOT NULL DEFAULT 0',
    );
    _tableReady = true;
  }

  Future<void> _tryAlter(String sql) async {
    try {
      await db.customStatement(sql);
    } catch (_) {
      // العمود موجود سلفاً — ترقية idempotent.
    }
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

  // ─────────────────────────────────────────────────────────────────────
  // ✅ Resumable Full Sync (2026-09-21) — مؤشر تقدّم السحب الكامل الجاري.
  // ─────────────────────────────────────────────────────────────────────

  /// آخر `$id` تم تطبيقه بنجاح في السحب الكامل الجاري (null = لم يبدأ).
  ///
  /// يُقرأ من [UnifiedPullEngine.plan] لاستئناف السحب من حيث توقف:
  /// `cursorAfter($id)` بدل إعادة سحب كل الصفحات السابقة.
  Future<String?> getFullSyncCursor(String collectionName) async {
    await _ensureTable();
    try {
      final rows = await db
          .customSelect(
            'SELECT full_sync_cursor FROM $tableName WHERE collection_name = ?',
            variables: [drift.Variable.withString(collectionName)],
          )
          .get();
      if (rows.isEmpty) return null;
      final raw = rows.first.data['full_sync_cursor'];
      if (raw == null) return null;
      final cursor = raw.toString();
      if (cursor.isEmpty) return null;
      return cursor;
    } catch (_) {
      return null;
    }
  }

  /// يثبّت مؤشر التقدّم بعد نجاح تطبيق صفحة كاملة (crash-safe).
  ///
  /// لا يُستدعى إلا بعد نجاح [CollectionPullTask.apply] للصفحة — إذا انهار
  /// التطبيق بعدها، الاستئناف يبدأ من هذه الصفحة بالضبط فلا صفحة مفقودة
  /// ولا إعادة عمل كبيرة (الـ upsert idempotent على أي حال).
  Future<void> setFullSyncCursor(
    String collectionName,
    String cursor,
  ) async {
    await _ensureTable();
    await db.customStatement(
      'INSERT INTO $tableName '
      '(collection_name, last_pull_ts, full_sync_complete, '
      'full_sync_cursor, full_sync_max_updated, updated_at) '
      'VALUES (?, 0, 0, ?, 0, ?) '
      'ON CONFLICT(collection_name) DO UPDATE SET '
      'full_sync_cursor = excluded.full_sync_cursor, '
      'updated_at = excluded.updated_at',
      [collectionName, cursor, _nowSec()],
    );
  }

  /// يرفع أقصى `$updatedAt` مُشاهد خلال السحب الكامل الجاري (monotonic).
  Future<void> bumpFullSyncMaxUpdated(
    String collectionName,
    int maxUpdatedSec,
  ) async {
    await _ensureTable();
    await db.customStatement(
      'INSERT INTO $tableName '
      '(collection_name, last_pull_ts, full_sync_complete, '
      'full_sync_cursor, full_sync_max_updated, updated_at) '
      'VALUES (?, 0, 0, NULL, ?, ?) '
      'ON CONFLICT(collection_name) DO UPDATE SET '
      'full_sync_max_updated = MAX(full_sync_max_updated, excluded.full_sync_max_updated), '
      'updated_at = excluded.updated_at',
      [collectionName, maxUpdatedSec, _nowSec()],
    );
  }

  /// أقصى `$updatedAt` مُسجّل خلال السحب الكامل الجاري (0 = لا شيء بعد).
  Future<int> getFullSyncMaxUpdated(String collectionName) async {
    await _ensureTable();
    try {
      final rows = await db
          .customSelect(
            'SELECT full_sync_max_updated FROM $tableName '
            'WHERE collection_name = ?',
            variables: [drift.Variable.withString(collectionName)],
          )
          .get();
      if (rows.isEmpty) return 0;
      return rows.first.read<int>('full_sync_max_updated');
    } catch (_) {
      return 0;
    }
  }

  /// يمسح حالة التقدّم (المؤشر + الأقصى) دون لمس last_pull_ts/complete.
  Future<void> clearFullSyncProgress(String collectionName) async {
    await _ensureTable();
    await db.customStatement(
      'UPDATE $tableName SET full_sync_cursor = NULL, full_sync_max_updated = 0, '
      'updated_at = ? WHERE collection_name = ?',
      [_nowSec(), collectionName],
    );
  }

  /// يُنهي السحب الكامل: يثبّت مؤشر Delta من أقصى `$updatedAt` مُشاهد ويُعلن
  /// الاكتمال ويمسح حالة التقدّم.
  ///
  /// إذا كان `maxUpdatedSec <= 0` (لا مستندات أو $updatedAt غير قابل للقراءة
  /// في كل الصفحات) نُعلن الاكتمال فقط دون مؤشر — الدورة التالية ترى
  /// `sinceTs <= 0` فتُعيد وضع Full (استعلام فارغ رخيص) — نفس دلالات
  /// [commit] القديمة للمجموعة الفارغة.
  Future<void> completeFullSync(
    String collectionName, {
    required int maxUpdatedSec,
  }) async {
    await _ensureTable();
    if (maxUpdatedSec > 0) {
      await db.customStatement(
        'UPDATE $tableName SET '
        'last_pull_ts = ?, full_sync_complete = 1, '
        'full_sync_cursor = NULL, full_sync_max_updated = 0, updated_at = ? '
        'WHERE collection_name = ?',
        [maxUpdatedSec, _nowSec(), collectionName],
      );
    } else {
      await db.customStatement(
        'UPDATE $tableName SET '
        'full_sync_complete = 1, full_sync_cursor = NULL, '
        'full_sync_max_updated = 0, updated_at = ? '
        'WHERE collection_name = ?',
        [_nowSec(), collectionName],
      );
    }
  }

  /// يعيد ضبط checkpoint المجموعة (Full sync مطلوب لها في الدورة القادمة).
  ///
  /// يُستدعى عند: فشل متكرر، استعادة نسخة احتياطية، أو اكتشاف عدم تطابق schema.
  /// يمسح أيضاً حالة التقدّم القابلة للاستئناف (cursor/max) — دورة Full
  /// القادمة تبدأ من الصفر فعلاً.
  Future<void> reset(String collectionName) async {
    await _ensureTable();
    await db.customStatement(
      'UPDATE $tableName SET last_pull_ts = 0, full_sync_complete = 0, '
      'full_sync_cursor = NULL, full_sync_max_updated = 0, '
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
