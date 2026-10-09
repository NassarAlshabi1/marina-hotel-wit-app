// ══════════════════════════════════════════════════════════════════
//  payload_normalizer.dart — Cloudflare D1 wire contract normalizer
//
//  AUDIT 2026-09-05 (FIELD_TYPE_MATCH_AUDIT): the worker accepts ONLY
//  snake_case payload keys — it filters them against the actual D1
//  columns via PRAGMA table_info (worker/src/database.ts:346) with NO
//  camelCase→snake conversion, and resolves record identity through
//  data.local_uuid (worker/src/sync.ts:60 requireEntityId).
//
//  Outbox payloads, however, were historically built for Appwrite
//  documents (camelCase via toJsonForSource(Source.appwrite) or manual
//  camel maps) — those keys were silently dropped on push: creates
//  became empty rows with random uuids, updates matched nothing.
//
//  This normalizer enforces the contract at the single push boundary
//  (CloudflareSyncManager._pushBatch):
//    1. top-level keys camelCase → snake_case (idempotent),
//    2. Dart bool → INTEGER (0/1) — D1 rejects JS booleans on bind,
//    3. identity: outbox.local_uuid injected when the payload lacks it
//       (thin soft-delete payloads like {'id': 42} — requireEntityId
//       rejects numeric ids),
//    4. vector clock: carried from the entity row (the authoritative
//       clock lives there — OutboxDao._bumpVectorClockForLocalWrite
//       updates the TABLE, not the payload).
//
//  Values are passed through verbatim: JSON strings and nested lists
//  are DATA (e.g. applied_adjustments_json) whose inner camelCase keys
//  must be preserved — only column names are normalized.
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';

import '../local_db.dart';

class PayloadNormalizer {
  PayloadNormalizer._();

  static final RegExp _camelBoundary = RegExp('([a-z0-9])([A-Z])');
  static final RegExp _hasUpper = RegExp('[A-Z]');

  /// camelCase → snake_case, idempotent for keys already snake_case.
  ///
  /// localUuid → local_uuid, hotelDayKey → hotel_day_key,
  /// idempotencyKey → idempotency_key, local_uuid → local_uuid.
  ///
  /// الحد يوضع بين صغير/رقم وكبير فقط — `employeeId` يعطي `employee_id`
  /// (وليس `employee_i_d`) لأن I في Id يليها صغير، والقاعدة
  /// `([a-z0-9])([A-Z])` تلتقط المفصل الصحيح بين الكلمات.
  static String toSnakeCase(String key) {
    // Already normalized (no uppercase) — common case, return as-is.
    if (!_hasUpper.hasMatch(key)) return key;
    return key
        .replaceAllMapped(_camelBoundary, (m) => '${m.group(1)}_${m.group(2)}')
        .toLowerCase();
  }

  /// Normalizes an outbox payload map to the D1 wire contract.
  ///
  /// Returns a NEW map; the input is not mutated. Top-level only —
  /// nested values are data payloads, not column names (see header).
  static Map<String, dynamic> normalize(Map<String, dynamic> payload) {
    final out = <String, dynamic>{};
    payload.forEach((key, value) {
      out[toSnakeCase(key)] = _normalizeValue(value);
    });
    // ✅ تكافؤ `SyncEpochs.normalizeOutgoingEpochFields` (أندرويد): وحدة
    // الطوابع تُطبَّق عند نقطة الدفع نفسها، بعد توحيد الأسماء والأنواع.
    normalizeEpochFields(out);
    return out;
  }

  /// أعمدة الطابع الستة على السلك — نظير `SyncEpochs.WIRE_EPOCH_FIELDS`
  /// في أندرويد بنفس الأسماء.
  static const Set<String> wireEpochFields = {
    'created_at',
    'updated_at',
    'deleted_at',
    'last_modified',
    'created_at_epoch',
    'last_modified_epoch',
  };

  /// العتبة الفاصلة بين الثواني والميلي — `SyncEpochs.MILLIS_THRESHOLD`
  /// و`Database.MS_TIMESTAMP_THRESHOLD` في الطرفين: 1e11.
  static const int millisThreshold = 100000000000;

  /// يحوّل أي طابع ميلي في [wireEpochFields] إلى ثوانٍ (÷1000).
  ///
  /// لماذا: الـWorker ينسخ `last_modified` الوارد حرفياً (`createRecord`)
  /// ويقارنه عندنا وعند بقية الأجهزة بثوانيها — طابع ميلي يُخزَّن كما هو
  /// فيربح «الأحدث يفوز» على كل جهاز بلا سبب زمني حقيقي.
  ///
  /// ما لا يُلمس: القيم ≤ 1e11، والغائبة، والنصوص غير الرقمية —
  /// لا نُخمّن مكان غياب معلومة (سلوك `isMillisLike` نفسه).
  static void normalizeEpochFields(Map<String, dynamic> data) {
    for (final field in wireEpochFields) {
      final raw = data[field];
      final int? asInt = switch (raw) {
        final int v => v,
        final double v => v.truncate(),
        final String v => int.tryParse(v.trim()),
        _ => null,
      };
      if (asInt == null || asInt <= millisThreshold) continue;
      data[field] = asInt ~/ 1000;
    }
  }

  /// bool → int (D1/SQLite INTEGER affinity; Workers D1 rejects booleans).
  /// Every other value passes through untouched.
  static Object? _normalizeValue(Object? value) {
    if (value is bool) return value ? 1 : 0;
    return value;
  }
}

/// Signature of the entity-row vector-clock resolver — implemented by
/// CloudflareSyncManager against the local Drift database.
typedef RowVectorClockResolver =
    Future<String?> Function(String entity, String localUuid);

/// Builds ONE worker push operation from an outbox item, enforcing the
/// D1 wire contract (see file header). Used by _pushBatch; exposed for
/// the contract guard tests that run real DAO/repository producers.
Future<Map<String, dynamic>> buildPushOperation(
  OutboxData item, {
  required RowVectorClockResolver resolveRowVectorClock,
  String? deviceId,
}) async {
  final data = PayloadNormalizer.normalize(
    jsonDecode(item.payload) as Map<String, dynamic>,
  );
  final entity = canonicalEntity(item.entity);
  final operation = mapOperation(item.op);

  // ✅ عقد الهوية: صف outbox يحمل local_uuid دائماً (OutboxDao.merge
  // required localUuid) — الحمولات الرقيقة (soft-deletes `{'id': n}`)
  // لا تحمله، و requireEntityId يرمي على id الرقمي → validation_error.
  // يُحقن أيضاً إن كان نصّاً فارغاً (سلوك Android: `isNullOrBlank`).
  final localUuid = data['local_uuid'];
  if (localUuid is! String || localUuid.trim().isEmpty) {
    data['local_uuid'] = item.localUuid;
  }

  // ✅ تكافؤ `PushWireContract.buildOperation`: مسار الفصل الصريح لربط
  // الموظف (مصروف راتب تحوّل إلى مصروف بغير موظف) يُبلَّغ بعلامة
  // `clear_employee_link=1` — والـWorker يترجمها إلى
  // `employee_uuid=NULL + employee_link_cleared=1`.
  // الفارغ الغائب (null) أو وجود الكيان/العملية غيرهما لا يمسح الربط أبداً.
  if (entity == 'expenses' && operation == 'update') {
    final employeeUuid = data['employee_uuid'];
    if (employeeUuid is String && employeeUuid.trim().isEmpty) {
      data.remove('employee_uuid');
      data['clear_employee_link'] = 1;
    }
  }

  // ✅ عقد ساعة المتجه: authoritative clock يعيش على صف الكيان
  // (OutboxDao._bumpVectorClockForLocalWrite يحدّث الجدول لا الحمولة).
  // إرسال '{}' كان يجبر الـ worker على تهيئة ساعة جديدة وفقدان التاريخ.
  // ترتيب المصادر: الحمولة (إن كانت نصّاً غير فارغ) ← صف الكيان ← '{}'
  // (Android لا يملك مصدراً ثالثاً: حمولة، وإلا '{}').
  final rawVectorClock = data['vector_clock'];
  final vectorClock =
      (rawVectorClock is String && rawVectorClock.trim().isNotEmpty)
      ? rawVectorClock
      : await resolveRowVectorClock(item.entity, item.localUuid) ?? '{}';
  data['vector_clock'] = vectorClock;

  return <String, dynamic>{
    'idempotencyKey': switch (item.idempotencyKey) {
      final String k when k.trim().isNotEmpty => k,
      _ => '${entity}_${operation}_${item.localUuid}',
    },
    'entity': entity,
    'operation': operation,
    'data': data,
    'vectorClock': vectorClock,
    'updatedAt': toWireEpochSeconds(item.clientTs),
    'deviceId': switch (deviceId) {
      final String d when d.trim().isNotEmpty => d,
      _ => 'unknown-origin',
    },
  };
}

/// `create|update|delete` حصراً — نظير `PushWireContract.mapOperation`.
///
/// الـWorker يرفض أي قيمة أخرى بـ`Invalid operation` (`sync.ts:77`) وهي
/// `validation_error` ⇒ رفض دائم وdead-letter بلا إعادة. صندوق Dart يكتب
/// القيم الثلاث نفسها اليوم، فالترجمة حارس لا إصلاح — وقفل بالاختبار.
String mapOperation(String op) => switch (op.trim().toLowerCase()) {
  'insert' || 'create' || 'upsert' => 'create',
  'update' || 'edit' => 'update',
  'delete' || 'soft_delete' || 'softdelete' => 'delete',
  final other => other,
};

/// توحيد اسم الكيان إلى اسم السلك — نظير `PushWireContract.canonicalEntity`.
///
/// القيم غير المعروفة تمر كما هي: رفض الخادم الصريح أوضح من التخمين.
String canonicalEntity(String entity) =>
    entity.trim() == 'blacklist_entries' ? 'blacklist' : entity.trim();

/// `updatedAt` بوحدة ثوانٍ — نظير `PushWireContract.clientTimestampSeconds`
/// (عتبة 1e11 ⇒ ÷1000). صندوق Dart يخزّن `client_ts` بالثوانٍ أصلاً
/// (`Time.nowEpoch()`)، فالشرط دفاع لوراثة صفوف قديمة أو مُعادلتها من
/// أندرويد — والـWorker يقارن هذا الحقل بثواني الأجهزة الأخرى.
int toWireEpochSeconds(int value) =>
    value >= PayloadNormalizer.millisThreshold ? value ~/ 1000 : value;
