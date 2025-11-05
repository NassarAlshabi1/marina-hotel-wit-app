import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum AuthType { local, supabase, hybrid }

class AuthLocalStore {
  static const _kCurrentUser = 'current_user';
  static const _kPermissionsMap = 'user_permissions';
  static const _kRememberMe = 'remember_me';
  static const _kAuthType = 'auth_type';
  static const _kSupabaseSession = 'supabase_session';

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

  Future<Map<String, dynamic>?> validateCredentials(String username, String password) async {
    final user = _fixedAccounts[username.trim()];
    if (user == null) return null;
    if (user['password'] != password) return null;

    final perms = await getPermissions(username);
    if (username == 'admin') {
      return {
        'id': user['id'],
        'username': username,
        'full_name': user['full_name'],
        'user_type': user['user_type'],
        'permissions': ['all'],
      };
    }
    return {
      'id': user['id'],
      'username': username,
      'full_name': user['full_name'],
      'user_type': user['user_type'],
      'permissions': perms,
    };
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
      if (json is Map) return json.map((key, value) => MapEntry(key.toString(), value));
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = await getRememberMe();
    
    await prefs.remove(_kCurrentUser);
    await prefs.remove(_kSupabaseSession);
    
    // إذا كان "تذكرني" غير مفعل، امسح كل شيء
    if (!rememberMe) {
      await prefs.remove(_kRememberMe);
      await prefs.remove(_kAuthType);
    }
  }

  // دوال "تذكرني"
  Future<void> setRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRememberMe, value);
  }

  Future<bool> getRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kRememberMe) ?? false;
  }

  // دوال نوع المصادقة
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

  // دوال Supabase session
  Future<void> saveSupabaseSession(String sessionString) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSupabaseSession, sessionString);
  }

  Future<String?> loadSupabaseSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSupabaseSession);
    if (raw == null || raw.isEmpty) return null;
    return raw;
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
      } catch (_) {}
    }
    map[username] = permissions;
    await prefs.setString(_kPermissionsMap, jsonEncode(map));

    // If updating admin, keep 'all'
    if (username == 'admin') {
      map[username] = ['all'];
    }
  }
}