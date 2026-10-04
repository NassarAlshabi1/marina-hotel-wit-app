// lib/services/cloudflare_d1_app_users_source.dart
//
// ✅ D1-path audit fix (2026-10-04) — الفجوة F2:
// مجموعة `app_users` متزامنة مع Appwrite Cloud (رفع عبر Outbox في
// `_processAppUserEntry` + سحب عبر `AuthLocalStore.loadCloudAccounts`)
// لكن **لا يوجد جدول محلي لها في Drift** — الحسابات تُحفظ في
// SharedPreferences (`custom_accounts` + `user_permissions`) — لذلك كان
// مسار رفع Cloudflare D1 (SELECT * من جداول Drift) لا يصلها أبداً وكانت
// مرآة D1 تفتقد دليل المستخدمين كلياً.
//
// الحل: جدول `app_users` **تركيبي** في مسار D1:
// - المصدر: الحسابات المحلية (custom_accounts) + الحسابات السحابية
//   (loadCloudAccounts — best-effot بصمت عند انقطاع الشبكة) + خريطة
//   الصلاحيات (user_permissions).
// - الشكل: شكل مستند Appwrite Cloud نفسه (username/full_name/user_type/
//   role/permissions/active/credentials_version/...) لتبقى المرآة مطابقة
//   لما تحمله السحابة.
// - الأمان: عمود `password_hash` يحمل تجزئة PBKDF2 فقط (نفس ما يُخزَّن
//   محلياً ويُرفع للسحابة — لا نص صريح أبداً). الحسابات الثابتة المعرّفة
//   في الكود (admin) تُصدَّر **بدون** تجزئة (NULL) لأن بيانات اعتمادها
//   تُستعاد من الكود نفسه عند الاستعادة.
//
// هذا الملف نقي (بلا Flutter/Appwrite) ليكون قابل للاختبار المباشر.

import 'dart:convert';

/// تعريف جدول app_users في D1 — يُنقل عبر مرحلة DDL في `uploadData`
/// (مكتوب مسبقاً بـ IF NOT EXISTS — `_toIfNotExists` يتسامح معه).
const String kAppUsersD1CreateSql =
    'CREATE TABLE IF NOT EXISTS app_users ('
    'doc_id TEXT PRIMARY KEY, '
    'username TEXT NOT NULL, '
    'password_hash TEXT, '
    'full_name TEXT, '
    'user_type TEXT, '
    'role TEXT, '
    'permissions TEXT, '
    'active INTEGER NOT NULL DEFAULT 1, '
    'is_locked INTEGER NOT NULL DEFAULT 0, '
    'is_cloud INTEGER NOT NULL DEFAULT 0, '
    'credentials_version INTEGER, '
    'version INTEGER, '
    'last_modified INTEGER, '
    'exported_at TEXT)';

/// مدخلات بناء صفوف مرآة app_users (خام — تُنتجها AuthLocalStore).
class AppUsersBackupInputs {
  const AppUsersBackupInputs({
    required this.localAccounts,
    required this.cloudAccounts,
    required this.permissionsByUser,
    required this.fixedAccounts,
    required this.exportedAtIso,
  });

  /// custom_accounts الخام: username → {password(hash), full_name, user_type, id}
  final Map<String, dynamic> localAccounts;

  /// ناتج loadCloudAccounts الخام: username → حقول بمستند Cloud
  /// (password(hash), full_name, user_type, permissions_json, active,
  /// is_locked, credentials_version, role, version, doc_id, cloud_user_id)
  final Map<String, dynamic> cloudAccounts;

  /// user_permissions الخام: username → List<String>
  final Map<String, dynamic> permissionsByUser;

  /// الحسابات الثابتة في الكود: username → {password, user_type, full_name, id}
  final Map<String, dynamic> fixedAccounts;

  final String exportedAtIso;
}

/// أسماء أعمدة جدول app_users بترتيبها الثابت (مرجع للاختبارات والرفع).
const List<String> kAppUsersD1Columns = <String>[
  'doc_id',
  'username',
  'password_hash',
  'full_name',
  'user_type',
  'role',
  'permissions',
  'active',
  'is_locked',
  'is_cloud',
  'credentials_version',
  'version',
  'last_modified',
  'exported_at',
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

/// بناء صفوف مرآة app_users لرفع D1.
///
/// قواعد الدمج:
/// 1. الحسابات الثابتة (admin) تُصدَّر أولاً — بلا تجزئة كلمة مرور (NULL).
/// 2. الحسابات المحلية (custom_accounts) تليها — `doc_id` تركيبي
///    `local_<username>` و`is_cloud=0` وصلاحياتها من خريطة user_permissions.
/// 3. الحسابات السحابية تغلب المحلي عند تشابه اسم المستخدم (السحابة هي
///    المصدر الأساسي للهوية عبر `doc_id` الثابت بين الأجهزة).
List<Map<String, Object?>> buildAppUsersBackupRows(AppUsersBackupInputs inputs) {
  final rows = <String, Map<String, Object?>>{};

  Map<String, Object?> baseRow(String username) => <String, Object?>{
    'doc_id': null,
    'username': username,
    'password_hash': null,
    'full_name': null,
    'user_type': null,
    'role': null,
    'permissions': jsonEncode(<Object?>[]),
    'active': 1,
    'is_locked': 0,
    'is_cloud': 0,
    'credentials_version': null,
    'version': null,
    'last_modified': null,
    'exported_at': inputs.exportedAtIso,
  };

  // 1) الحسابات الثابتة المعرّفة في الكود — بيانات الاعتماد تُستعاد من
  //    الكود عند الاستعادة لذا لا تُرافقها أي تجزئة في المرآة.
  inputs.fixedAccounts.forEach((username, raw) {
    if (raw is! Map) return;
    final row = baseRow(username)
      ..['doc_id'] = 'local_$username'
      ..['full_name'] = _asString(raw['full_name']) ?? username
      ..['user_type'] = _asString(raw['user_type'])
      ..['role'] = _asString(raw['user_type'])
      ..['is_cloud'] = 0;
    final perms = inputs.permissionsByUser[username];
    if (perms is List) {
      row['permissions'] = jsonEncode(perms);
    }
    rows[username] = row;
  });

  // 2) الحسابات المحلية المخصصة.
  inputs.localAccounts.forEach((username, raw) {
    if (raw is! Map) return;
    final row = baseRow(username)
      ..['doc_id'] = 'local_$username'
      ..['password_hash'] = _asString(raw['password']) // تجزئة PBKDF2 فقط
      ..['full_name'] = _asString(raw['full_name']) ?? username
      ..['user_type'] = _asString(raw['user_type'])
      ..['role'] = _asString(raw['user_type'])
      ..['is_cloud'] = 0;
    final perms = inputs.permissionsByUser[username];
    if (perms is List) {
      row['permissions'] = jsonEncode(perms);
    }
    rows[username] = row;
  });

  // 3) الحسابات السحابية — تغلب المحلي بنفس اسم المستخدم.
  inputs.cloudAccounts.forEach((username, raw) {
    if (raw is! Map) return;
    final row = baseRow(username)
      ..['doc_id'] =
          _asString(raw['doc_id']) ??
          _asString(raw['cloud_user_id']) ??
          'cloud_$username'
      ..['password_hash'] = _asString(raw['password']) // تجزئة من السحابة
      ..['full_name'] = _asString(raw['full_name']) ?? username
      ..['user_type'] = _asString(raw['user_type'])
      ..['role'] = _asString(raw['role']) ?? _asString(raw['user_type'])
      ..['is_cloud'] = 1
      ..['active'] = _asBoolInt(raw['active'], fallback: 1)
      ..['is_locked'] = _asBoolInt(raw['is_locked'], fallback: 0)
      ..['credentials_version'] = _asInt(raw['credentials_version'])
      ..['version'] = _asInt(raw['version'])
      ..['last_modified'] = _asInt(raw['lastModified']);
    final permsJson = _asString(raw['permissions_json']);
    if (permsJson != null && permsJson.isNotEmpty) {
      row['permissions'] = permsJson;
    } else {
      final perms = inputs.permissionsByUser[username];
      if (perms is List) row['permissions'] = jsonEncode(perms);
    }
    rows[username] = row;
  });

  // ترتيب مستقر بالاسم لتقسيم صفحات ثابت بين الرفعات.
  final usernames = rows.keys.toList()..sort();
  return [for (final u in usernames) rows[u]!];
}

/// تقسيم صفوف المصدر التركيبي بنمط LIMIT/OFFSET نفسه الذي تستخدمه
/// `CloudflareD1SourceTable.readChunk` — يمنع تكرار/إسقاط الصفوف عند
/// اختلاف العدّ المعروض عن المُرفع.
List<Map<String, Object?>> sliceRows(
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
