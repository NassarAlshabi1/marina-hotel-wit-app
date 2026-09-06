import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import 'appwrite_sync_manager.dart';
import 'local_db.dart';
import 'password_hasher.dart';

enum AuthType { local }

class AuthLocalStore {
  String _cloudDocumentId(String username) {
    final legacyId = 'user_$username';
    final validLegacy =
        legacyId.length <= 36 &&
        RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(legacyId);
    if (validLegacy) return legacyId;

    final digest = sha256.convert(utf8.encode(username)).toString();
    return 'user_${digest.substring(0, 31)}';
  }

  /// ✅ (2026-09-05) حمولة مزامنة app_users بصيغة snake_case مطابقة
  /// لأعمدة جدول app_users في D1 (worker/schema.sql و
  /// migrations/0003_app_users.sql — مرآة جدول Drift المحلي AppUsers).
  ///
  /// لماذا snake_case؟ طبقة Cloudflare تُرشّح مفاتيح الحمولة مقابل
  /// أعمدة الجدول فعلياً (worker database.ts getTableColumns في
  /// createRecord/updateRecord) — المفاتيح camelCase القديمة
  /// (updatedAt/lastModified/…) كانت تُسقط صمتاً، و requireEntityId
  /// (worker sync.ts:60) يطلب local_uuid صراحة وإلا فشلت العملية
  /// ورست في dead-letter. هذا يوحّد app_users مع بقية الكيانات التي
  /// تبني حمولاتها من صفوف Drift (أعمدة snake_case).
  ///
  /// الهوية: local_uuid = معرف المستند السحابي الحتمي [_cloudDocumentId]
  /// — نفسها التي تستخدمها عمليات Outbox القائمة.
  static Map<String, dynamic> appUsersSyncPayload({
    required String localUuid,
    required int now, String? username,
    String? password,
    String? fullName,
    String? userType,
    String? permissionsJson,
    bool? active,
    int? lastLogin,
    int? credentialsVersion,
    String? role,
    int version = 1,
    String? deviceId,
    bool tombstone = false,
  }) {
    return <String, dynamic>{
      'local_uuid': localUuid,
      'updated_at': now,
      'last_modified': now,
      'last_modified_epoch': now,
      'version': version,
      'vector_clock': jsonEncode(<String, int>{
        if (deviceId != null && deviceId.isNotEmpty) deviceId: 1,
      }),
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
      'origin': 'local',
      if (tombstone) 'deleted_at': now,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      if (fullName != null) 'full_name': fullName,
      if (userType != null) 'user_type': userType,
      if (role != null) 'role': role,
      if (permissionsJson != null) 'permissions': permissionsJson,
      if (active != null) 'active': active ? 1 : 0,
      if (lastLogin != null) 'last_login': lastLogin,
      if (credentialsVersion != null) 'credentials_version': credentialsVersion,
    };
  }

  static const _kCurrentUser = 'current_user';
  static const _kPermissionsMap = 'user_permissions';
  static const _kCustomAccounts = 'custom_accounts';
  static const _kRememberMe = 'remember_me';
  static const _kAuthType = 'auth_type';

  static const List<String> permissionKeys = [
    'dashboard',
    'rooms',
    'bookings',
    'payments',
    'debts',
    'employees',
    'expenses',
    'finance',
    'reports',
    'notes',
    'information',
    'settings',
    'inventory',
  ];

  /// صلاحيات العمليات الدقيقة. وجود المفتاح القديم للقسم يبقى متوافقاً
  /// ويمنح نفس صلاحيات الإصدار السابق، بينما المفاتيح الجديدة تسمح بالفصل
  /// بين القراءة والإضافة والتعديل والحذف.
  static const List<String> operationPermissionKeys = [
    'view',
    'create',
    'update',
    'delete',
  ];

  static const Map<String, String> _permissionActions = {
    'view': 'عرض',
    'create': 'إضافة',
    'update': 'تعديل',
    'delete': 'حذف',
  };

  static List<String> permissionKeysForModule(String module) => [
    for (final action in operationPermissionKeys) '$module.$action',
  ];

  /// مفاتيح محرر المستخدمين: المفاتيح القديمة للتوافق، ثم العمليات الدقيقة.
  static List<String> get permissionEditorKeys => [
    ...permissionKeys,
    for (final module in permissionKeys) ...permissionKeysForModule(module),
  ];

  static String operationLabel(String action) =>
      _permissionActions[action] ?? action;

  /// يتحقق من صلاحية عملية محددة مع إبقاء الحسابات الحالية متوافقة.
  static bool canPerform({
    required String? userType,
    required List<String> permissions,
    required String module,
    required String action,
  }) {
    if (userType == 'admin' || permissions.contains('all')) return true;
    if (permissions.contains(module)) return true;
    return permissions.contains('$module.$action');
  }

  /// يستخدم لحارس الصفحة والقائمة: يكفي امتلاك أي صلاحية تشغيلية.
  static bool canAccessModule({
    required String? userType,
    required List<String> permissions,
    required String module,
  }) {
    if (userType == 'admin' || permissions.contains('all')) return true;
    if (permissions.contains(module)) return true;
    return permissionKeysForModule(module).any(permissions.contains);
  }

  /// حسابات افتراضية للوصول المحلي (fallback عند عدم توفر Appwrite Cloud).
  ///
  /// admin/admin — مدير النظام
  ///
  /// ⚠️ مهم: هذه الحسابات تعمل فقط على الأجهزة التي لم تُهاجر لـ Appwrite Cloud.
  /// الأجهزة المُهاجرة تستخدم `app_users` collection في Cloud.
  static const Map<String, Map<String, dynamic>> _fixedAccounts = {
    'admin': {
      'password': 'admin',
      'user_type': 'admin',
      'full_name': 'مدير النظام',
      'id': 1,
    },
  };

  static const Map<String, List<String>> _fixedPermissions = {
    '1': [
      'dashboard',
      'bookings',
      'payments',
      'debts',
      'employees',
      'expenses',
      'finance',
      'reports',
      'notes',
      'information',
    ],
  };

  Future<Map<String, dynamic>> _loadCustomAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCustomAccounts);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) {
          if (value is Map) {
            return MapEntry(
              key.toString(),
              value.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
          return MapEntry(key.toString(), <String, dynamic>{});
        });
      }
    } catch (e, st) {
      AppLogger.warning(
        'فشل قراءة الحسابات المخصصة المحفوظة',
        tag: 'AUTH',
        error: e,
        stackTrace: st,
      );
    }
    return {};
  }

  Future<void> _saveCustomAccounts(Map<String, dynamic> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCustomAccounts, jsonEncode(accounts));
  }

  Future<Map<String, dynamic>?> _getCustomAccount(String username) async {
    final accounts = await _loadCustomAccounts();
    final data = accounts[username];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  int _nextUserId(Map<String, dynamic> customAccounts) {
    int maxId = 0;
    for (final entry in _fixedAccounts.values) {
      final id = entry['id'];
      if (id is int && id > maxId) {
        maxId = id;
      }
    }
    customAccounts.forEach((_, value) {
      if (value is Map) {
        final rawId = value['id'];
        if (rawId is int) {
          if (rawId > maxId) {
            maxId = rawId;
          }
        } else if (rawId is String) {
          final parsed = int.tryParse(rawId);
          if (parsed != null && parsed > maxId) {
            maxId = parsed;
          }
        }
      }
    });
    return maxId + 1;
  }

  /// سحب المستخدمين السحابيين — ✅ (2026-09-05) Cloudflare-only:
  /// المصدر هو جدول app_users المحلي (Drift) — landing zone للسحب من D1
  /// عبر مسار app_users المتزامن (pull/push + outbox delta sync).
  /// كان يقرأ مجموعة app_users من Appwrite Cloud مباشرة.
  /// يعيد Map<username, account_data> أو فارغ عند الفشل
  Future<Map<String, Map<String, dynamic>>> loadCloudAccounts({
    bool includeInactive = false,
  }) async {
    try {
      if (!DatabaseManager.isInitialized) return {};
      final db = DatabaseManager.instance;
      final rows = await db
          .customSelect(
            'SELECT * FROM app_users WHERE deleted_at IS NULL',
          )
          .get();
      final cloudAccounts = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final d = row.data;
        final username = (d['username'] ?? '').toString().trim();
        if (username.isEmpty) continue;
        final active = d['active'];
        final isActive = active is bool ? active : (active as num? ?? 1) != 0;
        if (!isActive && !includeInactive) continue;
        final docId = (d['local_uuid'] ?? '').toString();
        cloudAccounts[username] = {
          'password': (d['password'] ?? '').toString(),
          'full_name': (d['full_name'] ?? username).toString(),
          'user_type': (d['user_type'] ?? d['role'] ?? 'employee').toString(),
          'id': (d['id'] as num?)?.toInt() ?? docId.hashCode,
          'cloud_user_id': docId,
          'doc_id': docId,
          'is_cloud': true,
          'permissions_json': (d['permissions'] ?? '[]').toString(),
          'active': isActive,
          'is_locked': false,
          'credentials_version': (d['credentials_version'] as num?) ?? 1,
          'role': (d['role'] ?? d['user_type'] ?? 'employee').toString(),
          'version': (d['version'] as num?) ?? 1,
          'lastModified': d['last_modified'],
        };
      }
      if (cloudAccounts.isNotEmpty) {
        AppLogger.debug(
          'Cloud users loaded (D1 local mirror): ${cloudAccounts.keys.join(', ')}',
          tag: 'AUTH',
        );
      }
      return cloudAccounts;
    } catch (e) {
      AppLogger.warning(
        'Failed to load cloud users (fallback to local only)',
        tag: 'AUTH',
        error: e,
      );
      return {};
    }
  }

  Future<Map<String, dynamic>?> validateCredentials(
    String username,
    String password,
  ) async {
    final normalized = username.trim();

    // 1️⃣ البحث في الحسابات المحلية (hardcoded + custom)
    Map<String, dynamic>? account = _fixedAccounts[normalized];
    account ??= await _getCustomAccount(normalized);

    // 2️⃣ البحث في Appwrite Cloud
    if (account == null) {
      final cloudAccounts = await loadCloudAccounts();
      account = cloudAccounts[normalized];
    }

    if (account == null) {
      return null;
    }
    final storedPassword = account['password']?.toString() ?? '';

    // ✅ تشفير كلمات المرور (2026-06-28 P2):
    // نستخدم PasswordHasher.verify للتحقق من كلمات المرور المشفّرة بـ PBKDF2.
    // للتوافق مع الإصدارات السابقة، يدعم verify أيضاً كلمات المرور بالنص الصريح.
    if (!PasswordHasher.verify(password, storedPassword)) {
      return null;
    }

    // ✅ ترحيل تلقائي: إذا كانت كلمة المرور المخزّنة نصاً صريحاً (legacy)،
    // نُعيد تشفيرها بـ PBKDF2 ونُحدّث التخزين والسحابة.
    if (!PasswordHasher.isHashed(storedPassword) && storedPassword.isNotEmpty) {
      AppLogger.info(
        '🔄 Migrating plaintext password to PBKDF2 for user: $normalized',
        tag: 'AUTH',
      );
      final hashedPassword = PasswordHasher.hash(password);
      await _migratePasswordToHashed(normalized, account, hashedPassword);
    }

    // تحميل الصلاحيات: admin = all, cloud = من JSON, local = من SharedPreferences
    List<String> perms;
    if (normalized == 'admin') {
      perms = ['all'];
    } else if (account['is_cloud'] == true) {
      // مستخدم سحابي — الصلاحيات من الحقل JSON
      try {
        final permsJson = account['permissions_json'] as String? ?? '[]';
        final parsed = jsonDecode(permsJson);
        perms = (parsed as List).map((e) => e.toString()).toList();
      } catch (e, st) {
        AppLogger.warning(
          'فشل تحليل صلاحيات المستخدم السحابي، سيتم استخدام صلاحيات احتياطية',
          tag: 'AUTH',
          error: e,
          stackTrace: st,
        );
        perms = await getPermissions(normalized);
      }
      // حفظ credentials_version لمراقبة الجلسة — ✅ (2026-09-05)
      // Cloudflare-only: القراءة من صف app_users المحلي (مرآة D1) —
      // كان يقرأ مجموعة app_users من Appwrite مباشرة.
      try {
        if (DatabaseManager.isInitialized) {
          final db = DatabaseManager.instance;
          final rows = await db
              .customSelect(
                'SELECT credentials_version FROM app_users '
                'WHERE username = ? AND deleted_at IS NULL LIMIT 1',
                variables: [Variable.withString(normalized)],
              )
              .get();
          if (rows.isNotEmpty) {
            final version =
                (rows.first.data['credentials_version'] as num?)?.toInt() ?? 0;
            await saveCredentialsVersion(version);
          }
        }
      } catch (e, st) {
        AppLogger.warning(
          'تعذر حفظ credentials_version للمستخدم $normalized',
          tag: 'AUTH',
          error: e,
          stackTrace: st,
        );
      }
    } else {
      perms = await getPermissions(normalized);
    }

    return {
      'id': account['id'] ?? 0,
      'cloud_user_id': account['cloud_user_id'],
      'username': normalized,
      'full_name': (account['full_name'] ?? normalized).toString(),
      'user_type': (account['user_type'] ?? 'employee').toString(),
      'permissions': perms,
    };
  }

  Future<void> addUser({
    required String username,
    required String password,
    required String fullName,
    required String userType,
    required List<String> permissions,
  }) async {
    final normalized = username.trim();
    if (normalized.isEmpty) {
      throw Exception('اسم المستخدم مطلوب');
    }
    if (password.isEmpty) {
      throw Exception('كلمة المرور مطلوبة');
    }
    if (_fixedAccounts.containsKey(normalized)) {
      throw Exception('اسم المستخدم محجوز');
    }
    final accounts = await _loadCustomAccounts();
    if (accounts.containsKey(normalized)) {
      throw Exception('اسم المستخدم موجود مسبقاً');
    }
    final id = _nextUserId(accounts);
    // ✅ تشفير كلمة المرور قبل التخزين المحلي
    final hashedPassword = PasswordHasher.hash(password);
    accounts[normalized] = {
      'password': hashedPassword,
      'full_name': fullName,
      'user_type': userType,
      'id': id,
    };
    await _saveCustomAccounts(accounts);
    await setPermissions(normalized, permissions);

    // رفع المستخدم إلى Appwrite Cloud (كلمة المرور تُشفّر داخل _pushUserToCloud)
    await _pushUserToCloud(
      username: normalized,
      password: password, // يُمرّر كنص صريح، يُشفّر داخل _pushUserToCloud
      fullName: fullName,
      userType: userType,
      permissions: permissions,
    );
  }

  /// رفع مستخدم إلى "السحابة" — ✅ (2026-09-05) Cloudflare-only:
  /// الكتابة المحلية + Outbox فقط — جدول app_users المحلي مصدر رفع D1
  /// وlanding zone للسحب (pull/push + outbox delta sync). الإرسال الفعلي
  /// إلى D1 يتم عبر CloudflareSyncManager._pushOutbox. كان يكتب مستنداً
  /// موازياً في Appwrite Cloud — أُزيل ضمن إزالة Appwrite.
  Future<void> _pushUserToCloud({
    required String username,
    required String password,
    required String fullName,
    required String userType,
    required List<String> permissions,
  }) async {
    try {
      final docId = _cloudDocumentId(username);
      final hashedPassword = PasswordHasher.hash(password);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final deviceId = await _getDeviceId() ?? '';
      final syncPayload = AuthLocalStore.appUsersSyncPayload(
        localUuid: docId,
        username: username,
        password: hashedPassword,
        fullName: fullName,
        userType: userType,
        permissionsJson: jsonEncode(permissions),
        active: true,
        lastLogin: 0,
        credentialsVersion: 1,
        role: userType,
        now: now,
        deviceId: deviceId,
      );
      await _writeLocalAppUsersRow(syncPayload);
      await _enqueueAppUsersOp(
        op: 'create',
        docId: docId,
        payload: syncPayload,
      );
      AppLogger.debug(
        'User $username queued to D1 via outbox (password hashed)',
        tag: 'AUTH',
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to queue user $username to D1 outbox',
        tag: 'AUTH',
        error: e,
      );
    }
  }

  /// ✅ ترحيل كلمة مرور من نص صريح إلى PBKDF2 hash
  /// يُحدّث التخزين المحلي (custom accounts) والسحابة (إذا كان حساباً سحابياً)
  Future<void> _migratePasswordToHashed(
    String username,
    Map<String, dynamic> account,
    String hashedPassword,
  ) async {
    try {
      // 1️⃣ تحديث الحسابات المحلية المخصصة (custom)
      final accounts = await _loadCustomAccounts();
      if (accounts.containsKey(username)) {
        final custom = accounts[username] as Map<String, dynamic>;
        custom['password'] = hashedPassword;
        await _saveCustomAccounts(accounts);
        AppLogger.debug('Local password migrated for $username', tag: 'AUTH');
      }

      // 2️⃣ تحديث السحابة (إذا كان حساباً سحابياً) — ✅ (2026-09-05)
      // Cloudflare-only: كتابة محلية + Outbox فقط، كان يحدّث Appwrite أولاً.
      if (account['is_cloud'] == true) {
        final docId = account['doc_id'] as String?;
        if (docId != null && docId.isNotEmpty) {
          final syncPayload = AuthLocalStore.appUsersSyncPayload(
            localUuid: docId,
            username: username,
            password: hashedPassword,
            now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            deviceId: await _getDeviceId(),
          );
          await _writeLocalAppUsersRow(syncPayload);
          await _enqueueAppUsersOp(
            op: 'update',
            docId: docId,
            payload: syncPayload,
          );
          AppLogger.debug('Cloud password migrated for $username', tag: 'AUTH');
        }
      }
    } catch (e, st) {
      // فشل الترحيل ليس خطأ قاتلاً — المستخدم يسجّل الدخول بنجاح
      // سنحاول الترحيل مرة أخرى في تسجيل الدخول التالي
      AppLogger.warning(
        'Password migration failed for $username (will retry next login)',
        tag: 'AUTH',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// تحديث حساب محلي مخصص.
  Future<bool> updateLocalUser({
    required String username,
    String? newPassword,
    String? newFullName,
    String? newUserType,
    List<String>? newPermissions,
  }) async {
    final accounts = await _loadCustomAccounts();
    final raw = accounts[username];
    if (raw is! Map) return false;

    final account = Map<String, dynamic>.from(raw);
    if (newPassword != null && newPassword.isNotEmpty) {
      account['password'] = PasswordHasher.hash(newPassword);
    }
    if (newFullName != null) account['full_name'] = newFullName;
    if (newUserType != null) account['user_type'] = newUserType;
    accounts[username] = account;
    await _saveCustomAccounts(accounts);
    if (newPermissions != null) {
      await setPermissions(username, newPermissions);
    }
    return true;
  }

  /// حذف حساب محلي مخصص.
  Future<bool> deleteLocalUser(String username) async {
    if (_fixedAccounts.containsKey(username)) return false;
    final accounts = await _loadCustomAccounts();
    if (!accounts.containsKey(username)) return false;
    accounts.remove(username);
    await _saveCustomAccounts(accounts);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPermissionsMap);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final permissions = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          permissions.remove(username);
          await prefs.setString(_kPermissionsMap, jsonEncode(permissions));
        }
      } catch (e, st) {
        AppLogger.warning(
          'تعذر تنظيف صلاحيات المستخدم المحلي المحذوف $username',
          tag: 'AUTH',
          error: e,
          stackTrace: st,
        );
      }
    }
    return true;
  }

  /// تحديث بيانات مستخدم سحابي (اسم، كلمة مرور، صلاحيات) + زيادة credentials_version
  /// يعيد true إذا نجح → يجب قطع الجلسة على الأجهزة الأخرى
  Future<bool> updateCloudUser({
    required String username,
    required String docId,
    String? newPassword,
    String? newFullName,
    String? newUserType,
    List<String>? newPermissions,
    bool? active,
  }) async {
    try {
      // ✅ (2026-09-05) Cloudflare-only: الإصدار الحالي يُقرأ من صف
      // app_users المحلي (مرآة D1) — كان يُسحب من Appwrite قبل التعديل.
      int currentVersion = 0;
      if (DatabaseManager.isInitialized) {
        final db = DatabaseManager.instance;
        final rows = await db
            .customSelect(
              'SELECT credentials_version FROM app_users '
              'WHERE local_uuid = ? LIMIT 1',
              variables: [Variable.withString(docId)],
            )
            .get();
        if (rows.isNotEmpty) {
          currentVersion =
              (rows.first.data['credentials_version'] as num?)?.toInt() ?? 0;
        }
      }
      final nextVersion = currentVersion + 1;

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final syncPayload = AuthLocalStore.appUsersSyncPayload(
        localUuid: docId,
        username: username,
        password: (newPassword != null && newPassword.isNotEmpty)
            ? PasswordHasher.hash(newPassword)
            : null,
        fullName: newFullName,
        userType: newUserType,
        permissionsJson: newPermissions != null
            ? jsonEncode(newPermissions)
            : null,
        active: active,
        credentialsVersion: nextVersion,
        role: newUserType,
        now: now,
        version: nextVersion,
        deviceId: await _getDeviceId(),
      );
      await _writeLocalAppUsersRow(syncPayload);
      final queued = await _enqueueAppUsersOp(
        op: 'update',
        docId: docId,
        payload: syncPayload,
      );

      AppLogger.info(
        'Cloud user $username updated locally, outbox=$queued '
        '(version $currentVersion → $nextVersion)',
        tag: 'AUTH',
      );
      return true;
    } catch (e) {
      AppLogger.error(
        'Failed to update cloud user $username',
        tag: 'AUTH',
        error: e,
      );
      return false;
    }
  }

  /// حذف مستخدم سحابي — ✅ (2026-09-05) Cloudflare-only: tombstone محلي +
  /// outbox delete — يصل الحذف إلى D1 عبر المسار المتزامن ولا يعود الصف
  /// مع السحب اللاحق. كان يحذف المستند من Appwrite أولاً.
  Future<bool> deleteCloudUser({required String docId}) async {
    try {
      final syncPayload = AuthLocalStore.appUsersSyncPayload(
        localUuid: docId,
        now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        deviceId: await _getDeviceId(),
        tombstone: true,
      );
      await _writeLocalAppUsersRow(syncPayload);
      await _enqueueAppUsersOp(
        op: 'delete',
        docId: docId,
        payload: syncPayload,
      );
      AppLogger.info('Cloud user deleted (doc: $docId)', tag: 'AUTH');
      return true;
    } catch (e) {
      AppLogger.warning('Failed to delete cloud user', tag: 'AUTH', error: e);
      return false;
    }
  }

  /// حفظ credentials_version عند تسجيل الدخول
  static const _kCredVersion = 'credentials_version';

  Future<void> saveCredentialsVersion(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCredVersion, version);
  }

  Future<int?> getCredentialsVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCredVersion);
  }

  /// التحقق من صلاحية الجلسة — يقارن credentials_version المحلي مع السحابة
  /// يعيد true إذا الجلسة صالحة، false إذا تم تغيير البيانات من جهاز آخر
  Future<bool> checkSessionValidity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedVersion = prefs.getInt(_kCredVersion);

      final currentUser = await loadCurrentUser();
      if (currentUser == null) return true;

      final username = currentUser['username']?.toString() ?? '';
      if (username.isEmpty) return true;
      if (_fixedAccounts.containsKey(username)) return true; // hardcoded

      // ✅ (2026-09-05) Cloudflare-only: نقرأ صف app_users المحلي
      // (مرآة D1) — يشمل الحسابات النشطة وغير النشطة لأننا نقرأ الجدول
      // مباشرة، ولا يعتمد على شبكة. غياب الصف = حذف/تعطيل الحساب.
      if (!DatabaseManager.isInitialized) return true;
      final db = DatabaseManager.instance;
      final rows = await db
          .customSelect(
            'SELECT active, credentials_version FROM app_users '
            'WHERE username = ? AND deleted_at IS NULL LIMIT 1',
            variables: [Variable.withString(username)],
          )
          .get();

      if (rows.isEmpty) {
        AppLogger.warning(
          'Session invalid for $username: account deleted or inactive',
          tag: 'AUTH',
        );
        return false;
      }
      final d = rows.first.data;
      final active = d['active'];
      final isActive = active is bool ? active : (active as num? ?? 1) != 0;
      if (!isActive) {
        AppLogger.warning(
          'Session invalid for $username: account deleted or inactive',
          tag: 'AUTH',
        );
        return false;
      }

      final cloudVersion = (d['credentials_version'] as num?)?.toInt() ?? 0;
      if (storedVersion == null) {
        // جلسة قديمة من إصدار لا يحفظ النسخة: نثبت النسخة الحالية بعد
        // التحقق من أن الحساب موجود ونشط، بدلاً من تجاوز الإلغاء تماماً.
        await saveCredentialsVersion(cloudVersion);
        return true;
      }
      if (cloudVersion != storedVersion) {
        AppLogger.warning(
          'Session invalid for $username: local=$storedVersion, cloud=$cloudVersion',
          tag: 'AUTH',
        );
        return false;
      }
      return true;
    } catch (e) {
      AppLogger.warning(
        'Session check failed (ignoring)',
        tag: 'AUTH',
        error: e,
      );
      return true;
    }
  }

  Future<List<Map<String, dynamic>>> getAllAccountsDetailed() async {
    final result = <Map<String, dynamic>>[];

    // حسابات محلية ثابتة (hardcoded)
    _fixedAccounts.forEach((username, data) {
      result.add({
        'username': username,
        'full_name': data['full_name'] ?? username,
        'user_type': data['user_type'] ?? 'employee',
        'id': data['id'],
        'is_fixed': true,
        'is_cloud': false,
        'is_active': true,
        'is_locked': false,
      });
    });

    // حسابات محلية مخصصة (custom)
    final customAccounts = await _loadCustomAccounts();
    customAccounts.forEach((username, rawData) {
      if (rawData is Map) {
        result.add({
          'username': username,
          'full_name': rawData['full_name'] ?? username,
          'user_type': rawData['user_type'] ?? 'employee',
          'id': rawData['id'],
          'is_fixed': false,
          'is_cloud': false,
          'is_active': true,
          'is_locked': false,
        });
      }
    });

    // حسابات سحابية من Appwrite (app_users)، بما فيها المعطلة لعرض حالتها.
    try {
      final cloudAccounts = await loadCloudAccounts(includeInactive: true);
      for (final entry in cloudAccounts.entries) {
        final username = entry.key;
        final data = entry.value;
        final existingIndex = result.indexWhere(
          (account) => account['username'].toString() == username,
        );
        if (existingIndex == -1) {
          result.add({
            'username': username,
            'full_name': data['full_name'] ?? username,
            'user_type': data['user_type'] ?? 'employee',
            'id': data['id'],
            'is_fixed': false,
            'is_cloud': true,
            'doc_id': data['doc_id'],
            'is_active': data['active'] != false,
            'is_locked': data['is_locked'] == true,
          });
        } else if (result[existingIndex]['is_fixed'] != true) {
          // الحساب أُنشئ محلياً ثم رُفع إلى Appwrite؛ نحتفظ ببطاقة واحدة
          // ونضيف doc_id حتى تستخدم الشاشة مسار التعديل السحابي الصحيح.
          result[existingIndex] = {
            ...result[existingIndex],
            'full_name':
                data['full_name'] ?? result[existingIndex]['full_name'],
            'user_type':
                data['user_type'] ?? result[existingIndex]['user_type'],
            'is_cloud': true,
            'doc_id': data['doc_id'],
            'is_active': data['active'] != false,
            'is_locked': data['is_locked'] == true,
          };
        }
      }
    } catch (e, st) {
      // فشل سحب السحابي — لا مشكلة، نعرض المحلي فقط
      AppLogger.warning(
        'فشل سحب الحسابات السحابية أثناء التجميع التفصيلي',
        tag: 'AUTH',
        error: e,
        stackTrace: st,
      );
    }

    result.sort((a, b) {
      final aName = a['username'].toString();
      final bName = b['username'].toString();
      return aName.compareTo(bName);
    });
    return result;
  }

  Future<void> saveCurrentUser(Map<String, dynamic> userJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCurrentUser, jsonEncode(userJson));
  }

  Future<Map<String, dynamic>?> loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCurrentUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) return json;
      if (json is Map) {
        return json.map((key, value) => MapEntry(key.toString(), value));
      }
      return null;
    } catch (e, st) {
      AppLogger.warning(
        'بيانات المستخدم الحالي غير صالحة في التخزين المحلي',
        tag: 'AUTH',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = await getRememberMe();
    await prefs.remove(_kCurrentUser);
    if (!rememberMe) {
      await prefs.remove(_kRememberMe);
      await prefs.remove(_kAuthType);
    }
  }

  Future<void> setRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRememberMe, value);
  }

  Future<bool> getRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kRememberMe) ?? true;
  }

  Future<void> setAuthType(AuthType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAuthType, type.name);
  }

  Future<AuthType> getAuthType() async {
    final prefs = await SharedPreferences.getInstance();
    final typeStr = prefs.getString(_kAuthType);
    if (typeStr == null) return AuthType.local;
    return AuthType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => AuthType.local,
    );
  }

  Future<List<String>> getPermissions(String username) async {
    if (username == 'admin') return ['all'];

    // 1️⃣ محاولة سحب الصلاحيات من السحابة
    try {
      final cloudAccounts = await loadCloudAccounts();
      final cloudAccount = cloudAccounts[username];
      if (cloudAccount != null) {
        final permsJson = cloudAccount['permissions_json'] as String? ?? '[]';
        final parsed = jsonDecode(permsJson);
        if (parsed is List && parsed.isNotEmpty) {
          return parsed.map((e) => e.toString()).toList();
        }
      }
    } catch (e, st) {
      AppLogger.warning(
        'تعذر تحميل الصلاحيات من السحابة للمستخدم $username',
        tag: 'AUTH',
        error: e,
        stackTrace: st,
      );
    }

    // 2️⃣ fallback: الصلاحيات المحلية
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPermissionsMap);
    if (raw == null) return _fixedPermissions[username] ?? <String>[];
    try {
      final map = jsonDecode(raw);
      if (map is Map) {
        final v = map[username];
        if (v is List) {
          return v.map((e) => e.toString()).toList();
        }
      }
      return _fixedPermissions[username] ?? <String>[];
    } catch (e, st) {
      AppLogger.warning(
        'تعذر تحليل خريطة الأذونات المحلية للمستخدم $username',
        tag: 'AUTH',
        error: e,
        stackTrace: st,
      );
      return _fixedPermissions[username] ?? <String>[];
    }
  }

  Future<bool> setPermissions(String username, List<String> permissions) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPermissionsMap);
    Map<String, dynamic> map = {};
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          map = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (e, st) {
        AppLogger.warning(
          'فشل قراءة بيانات الأذونات المحفوظة',
          tag: 'AUTH',
          error: e,
          stackTrace: st,
        );
      }
    }
    final previous = map.containsKey(username) ? map[username] : null;
    final nextPermissions = username == 'admin' ? <String>['all'] : permissions;
    map[username] = nextPermissions;
    await prefs.setString(_kPermissionsMap, jsonEncode(map));

    // تحديث الصلاحيات في السحابة أيضاً. إذا فشل، نعيد القيمة المحلية السابقة
    // حتى لا تعرض الواجهة صلاحيات لم تصل فعلياً إلى Appwrite.
    final cloudUpdated = await _updateCloudPermissions(
      username,
      nextPermissions,
    );
    if (cloudUpdated) return true;

    if (previous == null) {
      map.remove(username);
    } else {
      map[username] = previous;
    }
    await prefs.setString(_kPermissionsMap, jsonEncode(map));
    return false;
  }

  /// تحديث صلاحيات مستخدم سحابي — ✅ (2026-09-05) Cloudflare-only:
  /// الكتابة المحلية + Outbox فقط (identifiers حتمية عبر
  /// _cloudDocumentId). كان يحدّث مستند Appwrite مباشرة.
  Future<bool> _updateCloudPermissions(
    String username,
    List<String> permissions,
  ) async {
    try {
      final docId = _cloudDocumentId(username);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // الإصدار الحالي من الصف المحلي (مرآة D1) إن وجد
      int credentialsVersion = 0;
      int version = 0;
      if (DatabaseManager.isInitialized) {
        final db = DatabaseManager.instance;
        final rows = await db
            .customSelect(
              'SELECT credentials_version, version FROM app_users '
              'WHERE local_uuid = ? LIMIT 1',
              variables: [Variable.withString(docId)],
            )
            .get();
        if (rows.isNotEmpty) {
          credentialsVersion =
              (rows.first.data['credentials_version'] as num?)?.toInt() ?? 0;
          version = (rows.first.data['version'] as num?)?.toInt() ?? 0;
        }
      }
      final syncPayload = AuthLocalStore.appUsersSyncPayload(
        localUuid: docId,
        username: username,
        permissionsJson: jsonEncode(permissions),
        credentialsVersion: credentialsVersion + 1,
        now: now,
        version: version + 1,
        deviceId: await _getDeviceId(),
      );
      await _writeLocalAppUsersRow(syncPayload);
      final queued = await _enqueueAppUsersOp(
        op: 'update',
        docId: docId,
        payload: syncPayload,
      );
      AppLogger.debug(
        'Permissions updated for $username (outbox=$queued)',
        tag: 'AUTH',
      );
      return true;
    } catch (e) {
      AppLogger.warning(
        'Failed to update cloud permissions for $username',
        tag: 'AUTH',
        error: e,
      );
      return false;
    }
  }

  /// ✅ (2026-09-05) كتابة/تحديث الصف المحلي في جدول app_users المتزامن
  /// (Drift) — يجعل الجدول المحلي مصدر رفع D1 وlanding zone مكتملة
  /// للسحب، أثناء بقاء Appwrite مساراً مباشراً موازياً (تشغيل مزدوج).
  ///
  /// - الصف موجود: UPDATE بالحقول المرسلة + version = الموجود + 1
  ///   (رقم أحادي التزايد يغذي فصل التعارضات LWW في worker).
  /// - الصف جديد: INSERT كامل مع ملء الأعمدة NOT NULL بلا default
  ///   بما يطابق سلوك worker (database.ts createRecord).
  ///
  /// فشل الكتابة المحلية مساعِد فقط — لا يُفشل العملية الأصلية.
  Future<void> _writeLocalAppUsersRow(
    Map<String, dynamic> syncPayload,
  ) async {
    try {
      if (!DatabaseManager.isInitialized) return;
      final db = DatabaseManager.instance;
      final localUuid = syncPayload['local_uuid'] as String?;
      if (localUuid == null || localUuid.isEmpty) return;

      final existingRows = await db
          .customSelect(
            'SELECT id, version FROM app_users WHERE local_uuid = ? LIMIT 1',
            variables: [Variable.withString(localUuid)],
          )
          .get();
      if (existingRows.isNotEmpty) {
        final existingVersion =
            (existingRows.first.data['version'] as int?) ?? 0;
        final fields = Map<String, dynamic>.from(syncPayload)
          ..remove('local_uuid')
          ..remove('created_at')
          ..['version'] = existingVersion + 1;
        if (fields.isEmpty) return;
        final setClauses = fields.keys.map((c) => '$c = ?').join(', ');
        await db.customStatement(
          'UPDATE app_users SET $setClauses WHERE local_uuid = ?',
          [...fields.values, localUuid],
        );
      } else {
        final row = <String, dynamic>{
          ...syncPayload,
          'username': syncPayload['username'] ?? '',
          'full_name': syncPayload['full_name'] ?? '',
          'user_type': syncPayload['user_type'] ?? '',
          'active': syncPayload['active'] ?? 1,
          'credentials_version': syncPayload['credentials_version'] ?? 0,
          'created_at':
              (syncPayload['created_at'] ?? syncPayload['updated_at']) as int,
          'created_at_epoch': 0,
          'sync_timestamp': 0,
        }..remove('id');
        final columns = row.keys.join(', ');
        final placeholders = row.keys.map((_) => '?').join(', ');
        await db.customStatement(
          'INSERT OR REPLACE INTO app_users ($columns) '
          'VALUES ($placeholders)',
          row.values.toList(),
        );
      }
    } catch (e, st) {
      AppLogger.warning(
        'تعذر تحديث صف app_users المحلي',
        tag: 'AUTH',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// ✅ (2026-09-05) حجز عملية app_users في Outbox (create/update/delete)
  /// بحمولة snake_case — انظر [appUsersSyncPayload].
  Future<bool> _enqueueAppUsersOp({
    required String op,
    required String docId,
    required Map<String, dynamic> payload,
  }) async {
    final manager = AppwriteSyncManager.instance;
    try {
      await manager.outboxDao.merge(
        entity: 'app_users',
        op: op,
        localUuid: docId,
        payload: payload,
        clientTs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      return true;
    } catch (e, st) {
      AppLogger.warning(
        'تعذر إضافة عملية app_users إلى Outbox',
        tag: 'AUTH',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  Future<List<String>> getAllUsernames() async {
    final names = <String>{..._fixedAccounts.keys};
    final custom = await _loadCustomAccounts();
    names.addAll(custom.keys.map((e) => e));
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPermissionsMap);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final k in decoded.keys) {
            names.add(k.toString());
          }
        }
      } catch (e, st) {
        AppLogger.warning(
          'فشل قراءة أسماء المستخدمين من الأذونات',
          tag: 'AUTH',
          error: e,
          stackTrace: st,
        );
      }
    }
    // إضافة أسماء المستخدمين السحابيين
    try {
      final cloudAccounts = await loadCloudAccounts();
      names.addAll(cloudAccounts.keys);
    } catch (e, st) {
      AppLogger.warning(
        'تعذر إضافة المستخدمين السحابيين إلى قائمة الأسماء',
        tag: 'AUTH',
        error: e,
        stackTrace: st,
      );
    }
    final list = names.toList();
    list.sort();
    return list;
  }

  Future<int> getUsersCount() async {
    final list = await getAllUsernames();
    return list.length;
  }

  /// التحقق مما إذا كان المستخدم من الحسابات الثابتة (hardcoded)
  bool isFixedAccount(String username) {
    return _fixedAccounts.containsKey(username);
  }

  /// الحصول على معرّف الجهاز الحالي (لحقل deviceId في المزامنة)
  Future<String?> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('appwrite_device_id') ??
          prefs.getString('appwrite_realtime_device_id');
    } catch (_) {
      return null;
    }
  }
}
