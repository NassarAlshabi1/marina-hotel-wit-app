import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

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
  // ✅ SECURITY: API key via --dart-define, NOT hardcoded.
  static const String defaultApiKey = String.fromEnvironment(
    'SECONDARY_APPWRITE_API_KEY',
  );
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
      dlog(() => '✅ Secondary Appwrite config saved (enabled=$enabled)');
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
      dlog('✅ Secondary Appwrite config restored to defaults');
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
      dlog('═══════════════════════════════════════');
      dlog('🔧 Secondary Appwrite Configuration');
      dlog('═══════════════════════════════════════');
      dlog(() => 'Enabled: $isEnabled');
      dlog(() => 'Configured: $isConfigured');
      dlog(() => 'Endpoint: $endpoint');
      dlog(() => 'Project ID: $projectId');
      dlog(() => 'Database ID: $databaseId');
      dlog(() => 'Push Enabled: $isPushEnabled');
      dlog(() => 'Pull Enabled: $isPullEnabled');
      dlog(() => 'Last Sync: $lastSyncTime');
      dlog(() => 'Status: $syncStatus');
      dlog('═══════════════════════════════════════');
    }
  }
}
