// lib/services/sync_core/deferred_relation_store.dart
//
// ✅ (G-3 / البند 6 — تدقيق الهوية المالية 2026-10-06): مخزن السجلات
// «ناقصة الربط» (relation-incomplete).
//
// **المشكلة التي يحلها**:
//   كان السجل الذي يصل من مزوّد المزامنة قبل «أبيه» (موظف/حجز/دورة راتب)
//   يُتخطّى **ويُهمَل** بعد محاولة داخل نفس الدورة فقط. وبما أن مؤشر السحب
//   يتقدّم بعد نجاح الدورة، لا يُعاد طلب السجل أبداً ⇒ **فقدان صامت** لحركة
//   مالية (سحب راتب/دورة/دفعة)، أو — الأسوأ — ربطه بموظف آخر عبر مطابقة
//   رقم محلي من جهاز مختلف (G-3).
//
// **الحل الهندسي**:
//   - لا حذف ولا ربط تخميني: كل سجل لا يمكن إثبات مرجعه يُخزَّن هنا
//     **كحمولة JSON محايدة المزوّد** (بنفس شكل Drive/Appwrite الذي تفهمه
//     المحوّلات) مع دليل التشخيص: الجهاز الكاتب، المعرّف الرقمي البعيد،
//     وسبب التعليق.
//   - طبقة المجال (`DeferredRelationRelinker`) تعيد تطبيق الحمولات عبر
//     `AdapterRegistry` — أي عبر **نفس مسار المزامنة الرسمي** — بمجرد
//     وصول الأب، والربط **بـ UUID فقط**.
//   - كل صف يظهر في تقرير المراجعة القابل للتصدير (G-8) حتى لا تضيع
//     أي حركة بصمت.
//
// **لماذا جدول SQL خام وليس كيان Drift؟**
//   نفس نمط `sync_checkpoints` المعتمد في هذا المشروع: جدول بنيوي بسيط
//   يُدار بـ SQL مُعتَمَد (CREATE TABLE IF NOT EXISTS) فلا يحتاج إعادة
//   توليد `local_db.g.dart` ولا دورة codegen — والتغيير additive بحت.
//
// ⚠️ هذا المخزن **لا يعدّل أي سجل مالي** — ينقل حمولات لم تُطبَّق بعد،
//    ويُعلّم حالتها. لا تخمين ولا إصلاح تاريخي (البند 12).
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../utils/app_logger.dart';
import '../../utils/time.dart';
import '../local_db.dart';

/// حالات صف التعليق.
enum DeferredRelationState {
  /// ينتظر وصول الأب — تُعاد المحاولة كل دورة.
  pending('pending'),

  /// استُنفدت المحاولات أو أن الأب مفقود بطريقة لا تُحل آلياً — للمراجعة
  /// البشرية في التقرير (لا حذف، ولا ربط تخميني).
  needsReview('needs_review'),

  /// طُبِّق السجل بنجاح بعد وصول الأب.
  resolved('resolved'),

  /// حمولة لا يعرفها هذا الإصدار (مجموعة غير مدعومة) — للمراجعة أيضاً.
  unsupported('unsupported');

  const DeferredRelationState(this.value);
  final String value;
}

/// صف مُعلَّق واحد.
class DeferredRelationRow {
  const DeferredRelationRow({
    required this.id,
    required this.collection,
    required this.localUuid,
    required this.source,
    required this.payloadJson,
    required this.state,
    required this.attempts,
    required this.firstSeenAt,
    this.reason,
    this.missingParent,
    this.parentUuid,
    this.remoteParentId,
    this.sourceDeviceId,
    this.lastAttemptAt,
    this.resolvedAt,
  });

  final int id;
  final String collection;
  final String localUuid;

  /// 'appwrite' أو 'drive' (تحدد صيغة المفاتيح كما تفهمها المحوّلات).
  final String source;
  final String payloadJson;
  final DeferredRelationState state;
  final int attempts;
  final int firstSeenAt;
  final String? reason;

  /// اسم العلاقة المعلّقة: 'employee' / 'booking' / 'salary_cycle'.
  final String? missingParent;
  final String? parentUuid;

  /// المعرّف الرقمي البعيد (مقيّد بجهاز المصدر) — **دليل للمراجعة**،
  /// لا يُستخدم للربط التلقائي.
  final int? remoteParentId;
  final String? sourceDeviceId;
  final int? lastAttemptAt;
  final int? resolvedAt;

  Map<String, dynamic> get payload =>
      (jsonDecode(payloadJson) as Map).cast<String, dynamic>();
}

class DeferredRelationStore {
  DeferredRelationStore(this.db);

  final AppDatabase db;

  /// اسم الجدول (نفس نمط sync_checkpoints).
  static const String tableName = 'deferred_relations';

  /// الحد الأقصى للمحاولات قبل تحويل الصف إلى «للمراجعة» (لا يُحذف).
  static const int maxAttempts = 25;

  bool _ready = false;

  Future<void> _ensureTable() async {
    if (_ready) return;
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS $tableName ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'collection_name TEXT NOT NULL, '
      'local_uuid TEXT NOT NULL, '
      'source TEXT NOT NULL DEFAULT \'appwrite\', '
      'payload_json TEXT NOT NULL, '
      'reason TEXT, '
      'missing_parent TEXT, '
      'parent_uuid TEXT, '
      'remote_parent_id INTEGER, '
      'source_device_id TEXT, '
      'attempts INTEGER NOT NULL DEFAULT 0, '
      'first_seen_at INTEGER NOT NULL DEFAULT 0, '
      'last_attempt_at INTEGER, '
      'state TEXT NOT NULL DEFAULT \'pending\', '
      'resolved_at INTEGER, '
      'UNIQUE(collection_name, local_uuid)'
      ')',
    );
    await _try(
      'CREATE INDEX IF NOT EXISTS idx_deferred_relations_state '
      'ON $tableName (state, missing_parent)',
    );
    _ready = true;
  }

  Future<void> _try(String sql) async {
    try {
      await db.customStatement(sql);
    } catch (_) {
      // فشل غير حرج (فهرس موجود/نسخة أقدم) — لا يوقف المزامنة.
    }
  }

  /// يُسجّل سجلاً «ناقص الربط». عملية idempotent بالمفتاح
  /// (collection, local_uuid): لا تُنشئ صفوفاً مكررة، ولا تُحيي صفاً
  /// حُلّ سابقاً (تجنّب ضجيج وإعادة تطبيق خطِرة).
  ///
  /// لا ترمي استثناء أبداً — فشل التعليق لا يجوز أن يُسقط دورة سحب.
  Future<bool> defer({
    required String collection,
    required String localUuid,
    required Map<String, dynamic> payload,
    required String source,
    String? reason,
    String? missingParent,
    String? parentUuid,
    int? remoteParentId,
    String? sourceDeviceId,
  }) async {
    if (collection.isEmpty || localUuid.isEmpty) return false;
    try {
      await _ensureTable();
      final existing = await db
          .customSelect(
            'SELECT id, state FROM $tableName '
            'WHERE collection_name = ? AND local_uuid = ? LIMIT 1',
            variables: [
              Variable.withString(collection),
              Variable.withString(localUuid),
            ],
          )
          .getSingleOrNull();

      final now = Time.nowEpoch();
      if (existing == null) {
        await db.customStatement(
          'INSERT INTO $tableName (collection_name, local_uuid, source, '
          'payload_json, reason, missing_parent, parent_uuid, '
          'remote_parent_id, source_device_id, attempts, first_seen_at, '
          'state) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)',
          [
            collection,
            localUuid,
            source,
            jsonEncode(payload),
            reason,
            missingParent,
            parentUuid,
            remoteParentId,
            sourceDeviceId,
            now,
            DeferredRelationState.pending.value,
          ],
        );
        AppLogger.info(
          '⏳ تعليق $collection/$localUuid — علاقة غير محلولة '
          '(${missingParent ?? '?'}) بلا ربط تخميني؛ سيُعاد الربط عبر UUID.',
          tag: 'DEFERRED_RELATIONS',
        );
        return true;
      }

      final state = existing.read<String>('state');
      if (state == DeferredRelationState.resolved.value) {
        // حُلّ سابقاً ⇒ لا نُحييه: وجوده مرة أخرى يعني أن الأب أُخفي
        // لاحقاً؛ إعادة التعليق تفسد السجل المطبَّق فعلاً.
        return false;
      }
      await db.customStatement(
        'UPDATE $tableName SET payload_json = ?, reason = ?, '
        'source_device_id = COALESCE(?, source_device_id), '
        'remote_parent_id = COALESCE(?, remote_parent_id), '
        'parent_uuid = COALESCE(?, parent_uuid), state = ? WHERE id = ?',
        [
          jsonEncode(payload),
          reason,
          sourceDeviceId,
          remoteParentId,
          parentUuid,
          DeferredRelationState.pending.value,
          existing.read<int>('id'),
        ],
      );
      return false;
    } catch (e) {
      AppLogger.warning(
        'تعذّر تعليق $collection/$localUuid (لن تُسقط المزامنة): $e',
        tag: 'DEFERRED_RELATIONS',
      );
      return false;
    }
  }

  /// الصفوف التي تستحق إعادة محاولة الآن (pending وعدد محاولاتها < الحد).
  Future<List<DeferredRelationRow>> retryable({int limit = 200}) async {
    await _ensureTable();
    final rows = await db
        .customSelect(
          'SELECT * FROM $tableName WHERE state = ? AND attempts < ? '
          'ORDER BY first_seen_at ASC LIMIT ?',
          variables: [
            Variable.withString(DeferredRelationState.pending.value),
            Variable.withInt(maxAttempts),
            Variable.withInt(limit),
          ],
        )
        .get();
    return rows.map(_row).toList();
  }

  /// كل الصفوف (للتقرير) — مع إمكانية تحديد الحالات المطلوبة.
  Future<List<DeferredRelationRow>> all({
    Set<DeferredRelationState>? states,
    int limit = 2000,
  }) async {
    await _ensureTable();
    final rows = await db
        .customSelect(
          'SELECT * FROM $tableName ORDER BY '
          "CASE state WHEN 'pending' THEN 0 WHEN 'needs_review' THEN 1 "
          'WHEN \'unsupported\' THEN 2 ELSE 3 END, first_seen_at ASC LIMIT ?',
          variables: [Variable.withInt(limit)],
        )
        .get();
    final mapped = rows.map(_row).toList();
    if (states == null) return mapped;
    return mapped.where((r) => states.contains(r.state)).toList();
  }

  Future<void> markResolved(int id) async {
    await _ensureTable();
    await db.customStatement(
      'UPDATE $tableName SET state = ?, resolved_at = ?, '
      'last_attempt_at = ? WHERE id = ?',
      [
        DeferredRelationState.resolved.value,
        Time.nowEpoch(),
        Time.nowEpoch(),
        id,
      ],
    );
  }

  /// محاولة فاشلة: يزيد العدّاد، ويحدّث الحالة (تُحسب في طبقة المجال —
  /// لا CASE في SQL). لا حذف أبداً: الصف يبقى للربط أو للمراجعة.
  Future<void> markAttemptFailed(
    int id, {
    String? reason,
    DeferredRelationState? forceState,
  }) async {
    await _ensureTable();
    await db.customStatement(
      'UPDATE $tableName SET attempts = attempts + 1, last_attempt_at = ?, '
      'reason = COALESCE(?, reason), state = ? WHERE id = ?',
      [
        Time.nowEpoch(),
        reason,
        (forceState ?? DeferredRelationState.pending).value,
        id,
      ],
    );
  }

  /// الحالة التالية بعد محاولة فاشلة (منطق المجال — قابل للاختبار).
  static DeferredRelationState nextStateAfterFailure({
    required int attempts,
    DeferredRelationState? forceState,
  }) {
    if (forceState != null) return forceState;
    if (attempts + 1 >= maxAttempts) return DeferredRelationState.needsReview;
    return DeferredRelationState.pending;
  }

  /// يُعيد تفعيل صفوف «للمراجعة» المرتبطة بأب وصل حديثاً.
  /// مثال: بعد سحب الموظفين ⇒ كل ما ينتظر علاقة 'employee' يُعاد فوراً
  /// لمحاولة الربط عبر UUID. (البيانات موجودة أصلاً — لا حذف ولا تعديل
  /// لأي مبلغ.)
  Future<int> rearmForParent(String parent) async {
    await _ensureTable();
    try {
      final before = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM $tableName WHERE missing_parent = ? '
            'AND state IN (?, ?)',
            variables: [
              Variable.withString(parent),
              Variable.withString(DeferredRelationState.needsReview.value),
              Variable.withString(DeferredRelationState.unsupported.value),
            ],
          )
          .getSingle();
      final count = before.read<int>('c');
      if (count == 0) return 0;
      await db.customStatement(
        'UPDATE $tableName SET state = ?, attempts = 0 '
        'WHERE missing_parent = ? AND state IN (?, ?)',
        [
          DeferredRelationState.pending.value,
          parent,
          DeferredRelationState.needsReview.value,
          DeferredRelationState.unsupported.value,
        ],
      );
      AppLogger.info(
        '🔁 أعيد تفعيل $count سجلاً معلّقاً على «$parent» بعد وصول بيانات جديدة.',
        tag: 'DEFERRED_RELATIONS',
      );
      return count;
    } catch (e) {
      AppLogger.warning(
        'تعذّر إعادة تفعيل المعلّقات على $parent: $e',
        tag: 'DEFERRED_RELATIONS',
      );
      return 0;
    }
  }

  /// ملخص عددي للتقرير.
  Future<Map<String, int>> summary() async {
    await _ensureTable();
    final rows = await db
        .customSelect(
          'SELECT state, COUNT(*) AS c FROM $tableName GROUP BY state',
        )
        .get();
    return {
      for (final row in rows) row.read<String>('state'): row.read<int>('c'),
    };
  }

  /// تنظيف الصفوف المحلولة القديمة (صيانة فقط — لا يمسّ المعلّق).
  Future<int> purgeResolved({int olderThanEpoch = 0}) async {
    await _ensureTable();
    try {
      final count = db.customSelect(
        'SELECT COUNT(*) AS c FROM $tableName WHERE state = ? '
        'AND COALESCE(resolved_at, 0) >= ?',
        variables: [
          Variable.withString(DeferredRelationState.resolved.value),
          Variable.withInt(olderThanEpoch),
        ],
      );
      final value = count.getSingle();
      await db.customStatement(
        'DELETE FROM $tableName WHERE state = ? AND COALESCE(resolved_at, 0) '
        '>= ?',
        [
          Variable.withString(DeferredRelationState.resolved.value),
          Variable.withInt(olderThanEpoch),
        ],
      );
      return (await value).read<int>('c');
    } catch (e) {
      AppLogger.warning(
        'تعذّر تنظيف المعلّقات المحلولة: $e',
        tag: 'DEFERRED_RELATIONS',
      );
      return 0;
    }
  }

  DeferredRelationRow _row(QueryRow row) => DeferredRelationRow(
    id: row.read<int>('id'),
    collection: row.read<String>('collection_name'),
    localUuid: row.read<String>('local_uuid'),
    source: row.read<String>('source'),
    payloadJson: row.read<String>('payload_json'),
    state: _stateOf(row.read<String>('state')),
    attempts: row.read<int>('attempts'),
    firstSeenAt: row.read<int>('first_seen_at'),
    reason: row.data['reason'] as String?,
    missingParent: row.data['missing_parent'] as String?,
    parentUuid: row.data['parent_uuid'] as String?,
    remoteParentId: (row.data['remote_parent_id'] as num?)?.toInt(),
    sourceDeviceId: row.data['source_device_id'] as String?,
    lastAttemptAt: (row.data['last_attempt_at'] as num?)?.toInt(),
    resolvedAt: (row.data['resolved_at'] as num?)?.toInt(),
  );

  static DeferredRelationState _stateOf(String value) {
    for (final state in DeferredRelationState.values) {
      if (state.value == value) return state;
    }
    return DeferredRelationState.pending;
  }
}
