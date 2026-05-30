import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import 'appwrite_service.dart';

enum AuthType { local }

/// خدمة تشفير كلمات المرور باستخدام SHA-256 مع salt
class PasswordHasher {
  /// إنشاء hash لكلمة المرور مع salt عشوائي
  static String hashPassword(String password, [String? salt]) {
    final effectiveSalt = salt ?? _generateSalt();
    final bytes = utf8.encode(password + effectiveSalt);
    final digest = sha256.convert(bytes);
    return '$effectiveSalt:${digest.toString()}';
  }

  /// التحقق من كلمة المرور
  static bool verifyPassword(String password, String storedHash) {
    final parts = storedHash.split(':');
    if (parts.length != 2) {
      // Fallback للمقارنة المباشرة (للتوافق)
      return password == storedHash;
    }
    final salt = parts[0];
    final hash = parts[1];
    final computed = sha256.convert(utf8.encode(password + salt)).toString();
    return computed == hash;
  }

  /// توليد salt عشوائي آمن
  static String _generateSalt() {
    final random = Random.secure();
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = random.nextInt(256);
    }
    final encoded = base64Encode(bytes);
    return encoded.substring(0, 22).replaceAll(RegExp(r'[/+=]'), '_');
  }
}

class AuthLocalStore {
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
  ];

  /// الحسابات الثابتة (معرفات فقط - كلمات المرور مشفرة في _hashedPasswords)
  static const Map<String, Map<String, dynamic>> _fixedAccounts = {
    'admin': {
      'user_type': 'admin',
      'full_name': 'مدير النظام',
      'id': 1,
    },
    'm': {
      'user_type': 'supervisor',
      'full_name': 'محمد',
      'id': 2,
    },
    'ahmed': {
      'user_type': 'employee',
      'full_name': 'أحمد',
      'id': 3,
    },
    '1': {
      'user_type': 'supervisor',
      'full_name': 'محمد',
      'id': 4,
    },
  };

  /// تخزين كلمات المرور المشفرة (SHA-256 + salt)
  static final Map<String, String> _hashedPasswords = {
    'admin': PasswordHasher.hashPassword('admin'),
    'm': PasswordHasher.hashPassword('1'),
    'ahmed': PasswordHasher.hashPassword('2222'),
    '1': PasswordHasher.hashPassword('1'),
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
      AppLogger.warning('فشل قراءة الحسابات المخصصة المحفوظة', tag: 'AUTH', error: e, stackTrace: st);
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

  /// سحب المستخدمين من Appwrite Cloud (app_users collection)
  /// يعيد Map<username, account_data> أو فارغ عند الفشل
  Future<Map<String, Map<String, dynamic>>> loadCloudAccounts() async {
    try {
      final appwrite = AppwriteService();
      await appwrite.initialize();
      final docs = await appwrite.listDocuments(
        collectionId: 'app_users',
        useCache: false,
      );
      final cloudAccounts = <String, Map<String, dynamic>>{};
      for (final doc in docs) {
        final d = doc.data;
        final username = (d['username'] ?? '').toString().trim();
        if (username.isEmpty) continue;
        final active = d['active'];
        if (active == false) continue;
        cloudAccounts[username] = {
          'password': (d['password'] ?? '').toString(),
          'full_name': (d['full_name'] ?? username).toString(),
          'user_type': (d['user_type'] ?? 'employee').toString(),
          'id': doc.$id.hashCode, // استخدام hash كـ ID محلي
          'doc_id': doc.$id,
          'is_cloud': true,
          'permissions_json': (d['permissions'] ?? '[]').toString(),
        };
      }
      if (cloudAccounts.isNotEmpty) {
        AppLogger.debug(
          'Cloud users loaded: ${cloudAccounts.keys.join(', ')}',
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
    final fixedAccountData = _fixedAccounts[normalized];
    Map<String, dynamic>? account = fixedAccountData != null
        ? Map<String, dynamic>.from(fixedAccountData)
        : null;
    if (account == null) {
      account = await _getCustomAccount(normalized);
    }

    // 2️⃣ البحث في Appwrite Cloud
    if (account == null) {
      final cloudAccounts = await loadCloudAccounts();
      account = cloudAccounts[normalized];
    }

    if (account == null) {
      return null;
    }

    // التحقق من كلمة المرور باستخدام hashing
    bool passwordValid = false;
    if (account['is_cloud'] == true) {
      // الحسابات السحابية - كلمة المرور مخزنة مشفرة في Appwrite
      passwordValid = password == account['password'];
    } else if (_hashedPasswords.containsKey(normalized)) {
      // الحسابات الثابتة - استخدام كلمات المرور المشفرة
      passwordValid = PasswordHasher.verifyPassword(password, _hashedPasswords[normalized]!);
    } else {
      // fallback للمقارنة المباشرة (للتوافق مع الحسابات القديمة)
      final storedPassword = account['password']?.toString() ?? '';
      passwordValid = storedPassword == password;
    }

    if (!passwordValid) {
      return null;
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
      // حفظ credentials_version لمراقبة الجلسة
      try {
        final appwrite = AppwriteService();
        await appwrite.initialize();
        final docs = await appwrite.listDocuments(
          collectionId: 'app_users',
          useCache: false,
        );
        for (final doc in docs) {
          if ((doc.data['username']?.toString() ?? '') == normalized) {
            final version = doc.data['credentials_version'] as int? ?? 0;
            await saveCredentialsVersion(version);
            break;
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
    accounts[normalized] = {
      'password': password,
      'full_name': fullName,
      'user_type': userType,
      'id': id,
    };
    await _saveCustomAccounts(accounts);
    await setPermissions(normalized, permissions);

    // رفع المستخدم إلى Appwrite Cloud
    await _pushUserToCloud(
      username: normalized,
      password: password,
      fullName: fullName,
      userType: userType,
      permissions: permissions,
    );
  }

  /// رفع مستخدم إلى Appwrite Cloud
  Future<void> _pushUserToCloud({
    required String username,
    required String password,
    required String fullName,
    required String userType,
    required List<String> permissions,
  }) async {
    try {
      final appwrite = AppwriteService();
      await appwrite.initialize();
      final docId = 'user_$username';
      await appwrite.upsertDocument(
        collectionId: 'app_users',
        documentId: docId,
        data: {
          'username': username,
          'password': password,
          'full_name': fullName,
          'user_type': userType,
          'permissions': jsonEncode(permissions),
          'active': true,
          'last_login': 0,
          'credentials_version': 1,
        },
      );
      AppLogger.debug('User $username pushed to cloud', tag: 'AUTH');
    } catch (e) {
      AppLogger.warning(
        'Failed to push user $username to cloud',
        tag: 'AUTH',
        error: e,
      );
    }
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
      final appwrite = AppwriteService();
      await appwrite.initialize();

      // سحب المستند الحالي لمعرفة credentials_version الحالي
      final currentDoc = await appwrite.getDocument(
        collectionId: 'app_users',
        documentId: docId,
      );
      final currentVersion = currentDoc.data['credentials_version'] as int? ?? 0;
      final nextVersion = currentVersion + 1;

      final data = <String, dynamic>{
        'credentials_version': nextVersion,
      };

      if (newPassword != null) data['password'] = newPassword;
      if (newFullName != null) data['full_name'] = newFullName;
      if (newUserType != null) data['user_type'] = newUserType;
      if (newPermissions != null) data['permissions'] = jsonEncode(newPermissions);
      if (active != null) data['active'] = active;

      await appwrite.updateDocument(
        collectionId: 'app_users',
        documentId: docId,
        data: data,
      );

      AppLogger.info(
        'Cloud user $username updated (version $currentVersion → $nextVersion)',
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

  /// حذف مستخدم سحابي من Appwrite
  Future<bool> deleteCloudUser({
    required String docId,
  }) async {
    try {
      final appwrite = AppwriteService();
      await appwrite.initialize();
      await appwrite.deleteDocument(
        collectionId: 'app_users',
        documentId: docId,
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
      if (storedVersion == null) return true; // مستخدم محلي، لا تحقق

      final currentUser = await loadCurrentUser();
      if (currentUser == null) return true;

      final username = currentUser['username']?.toString() ?? '';
      if (username.isEmpty) return true;
      if (_fixedAccounts.containsKey(username)) return true; // hardcoded

      final appwrite = AppwriteService();
      await appwrite.initialize();
      final cloudAccounts = await loadCloudAccounts();
      final cloudAccount = cloudAccounts[username];
      if (cloudAccount == null) return true; // ليس مستخدم سحابي

      // سحب credentials_version من السحابة
      final docs = await appwrite.listDocuments(
        collectionId: 'app_users',
        useCache: false,
      );
      for (final doc in docs) {
        final d = doc.data;
        if ((d['username']?.toString() ?? '') == username) {
          final cloudVersion = d['credentials_version'] as int? ?? 0;
          if (cloudVersion != storedVersion) {
            AppLogger.warning(
              'Session invalid for $username: local=$storedVersion, cloud=$cloudVersion',
              tag: 'AUTH',
            );
            return false;
          }
          return true;
        }
      }
      return true;
    } catch (e) {
      AppLogger.warning('Session check failed (ignoring)', tag: 'AUTH', error: e);
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
        });
      }
    });

    // حسابات سحابية من Appwrite (app_users)
    try {
      final cloudAccounts = await loadCloudAccounts();
      final localUsernames = result
          .map((a) => a['username'].toString())
          .toSet();
      cloudAccounts.forEach((username, data) {
        // تجنب التكرار مع الحسابات المحلية
        if (!localUsernames.contains(username)) {
          result.add({
            'username': username,
            'full_name': data['full_name'] ?? username,
            'user_type': data['user_type'] ?? 'employee',
            'id': data['id'],
            'is_fixed': false,
            'is_cloud': true,
            'doc_id': data['doc_id'],
          });
        }
      });
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
    return prefs.getBool(_kRememberMe) ?? false;
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

  Future<void> setPermissions(String username, List<String> permissions) async {
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
        AppLogger.warning('فشل قراءة بيانات الأذونات المحفوظة', tag: 'AUTH', error: e, stackTrace: st);
      }
    }
    map[username] = permissions;
    await prefs.setString(_kPermissionsMap, jsonEncode(map));
    if (username == 'admin') {
      map[username] = ['all'];
    }

    // تحديث الصلاحيات في السحابة أيضاً
    await _updateCloudPermissions(username, permissions);
  }

  /// تحديث صلاحيات مستخدم سحابي في Appwrite
  Future<void> _updateCloudPermissions(
    String username,
    List<String> permissions,
  ) async {
    try {
      final appwrite = AppwriteService();
      await appwrite.initialize();
      final cloudAccounts = await loadCloudAccounts();
      final cloudAccount = cloudAccounts[username];
      if (cloudAccount == null) return;
      final docId = cloudAccount['doc_id'] as String?;
      if (docId == null) return;
      await appwrite.updateDocument(
        collectionId: 'app_users',
        documentId: docId,
        data: {
          'permissions': jsonEncode(permissions),
        },
      );
      AppLogger.debug(
        'Permissions updated for $username in cloud',
        tag: 'AUTH',
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to update cloud permissions for $username',
        tag: 'AUTH',
        error: e,
      );
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
        AppLogger.warning('فشل قراءة أسماء المستخدمين من الأذونات', tag: 'AUTH', error: e, stackTrace: st);
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
}
