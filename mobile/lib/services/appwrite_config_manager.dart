import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_defaults.dart';

/// مدير إعدادات Appwrite - المصدر الوحيد للحقيقة
/// يحتوي على القيم الافتراضية ويدير التخزين والتحميل
class AppwriteConfigManager {
  // ═══════════════════════════════════════════════════════════════════
  // مفاتيح التخزين
  // ═══════════════════════════════════════════════════════════════════

  static const String _endpointKey = 'appwrite_endpoint';
  static const String _projectIdKey = 'appwrite_project_id';
  static const String _databaseIdKey = 'appwrite_database_id';
  static const String _apiKey = 'appwrite_api_key';

  // ═══════════════════════════════════════════════════════════════════
  // المتغيرات الداخلية - تبدأ بالقيم الافتراضية
  // ═══════════════════════════════════════════════════════════════════

  static String _endpoint = AppwriteDefaults.endpoint;
  static String _projectId = AppwriteDefaults.projectId;
  static String _databaseId = AppwriteDefaults.databaseId;
  static String _apiKeyValue = '';

  // ═══════════════════════════════════════════════════════════════════
  // Getters للوصول للق values الحالية
  // ═══════════════════════════════════════════════════════════════════

  static String get endpoint => _endpoint;
  static String get projectId => _projectId;
  static String get databaseId => _databaseId;
  static String get apiKey => _apiKeyValue;

  // ═══════════════════════════════════════════════════════════════════
  // Getters للقيم الافتراضية
  // ═══════════════════════════════════════════════════════════════════

  static String get defaultEndpoint => AppwriteDefaults.endpoint;
  static String get defaultProjectId => AppwriteDefaults.projectId;
  static String get defaultDatabaseId => AppwriteDefaults.databaseId;

  // ═══════════════════════════════════════════════════════════════════
  // التهيئة - تحميل الإعدادات المحفوظة أو استخدام الافتراضية
  // ═══════════════════════════════════════════════════════════════════

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _endpoint = prefs.getString(_endpointKey) ?? AppwriteDefaults.endpoint;
    _projectId = prefs.getString(_projectIdKey) ?? AppwriteDefaults.projectId;
    _databaseId = prefs.getString(_databaseIdKey) ?? AppwriteDefaults.databaseId;
    _apiKeyValue = prefs.getString(_apiKey) ?? '';

    if (kDebugMode) {
      debugPrint('📱 Appwrite Config Loaded:');
      debugPrint('   Endpoint: $_endpoint');
      debugPrint('   Project ID: $_projectId');
      debugPrint('   Database ID: $_databaseId');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // حفظ الإعدادات الجديدة
  // ═══════════════════════════════════════════════════════════════════

  static Future<void> saveConfig({
    required String endpoint,
    required String projectId,
    required String databaseId,
    required String apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_endpointKey, endpoint);
    await prefs.setString(_projectIdKey, projectId);
    await prefs.setString(_databaseIdKey, databaseId);
    await prefs.setString(_apiKey, apiKey);

    _endpoint = endpoint;
    _projectId = projectId;
    _databaseId = databaseId;
    _apiKeyValue = apiKey;

    if (kDebugMode) {
      debugPrint('💾 Appwrite Config Saved:');
      debugPrint('   Endpoint: $_endpoint');
      debugPrint('   Project ID: $_projectId');
      debugPrint('   Database ID: $_databaseId');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // إعادة التعيين للقيم الافتراضية
  // ═══════════════════════════════════════════════════════════════════

  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_endpointKey);
    await prefs.remove(_projectIdKey);
    await prefs.remove(_databaseIdKey);
    await prefs.remove(_apiKey);

    _endpoint = AppwriteDefaults.endpoint;
    _projectId = AppwriteDefaults.projectId;
    _databaseId = AppwriteDefaults.databaseId;
    _apiKeyValue = '';

    if (kDebugMode) {
      debugPrint('🔄 Appwrite Config Reset to Defaults');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // التحقق من استخدام إعدادات مخصصة
  // ═══════════════════════════════════════════════════════════════════

  static bool get isUsingCustomConfig {
    return _endpoint != AppwriteDefaults.endpoint ||
        _projectId != AppwriteDefaults.projectId ||
        _databaseId != AppwriteDefaults.databaseId ||
        _apiKeyValue.isNotEmpty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // الحصول على الإعدادات الحالية والافتراضية
  // ═══════════════════════════════════════════════════════════════════

  static Map<String, String> get currentConfig => {
    'endpoint': _endpoint,
    'projectId': _projectId,
    'databaseId': _databaseId,
    'apiKey': _apiKeyValue,
  };

  static Map<String, String> get defaultConfig => {
    'endpoint': AppwriteDefaults.endpoint,
    'projectId': AppwriteDefaults.projectId,
    'databaseId': AppwriteDefaults.databaseId,
    'apiKey': '',
  };
}
