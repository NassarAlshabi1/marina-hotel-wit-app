import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_config.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

class AppwriteConfigManager {
  static const String _endpointKey = 'appwrite_endpoint';
  static const String _projectIdKey = 'appwrite_project_id';
  static const String _databaseIdKey = 'appwrite_database_id';
  static const String _apiKey = 'appwrite_api_key';

  static String _endpoint = AppwriteConfig.endpoint;
  static String _projectId = AppwriteConfig.projectId;
  static String _databaseId = AppwriteConfig.databaseId;
  // ✅ استخدم مفتاح API الافتراضي المُدمج كقيمة ابتدائية.
  // عند أول تشغيل، _apiKeyValue = AppwriteConfig.defaultApiKey.
  // إذا أعاد المستخدم تعيينه لاحقاً، تُحفظ القيمة الجديدة في SharedPreferences
  // وتُحمَّل بدلاً من الافتراضي عند بدء التشغيل التالي.
  static String _apiKeyValue = AppwriteConfig.defaultApiKey;

  static String get endpoint => _endpoint;
  static String get projectId => _projectId;
  static String get databaseId => _databaseId;
  static String get apiKey => _apiKeyValue;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _endpoint = prefs.getString(_endpointKey) ?? AppwriteConfig.endpoint;
    _projectId = prefs.getString(_projectIdKey) ?? AppwriteConfig.projectId;
    _databaseId = prefs.getString(_databaseIdKey) ?? AppwriteConfig.databaseId;
    // ✅ إذا لم يُخزَّن مفتاح API في prefs، نستخدم المفتاح الافتراضي المُدمج.
    // هذا يضمن أن التطبيق يعمل "out-of-the-box" دون الحاجة لإدخال مفتاح يدوياً.
    _apiKeyValue = prefs.getString(_apiKey) ?? AppwriteConfig.defaultApiKey;

    if (kDebugMode) {
      dlog('📱 Appwrite Config Loaded:');
      dlog(() => '   Endpoint: $_endpoint');
      dlog(() => '   Project ID: $_projectId');
      dlog(() => '   Database ID: $_databaseId');
      dlog(
        () =>
            '   API Key: ${_apiKeyValue.isEmpty ? '(empty)' : '${_apiKeyValue.substring(0, 12)}...'}',
      );
    }
  }

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
      dlog('💾 Appwrite Config Saved:');
      dlog(() => '   Endpoint: $_endpoint');
      dlog(() => '   Project ID: $_projectId');
      dlog(() => '   Database ID: $_databaseId');
    }
  }

  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_endpointKey);
    await prefs.remove(_projectIdKey);
    await prefs.remove(_databaseIdKey);
    await prefs.remove(_apiKey);

    _endpoint = AppwriteConfig.endpoint;
    _projectId = AppwriteConfig.projectId;
    _databaseId = AppwriteConfig.databaseId;
    // ✅ إعادة التعيين تُعيد المفتاح الافتراضي المُدمج، لا قيمة فارغة
    _apiKeyValue = AppwriteConfig.defaultApiKey;

    if (kDebugMode) {
      dlog('🔄 Appwrite Config Reset to Defaults');
    }
  }

  static bool get isUsingCustomConfig {
    return _endpoint != AppwriteConfig.endpoint ||
        _projectId != AppwriteConfig.projectId ||
        _databaseId != AppwriteConfig.databaseId ||
        _apiKeyValue != AppwriteConfig.defaultApiKey;
  }

  static Map<String, String> get currentConfig => {
    'endpoint': _endpoint,
    'projectId': _projectId,
    'databaseId': _databaseId,
    'apiKey': _apiKeyValue,
  };

  static Map<String, String> get defaultConfig => {
    'endpoint': AppwriteConfig.endpoint,
    'projectId': AppwriteConfig.projectId,
    'databaseId': AppwriteConfig.databaseId,
    'apiKey': AppwriteConfig.defaultApiKey,
  };
}
