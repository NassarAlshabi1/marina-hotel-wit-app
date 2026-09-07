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
    return out;
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
}) async {
  final data = PayloadNormalizer.normalize(
    jsonDecode(item.payload) as Map<String, dynamic>,
  );
  // ✅ عقد الهوية: صف outbox يحمل local_uuid دائماً (OutboxDao.merge
  // required localUuid) — الحمولات الرقيقة (soft-deletes `{'id': n}`)
  // لا تحمله، و requireEntityId يرمي على id الرقمي → validation_error.
  data['local_uuid'] ??= item.localUuid;
  // ✅ عقد ساعة المتجه: authoritative clock يعيش على صف الكيان
  // (OutboxDao._bumpVectorClockForLocalWrite يحدّث الجدول لا الحمولة).
  // إرسال '{}' كان يجبر الـ worker على تهيئة ساعة جديدة وفقدان التاريخ.
  final vectorClock =
      data['vector_clock'] as String? ??
      await resolveRowVectorClock(item.entity, item.localUuid) ??
      '{}';
  data['vector_clock'] = vectorClock;
  return <String, dynamic>{
    'idempotencyKey': item.idempotencyKey,
    'entity': item.entity,
    'operation': item.op,
    'data': data,
    'vectorClock': vectorClock,
    'updatedAt': item.clientTs,
  };
}
