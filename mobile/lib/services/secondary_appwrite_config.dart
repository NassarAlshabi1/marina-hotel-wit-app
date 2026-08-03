import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات الوجهة الثانوية لـ Appwrite (نسخة احتياطية/طوارئ)
///
/// الوجهة الثانوية تعمل بشكل مستقل عن الوجهة الرئيسية. الـ outbox المحلي
/// يُسلّم لكلا الوجهتين بالتوازي، ولا يُحذف السجل إلا بعد نجاح كليهما.
///
/// القيم الافتراضية (مدمجة في التطبيق — يُمكن للمستخدم تغييرها في أي وقت
/// من شاشة الإعدادات، أو استعادتها عبر زر "استعادة الافتراضي"):
///   - isEnabled = false (معطّل افتراضياً — المستخدم يُفعّله يدوياً عند الحاجة)
///   - isPushEnabled = false (الرفع معطّل افتراضياً)
///   - isPullEnabled = false (السحب معطّل افتراضياً)
///
/// ✅ تم التعطيل الافتراضي بناءً على طلب المستخدم لمنع الرفع المزدوج
///    غير المرغوب فيه لـ Primary + Secondary في الإعداد الافتراضي.
///    المستخدم يُفعّل Secondary يدوياً من شاشة الإعدادات عند الحاجة
///    لتشغيل نسخة احتياطية على Appwrite Cloud آخر.
class SecondaryAppwriteConfig {
  // ═══════════════════════════════════════════════════════════════════════
  //  القيم الافتراضية المُدمجة في التطبيق
  //  هذه القيم تُستخدم عندما لا يوجد إعداد محفوظ في SharedPreferences،
  //  ويُمكن للمستخدم تغييرها أو استعادتها في أي وقت.
  // ═══════════════════════════════════════════════════════════════════════
  static const String defaultEndpoint = 'https://fra.cloud.appwrite.io/v1';
  static const String defaultProjectId = '6a4408f300217885fd7b';
  static const String defaultDatabaseId = '6a4409b50019dd39dde5';
  static const String defaultApiKey =
      'standard_c0ab6ac2628715c7714eb312e2272a55ae41809dcc156c7e4553874e4a6ad9f3d3e9169d8a69b84f7d746b108905041e412a66ec66d03e122ccb056484c43d2a27f7839088bf60385ab58061624bbcc1f82271c09d608536e68d9cc0ff1b05b83ae4fe14c4dc4ce38840317ea555155f1733141450b3097df09a2a1b4b154a6c';
  static const bool defaultEnabled = false;
  static const bool defaultPushEnabled = false;
  static const bool defaultPullEnabled = false;

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
    return _prefs!.getBool(_keyEnabled) ?? defaultEnabled;
  }

  static bool get isConfigured {
    ensureInitializedSync();
    final endpoint = _prefs!.getString(_keyEndpoint) ?? defaultEndpoint;
    final projectId = _prefs!.getString(_keyProjectId) ?? defaultProjectId;
    final databaseId = _prefs!.getString(_keyDatabaseId) ?? defaultDatabaseId;
    return endpoint.isNotEmpty && projectId.isNotEmpty && databaseId.isNotEmpty;
  }

  static String get endpoint {
    ensureInitializedSync();
    return _prefs!.getString(_keyEndpoint) ?? defaultEndpoint;
  }

  static String get projectId {
    ensureInitializedSync();
    return _prefs!.getString(_keyProjectId) ?? defaultProjectId;
  }

  static String get databaseId {
    ensureInitializedSync();
    return _prefs!.getString(_keyDatabaseId) ?? defaultDatabaseId;
  }

  static String get apiKey {
    ensureInitializedSync();
    return _prefs!.getString(_keyApiKey) ?? defaultApiKey;
  }

  static bool get isPushEnabled {
    ensureInitializedSync();
    return _prefs!.getBool(_keyPushEnabled) ?? defaultPushEnabled;
  }

  static bool get isPullEnabled {
    ensureInitializedSync();
    return _prefs!.getBool(_keyPullEnabled) ?? defaultPullEnabled;
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

  /// استعادة القيم الافتراضية المُدمجة في التطبيق.
  ///
  /// تُستخدم عند رغبة المستخدم في العودة للإعدادات الأصلية بعد تجربة قيم
  /// مختلفة. تُعيد الكتابة فوق أي قيم محفوظة سابقاً.
  static Future<void> restoreDefaults() async {
    await ensureInitialized();
    await Future.wait([
      _prefs!.setBool(_keyEnabled, defaultEnabled),
      _prefs!.setString(_keyEndpoint, defaultEndpoint),
      _prefs!.setString(_keyProjectId, defaultProjectId),
      _prefs!.setString(_keyDatabaseId, defaultDatabaseId),
      _prefs!.setString(_keyApiKey, defaultApiKey),
      _prefs!.setBool(_keyPushEnabled, defaultPushEnabled),
      _prefs!.setBool(_keyPullEnabled, defaultPullEnabled),
    ]);
    if (kDebugMode) {
      debugPrint('✅ Secondary Appwrite config restored to defaults');
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
