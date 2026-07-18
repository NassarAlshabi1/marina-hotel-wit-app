import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات الوجهة الثانوية لـ Appwrite (نسخة احتياطية/طوارئ)
///
/// الوجهة الثانوية تعمل بشكل مستقل عن الوجهة الرئيسية. الـ outbox المحلي
/// يُسلّم لكلا الوجهتين بالتوازي، ولا يُحذف السجل إلا بعد نجاح كليهما.
///
/// القيم الافتراضية:
///   - isEnabled = false (يجب تفعيلها يدوياً من شاشة الإعدادات)
///   - isPushEnabled = true (الرفع مُفعّل افتراضياً عند تفعيل Secondary)
///   - isPullEnabled = false (السحب معطّل افتراضياً — يحتاج تطبيقاً منفصلاً)
class SecondaryAppwriteConfig {
  static const String _keyEnabled = 'secondary_appwrite_enabled';
  static const String _keyEndpoint = 'secondary_appwrite_endpoint';
  static const String _keyProjectId = 'secondary_appwrite_project_id';
  static const String _keyDatabaseId = 'secondary_appwrite_database_id';
  static const String _keyApiKey = 'secondary_appwrite_api_key';
  static const String _keyPushEnabled = 'secondary_appwrite_push_enabled';
  static const String _keyPullEnabled = 'secondary_appwrite_pull_enabled';
  static const String _keyLastSync = 'secondary_appwrite_last_sync';
  static const String _keySyncStatus = 'secondary_appwrite_sync_status';
  static const String _keyFailoverActive = 'secondary_appwrite_failover_active';

  static SharedPreferences? _prefs;

  /// تهيئة الكاش (يُستدعى مرة واحدة عند بدء التطبيق)
  static Future<void> ensureInitialized() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ── Getters ──

  static bool get isEnabled {
    ensureInitializedSync();
    return _prefs!.getBool(_keyEnabled) ?? false;
  }

  static bool get isConfigured {
    ensureInitializedSync();
    final endpoint = _prefs!.getString(_keyEndpoint) ?? '';
    final projectId = _prefs!.getString(_keyProjectId) ?? '';
    final databaseId = _prefs!.getString(_keyDatabaseId) ?? '';
    return endpoint.isNotEmpty && projectId.isNotEmpty && databaseId.isNotEmpty;
  }

  static String get endpoint {
    ensureInitializedSync();
    return _prefs!.getString(_keyEndpoint) ?? '';
  }

  static String get projectId {
    ensureInitializedSync();
    return _prefs!.getString(_keyProjectId) ?? '';
  }

  static String get databaseId {
    ensureInitializedSync();
    return _prefs!.getString(_keyDatabaseId) ?? '';
  }

  static String get apiKey {
    ensureInitializedSync();
    return _prefs!.getString(_keyApiKey) ?? '';
  }

  static bool get isPushEnabled {
    ensureInitializedSync();
    return _prefs!.getBool(_keyPushEnabled) ?? true;
  }

  static bool get isPullEnabled {
    ensureInitializedSync();
    return _prefs!.getBool(_keyPullEnabled) ?? false;
  }

  static DateTime? get lastSyncTime {
    ensureInitializedSync();
    final ts = _prefs!.getInt(_keyLastSync);
    return ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
  }

  static String get syncStatus {
    ensureInitializedSync();
    return _prefs!.getString(_keySyncStatus) ?? 'never';
  }

  /// هل تجاوز الفشل (Failover) مُفعّل؟
  static bool get isFailoverActive {
    ensureInitializedSync();
    return _prefs!.getBool(_keyFailoverActive) ?? false;
  }

  /// تفعيل/تعطيل تجاوز الفشل
  static Future<void> setFailoverActive(bool active) async {
    await ensureInitialized();
    await _prefs!.setBool(_keyFailoverActive, active);
  }

  // ── Setters ──

  static Future<void> saveConfig({
    required bool enabled,
    required String endpoint,
    required String projectId,
    required String databaseId,
    required String apiKey,
    required bool pushEnabled,
    required bool pullEnabled,
  }) async {
    await ensureInitialized();
    await Future.wait([
      _prefs!.setBool(_keyEnabled, enabled),
      _prefs!.setString(_keyEndpoint, endpoint.trim()),
      _prefs!.setString(_keyProjectId, projectId.trim()),
      _prefs!.setString(_keyDatabaseId, databaseId.trim()),
      _prefs!.setString(_keyApiKey, apiKey.trim()),
      _prefs!.setBool(_keyPushEnabled, pushEnabled),
      _prefs!.setBool(_keyPullEnabled, pullEnabled),
    ]);
    if (kDebugMode) {
      debugPrint('✅ Secondary Appwrite config saved (enabled=$enabled)');
    }
  }

  static Future<void> updateLastSync() async {
    await ensureInitialized();
    await _prefs!.setInt(_keyLastSync, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> updateSyncStatus(String status) async {
    await ensureInitialized();
    await _prefs!.setString(_keySyncStatus, status);
  }

  static Future<void> clear() async {
    await ensureInitialized();
    await Future.wait([
      _prefs!.remove(_keyEnabled),
      _prefs!.remove(_keyEndpoint),
      _prefs!.remove(_keyProjectId),
      _prefs!.remove(_keyDatabaseId),
      _prefs!.remove(_keyApiKey),
      _prefs!.remove(_keyPushEnabled),
      _prefs!.remove(_keyPullEnabled),
      _prefs!.remove(_keyLastSync),
      _prefs!.remove(_keySyncStatus),
      _prefs!.remove(_keyFailoverActive),
    ]);
  }

  /// ضمان تهيئة _prefs بشكل متزامن.
  ///
  /// ⚠️ يجب استدعاء [ensureInitialized] بشكل async مرة واحدة عند بدء التطبيق
  /// (يتم ذلك في main.dart). إذا تم الوصول لـ getters قبل التهيئة، يتم رمي
  /// [StateError] بدلاً من إرجاع قيم خاطئة صامتة.
  static void ensureInitializedSync() {
    if (_prefs == null) {
      throw StateError(
        'SecondaryAppwriteConfig not initialized. '
        'Call SecondaryAppwriteConfig.ensureInitialized() during app startup.',
      );
    }
  }

  /// طباعة الإعدادات للتشخيص
  static void printConfig() {
    if (kDebugMode) {
      debugPrint('═══════════════════════════════════════');
      debugPrint('🔧 Secondary Appwrite Configuration');
      debugPrint('═══════════════════════════════════════');
      debugPrint('Enabled: $isEnabled');
      debugPrint('Configured: $isConfigured');
      debugPrint('Endpoint: $endpoint');
      debugPrint('Project ID: $projectId');
      debugPrint('Database ID: $databaseId');
      debugPrint('Push Enabled: $isPushEnabled');
      debugPrint('Pull Enabled: $isPullEnabled');
      debugPrint('Last Sync: $lastSyncTime');
      debugPrint('Status: $syncStatus');
      debugPrint('═══════════════════════════════════════');
    }
  }
}
