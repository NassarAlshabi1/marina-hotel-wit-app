// lib/services/cloudflare_d1_blacklist_source.dart
//
// ✅ D1-path audit fix (2026-10-11) — الفجوة: blacklist متزامنة مع Appwrite Cloud
// (مجموعة `blacklist` مستقلة) لكن **لا يوجد جدول محلي لها في Drift** —
// السجلات تُحفظ في shift_notes بـ createdBy='blacklist' — لذلك كان
// مسار رفع Cloudflare D1 (SELECT * من جداول Drift) لا يصلها لأنها
// تستبعد من shift_notes (kShiftNotesD1ExclusionWhere).
//
// الحل: جدول `blacklist` **تركيبي** في مسار D1:
// - المصدر: shift_notes حيث created_by = 'blacklist' (تُقرأ مباشرة من Drift).
// - الشكل: نفس مستند Appwrite Cloud blacklist (name, nationality, nationalId,
//   phone, reason, notes, active, reportedBy + حقول المزامنة).
// - الهوية: local_uuid من shift_notes (مفتاح UPSERT في D1).

import 'dart:convert';

import '../../services/local_db.dart';

/// تعريف جدول blacklist في D1 — يُنقل عبر مرحلة DDL في `uploadData`
/// (مكتوب مسبقاً بـ IF NOT EXISTS — `_toIfNotExists` يتسامح معه).
const String kBlacklistD1CreateSql =
    'CREATE TABLE IF NOT EXISTS blacklist ('
    'doc_id TEXT PRIMARY KEY, '
    'name TEXT NOT NULL, '
    'nationality TEXT, '
    'nationalId TEXT, '
    'phone TEXT, '
    'reason TEXT, '
    'notes TEXT, '
    'active INTEGER NOT NULL DEFAULT 1, '
    'reportedBy TEXT, '
    'local_uuid TEXT NOT NULL UNIQUE, '
    'createdAt TEXT, '
    'createdAtIso TEXT, '
    'updatedAt TEXT, '
    'updatedAtIso TEXT, '
    'lastModified INTEGER, '
    'version INTEGER, '
    'origin TEXT, '
    'vectorClock TEXT, '
    'deletedAt INTEGER, '
    'deletedAtIso TEXT, '
    'deviceId TEXT)';

/// أسماء أعمدة جدول blacklist بترتيبها الثابت (مرجع للاختبارات والرفع).
const List<String> kBlacklistD1Columns = <String>[
  'doc_id',
  'name',
  'nationality',
  'nationalId',
  'phone',
  'reason',
  'notes',
  'active',
  'reportedBy',
  'local_uuid',
  'createdAt',
  'createdAtIso',
  'updatedAt',
  'updatedAtIso',
  'lastModified',
  'version',
  'origin',
  'vectorClock',
  'deletedAt',
  'deletedAtIso',
  'deviceId',
];

String? _asString(Object? v) => v?.toString();

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

int _asBoolInt(Object? v, {required int fallback}) {
  if (v is bool) return v ? 1 : 0;
  if (v is int) return v == 0 ? 0 : 1;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == 'true' || s == '1') return 1;
    if (s == 'false' || s == '0') return 0;
  }
  return fallback;
}

/// بناء صفوف مرآة blacklist لرفع D1.
///
/// يقرأ من shift_notes حيث created_by = 'blacklist'.
/// كل صف ShiftNote يُحول لصف blacklist بنفس local_uuid.
List<Map<String, Object?>> buildBlacklistBackupRows(
  AppDatabase db,
  String exportedAtIso,
) {
  final rows = await db.customSelect(
    'SELECT * FROM "shift_notes" WHERE created_by = \'blacklist\'',
  ).get();

  final result = <Map<String, Object?>>[];
  for (final r in rows) {
    final data = r.data;
    final localUuid = _asString(data['local_uuid']) ?? '';
    if (localUuid.isEmpty) continue;

    Map<String, dynamic> extra = {};
    try {
      extra = jsonDecode(data['content']?.toString() ?? '{}') as Map<String, dynamic>;
    } catch (_) {}

    final createdAt = _asInt(data['created_at']);
    final updatedAt = _asInt(data['updated_at']);
    final deletedAt = _asInt(data['deleted_at']);
    final version = _asInt(data['version']) ?? 1;
    final origin = _asString(data['origin']) ?? 'server';
    final vectorClock = _asString(data['vector_clock']) ?? '{}';
    final deviceId = _asString(data['device_id']) ?? '';

    final createdAtIso = createdAt != null
        ? DateTime.fromMillisecondsSinceEpoch(createdAt * 1000).toIso8601String()
        : '';
    final updatedAtIso = updatedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(updatedAt * 1000).toIso8601String()
        : createdAtIso;
    final deletedAtIso = deletedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(deletedAt * 1000).toIso8601String()
        : null;

    result.add({
      'doc_id': localUuid,
      'name': _asString(data['title']) ?? '',
      'nationality': _asString(extra['nationality']),
      'nationalId': _asString(extra['nationalId']),
      'phone': _asString(extra['phone']),
      'reason': _asString(extra['reason']),
      'notes': _asString(extra['notes']),
      'active': _asBoolInt(extra['active'], fallback: 1),
      'reportedBy': _asString(extra['reportedBy']) ?? 'police',
      'local_uuid': localUuid,
      'createdAt': createdAtIso,
      'createdAtIso': createdAtIso,
      'updatedAt': updatedAtIso,
      'updatedAtIso': updatedAtIso,
      'lastModified': _asInt(data['last_modified']) ?? updatedAt ?? createdAt ?? 0,
      'version': version,
      'origin': origin,
      'vectorClock': vectorClock,
      'deletedAt': deletedAt,
      'deletedAtIso': deletedAtIso,
      'deviceId': deviceId,
    });
  }

  // ترتيب مستقر بالـ local_uuid لتقسيم صفحات ثابت بين الرفعات.
  result.sort((a, b) => (a['local_uuid'] as String).compareTo(b['local_uuid'] as String));
  return result;
}

/// تقسيم صفوف المصدر التركيبي بنمط LIMIT/OFFSET نفسه الذي تستخدمه
/// `CloudflareD1SourceTable.readChunk` — يمنع تكرار/إسقاط الصفوف عند
/// اختلاف العدّ المعروض عن المُرفع.
List<Map<String, Object?>> sliceBlacklistRows(
  List<Map<String, Object?>> rows,
  int limit,
  int offset,
) {
  if (limit <= 0 || offset < 0 || offset >= rows.length) {
    return const <Map<String, Object?>>[];
  }
  final end = (offset + limit).clamp(0, rows.length);
  return rows.sublist(offset, end);
}