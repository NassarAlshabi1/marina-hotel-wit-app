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

  /// ✅ (2026-11-06) تطبيع Endpoint قبل الحفظ/الاختبار.
  ///
  /// **العطل المؤكد**: شاشة إعدادات الاتصال تحفظ النص كما هو، ولوحة تحكم
  /// Appwrite تعرض الـ Endpoint أحياناً بشرطة مائلة نهائية
  /// (`https://fra.cloud.appwrite.io/v1/`). عند نسخها كما هي يبني عميل
  /// Appwrite مسارات مزدوجة الشرطة (`/v1//databases/...`) فيرد الخادم 404،
  /// فيظهر "فشل الاتصال" مع أن كل القيم صحيحة. التطبيع هنا يجعل الحفظ
  /// والاختبار والتشغيل تستخدم الصيغة نفسها دائماً.
  static String normalizeEndpoint(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value.trim();
  }

  /// تطبيع معرّفات Appwrite (Project/Database): إزالة الفراغات الطرفية فقط —
  /// الفراغ الطرفي الناتج عن النسخ/اللصق يسبب 404 `project_not_found`.
  static String normalizeId(String raw) => raw.trim();

  /// بصمة هدف المزامنة الفعّال (Endpoint + Project + Database).
  /// مصدر واحد للحقيقة يستخدمه [AppwriteSyncManager] في حرس تغيير الهدف،
  /// حتى لا يختلف تنسيق البصمة بين الحفظ والفحص.
  static String get targetIdentity => '$_endpoint|$_projectId|$_databaseId';

  static String get endpoint => _endpoint;
  static String get projectId => _projectId;
  static String get databaseId => _databaseId;
  static String get apiKey => _apiKeyValue;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ (2026-11-06) القيم المخزَّنة من نسخ سابقة قد تكون بشرطة مائلة نهائية
    // أو فارغة؛ تُطبَّع عند التحميل حتى تُشفى الأجهزة المتأثرة تلقائياً.
    final storedEndpoint = normalizeEndpoint(
      prefs.getString(_endpointKey) ?? '',
    );
    final storedProjectId = normalizeId(prefs.getString(_projectIdKey) ?? '');
    final storedDatabaseId = normalizeId(prefs.getString(_databaseIdKey) ?? '');
    _endpoint = storedEndpoint.isEmpty
        ? AppwriteConfig.endpoint
        : storedEndpoint;
    _projectId = storedProjectId.isEmpty
        ? AppwriteConfig.projectId
        : storedProjectId;
    _databaseId = storedDatabaseId.isEmpty
        ? AppwriteConfig.databaseId
        : storedDatabaseId;
    // ✅ إذا لم يُخزَّن مفتاح API في prefs، نستخدم المفتاح الافتراضي المُدمج.
    // هذا يضمن أن التطبيق يعمل "out-of-the-box" دون الحاجة لإدخال مفتاح يدوياً.
    // ✅ (2026-11-06) مفتاح فارغ مخزَّن من نسخة سابقة يُعامل كغير مخزَّن،
    // وإلا بقي التطبيق بلا X-Appwrite-Key إلى الأبد (401 على كل طلب).
    final storedApiKey = (prefs.getString(_apiKey) ?? '').trim();
    _apiKeyValue = storedApiKey.isEmpty
        ? AppwriteConfig.defaultApiKey
        : storedApiKey;

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
    final normalizedEndpoint = normalizeEndpoint(endpoint);
    final normalizedProjectId = normalizeId(projectId);
    final normalizedDatabaseId = normalizeId(databaseId);
    final normalizedApiKey = apiKey.trim();

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_endpointKey, normalizedEndpoint);
    await prefs.setString(_projectIdKey, normalizedProjectId);
    await prefs.setString(_databaseIdKey, normalizedDatabaseId);

    // ✅ (2026-11-06) مفتاح API الفارغ لا يُحفظ أبداً.
    //
    // **العطل المؤكد**: الحفظ كان يكتب '' في prefs دائماً، و[init] يقرأ
    // `prefs.getString(_apiKey) ?? default` — و'' ليست null ⇒ يُلغي المفتاح
    // المُدمج (المُمرَّر بـ --dart-define) نهائياً. النتيجة: كل طلبات
    // Appwrite تخرج بلا ترويسة X-Appwrite-Key فتُرفض 401، والحقل يقول
    // "يُستخدم المفتاح الافتراضي تلقائياً" والشاشة تقول "تم الحفظ بنجاح".
    // الآن: فارغ ⇒ حذف المفتاح المخزَّن ⇒ الرجوع إلى المفتاح المُدمج.
    if (normalizedApiKey.isEmpty) {
      await prefs.remove(_apiKey);
    } else {
      await prefs.setString(_apiKey, normalizedApiKey);
    }

    _endpoint = normalizedEndpoint;
    _projectId = normalizedProjectId;
    _databaseId = normalizedDatabaseId;
    _apiKeyValue = normalizedApiKey.isEmpty
        ? AppwriteConfig.defaultApiKey
        : normalizedApiKey;

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
