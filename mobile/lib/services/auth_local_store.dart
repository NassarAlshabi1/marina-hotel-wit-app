import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AuthType { local }

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
    'employees',
    'expenses',
    'finance',
    'reports',
    'notes',
    'settings',
  ];

  static const Map<String, Map<String, dynamic>> _fixedAccounts = {
    'admin': {
      'password': 'admin',
      'user_type': 'admin',
      'full_name': 'مدير النظام',
      'id': 1,
    },
    'm': {
      'password': '1',
      'user_type': 'supervisor',
      'full_name': 'محمد',
      'id': 2,
    },
    'ahmed': {
      'password': '2222',
      'user_type': 'employee',
      'full_name': 'أحمد',
      'id': 3,
    },
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
                key.toString(), value.map((k, v) => MapEntry(k.toString(), v)));
          }
          return MapEntry(key.toString(), <String, dynamic>{});
        });
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load custom accounts: $e');
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

  Future<Map<String, dynamic>?> validateCredentials(
      String username, String password) async {
    final normalized = username.trim();
    Map<String, dynamic>? account = _fixedAccounts[normalized];
    account ??= await _getCustomAccount(normalized);
    if (account == null) {
      return null;
    }
    final storedPassword = account['password']?.toString() ?? '';
    if (storedPassword != password) {
      return null;
    }

    final perms =
        normalized == 'admin' ? ['all'] : await getPermissions(normalized);
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
  }

  Future<List<Map<String, dynamic>>> getAllAccountsDetailed() async {
    final result = <Map<String, dynamic>>[];
    _fixedAccounts.forEach((username, data) {
      result.add({
        'username': username,
        'full_name': data['full_name'] ?? username,
        'user_type': data['user_type'] ?? 'employee',
        'id': data['id'],
        'is_fixed': true,
      });
    });
    final customAccounts = await _loadCustomAccounts();
    customAccounts.forEach((username, rawData) {
      if (rawData is Map) {
        result.add({
          'username': username,
          'full_name': rawData['full_name'] ?? username,
          'user_type': rawData['user_type'] ?? 'employee',
          'id': rawData['id'],
          'is_fixed': false,
        });
      }
    });
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
    } catch (_) {
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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPermissionsMap);
    if (raw == null) return <String>[];
    try {
      final map = jsonDecode(raw);
      if (map is Map) {
        final v = map[username];
        if (v is List) {
          return v.map((e) => e.toString()).toList();
        }
      }
      return <String>[];
    } catch (_) {
      return <String>[];
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
      } catch (e) {
        debugPrint('⚠️ Failed to decode permissions map: $e');
      }
    }
    map[username] = permissions;
    await prefs.setString(_kPermissionsMap, jsonEncode(map));
    if (username == 'admin') {
      map[username] = ['all'];
    }
  }

  Future<List<String>> getAllUsernames() async {
    final names = <String>{..._fixedAccounts.keys};
    final custom = await _loadCustomAccounts();
    names.addAll(custom.keys.map((e) => e.toString()));
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
      } catch (e) {
        debugPrint('⚠️ Failed to decode permission names: $e');
      }
    }
    final list = names.toList();
    list.sort();
    return list;
  }

  Future<int> getUsersCount() async {
    final list = await getAllUsernames();
    return list.length;
  }
}
