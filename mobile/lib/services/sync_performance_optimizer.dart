import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import 'appwrite_config.dart';

/// مُحسِّن أداء المزامنة
/// يراقب حالة الاتصال ويحسن أداء المزامنة بناءً على نوع الشبكة
class SyncPerformanceOptimizer {
  factory SyncPerformanceOptimizer() => _instance;

  SyncPerformanceOptimizer._internal();
  static final SyncPerformanceOptimizer _instance =
      SyncPerformanceOptimizer._internal();

  // إضافة static getter instance للوصول للـ singleton
  static SyncPerformanceOptimizer get instance => _instance;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOnWiFi = false;
  bool _isInitialized = false;
  DateTime? _lastSyncTime;
  int _syncAttempts = 0;

  HttpClient? _cachedHttpClient;
  DateTime? _httpClientCreatedAt;
  static const Duration _httpClientTtl = Duration(minutes: 5);

  // إعدادات الأداء حسب نوع الشبكة
  static const Map<String, Map<String, dynamic>> _performanceSettings = {
    'wifi': {
      'batchSize': 80,
      'timeout': 25,
      'retryAttempts': 3,
      'syncInterval': 60, // ثواني
    },
    'mobile': {
      'batchSize': 15,
      'timeout': 12,
      'retryAttempts': 4,
      'syncInterval': 90, // ثواني
    },
    'none': {
      'batchSize': 0,
      'timeout': 0,
      'retryAttempts': 0,
      'syncInterval': 0,
    },
  };

  /// تهيئة مراقب الاتصال
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      // فحص حالة الاتصال الحالية
      final connectivity = Connectivity();
      final currentResults = await connectivity.checkConnectivity();
      _updateConnectivityStatus(currentResults);

      // الاشتراك في تغييرات حالة الاتصال
      _connectivitySubscription = connectivity.onConnectivityChanged.listen(
        _updateConnectivityStatus,
        onError: (Object error) {
          dlog(() => '❌ خطأ في مراقبة الاتصال: $error');
        },
      );

      _isInitialized = true;
      dlog('✅ تم تهيئة مُحسِّن أداء المزامنة بنجاح');
    } catch (e) {
      dlog(() => '❌ خطأ في تهيئة مُحسِّن أداء المزامنة: $e');
    }
  }

  /// إصلاح المشكلة الثالثة: تحديث دالة _updateConnectivityStatus للتعامل مع List<ConnectivityResult>
  void _updateConnectivityStatus(List<ConnectivityResult> results) {
    final wasOnWiFi = _isOnWiFi;

    // معالجة الحالات الاستثنائية (قائمة فارغة)
    if (results.isEmpty) {
      _isOnWiFi = false;
      dlog('⚠️ قائمة نتائج الاتصال فارغة - افتراض عدم وجود اتصال');
      return;
    }

    // البحث عن أفضل نوع اتصال متاح
    // ترتيب الأولوية: WiFi > Ethernet > Mobile > VPN > Bluetooth > Other
    if (results.contains(ConnectivityResult.wifi)) {
      _isOnWiFi = true;
    } else if (results.contains(ConnectivityResult.ethernet)) {
      _isOnWiFi = true; // نعامل الإيثرنت كشبكة سريعة مثل WiFi
    } else if (results.contains(ConnectivityResult.mobile)) {
      _isOnWiFi = false;
    } else if (results.contains(ConnectivityResult.vpn)) {
      _isOnWiFi = false; // VPN قد يكون بطيء
    } else if (results.contains(ConnectivityResult.none)) {
      _isOnWiFi = false;
    } else if (results.contains(ConnectivityResult.bluetooth)) {
      _isOnWiFi = false; // البلوتوث بطيء
    } else if (results.contains(ConnectivityResult.other)) {
      _isOnWiFi = false; // اتصال غير محدد - نفترض أنه بطيء
    } else {
      _isOnWiFi = false; // لا يوجد اتصال
    }

    // طباعة تفاصيل التغيير إذا حدث
    if (wasOnWiFi != _isOnWiFi) {
      final connectionType = _getConnectionTypeString(results);
      dlog(() => '📡 تغيير نوع الاتصال: $connectionType');
      dlog(() => '🔄 حالة WiFi: ${_isOnWiFi ? 'متصل' : 'غير متصل'}');

      // إعادة تعيين عداد المحاولات عند تغيير نوع الاتصال
      _syncAttempts = 0;
    }
  }

  /// الحصول على وصف نوع الاتصال
  String _getConnectionTypeString(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      return 'لا يوجد اتصال';
    }

    final List<String> types = [];
    for (final result in results) {
      switch (result) {
        case ConnectivityResult.wifi:
          types.add('WiFi');
        case ConnectivityResult.mobile:
          types.add('بيانات الهاتف');
        case ConnectivityResult.ethernet:
          types.add('إيثرنت');
        case ConnectivityResult.vpn:
          types.add('VPN');
        case ConnectivityResult.bluetooth:
          types.add('بلوتوث');
        case ConnectivityResult.satellite:
          types.add('قمر صناعي');
        case ConnectivityResult.other:
          types.add('أخرى');
        case ConnectivityResult.none:
          types.add('لا يوجد اتصال');
      }
    }
    return types.join(' + ');
  }

  @visibleForTesting
  void simulateConnectivity(List<ConnectivityResult> results) {
    _updateConnectivityStatus(results);
  }

  /// الحصول على إعدادات الأداء الحالية
  Map<String, dynamic> getCurrentPerformanceSettings() {
    final networkType = _isOnWiFi ? 'wifi' : 'mobile';
    return Map.from(_performanceSettings[networkType]!);
  }

  /// التحقق من إمكانية بدء المزامنة
  /// إصلاح المشكلة الثانية: إضافة async للدالة
  Future<bool> shouldSkipSync() async {
    // التحقق من وجود اتصال بالإنترنت
    if (!await _hasInternetConnection()) {
      dlog('⏭️ تم تخطي المزامنة: لا يوجد اتصال بالإنترنت');
      return true;
    }

    // التحقق من إعدادات WiFi Only
    if (await _isWifiOnlyEnabled() && !_isOnWiFi) {
      dlog('⏭️ تم تخطي المزامنة: مطلوب WiFi فقط');
      return true;
    }

    // التحقق من الحد الأدنى للفترة بين المزامنة
    if (_lastSyncTime != null) {
      final settings = getCurrentPerformanceSettings();
      final minInterval = Duration(seconds: settings['syncInterval'] as int);
      final timeSinceLastSync = DateTime.now().difference(_lastSyncTime!);

      if (timeSinceLastSync < minInterval) {
        dlog(
          () =>
              '⏭️ تم تخطي المزامنة: لم تمر الفترة المطلوبة بعد (${timeSinceLastSync.inSeconds}/${minInterval.inSeconds} ثانية)',
        );
        return true;
      }
    }

    // التحقق من عدد المحاولات الفاشلة
    final settings = getCurrentPerformanceSettings();
    if (_syncAttempts >= (settings['retryAttempts'] as num)) {
      // ✅ إصلاح: بدلاً من التخطي الدائم، نتحقق من مرور فترة cooldown
      const cooldownMinutes = 30;
      if (_lastSyncTime != null &&
          DateTime.now().difference(_lastSyncTime!).inMinutes >=
              cooldownMinutes) {
        dlog('🔄 انتهت فترة cooldown - إعادة تعيين المحاولات والمحاولة مجدداً');
        _syncAttempts = 0;
        return false;
      }
      dlog(
        () =>
            '⏭️ تم تخطي المزامنة: تم الوصول للحد الأقصى للمحاولات (cooldown $cooldownMinutes دقيقة)',
      );
      return true;
    }

    return false;
  }

  /// التحقق من وجود اتصال إنترنت فعلي
  Future<bool> _hasInternetConnection() async {
    // ✅ إعادة استخدام HttpClient بدلاً من إنشاء واحد جديد كل مرة
    final client = _getOrCreateHttpClient();
    try {
      final uri = Uri.parse(AppwriteConfig.endpoint);
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 2));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      await response.drain<void>();
      return response.statusCode < HttpStatus.internalServerError;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (e) {
      dlog(() => '❌ خطأ في فحص الاتصال: $e');
      return false;
    }
  }

  HttpClient _getOrCreateHttpClient() {
    final now = DateTime.now();
    if (_cachedHttpClient == null ||
        _httpClientCreatedAt == null ||
        now.difference(_httpClientCreatedAt!) > _httpClientTtl) {
      _cachedHttpClient?.close(force: true);
      _cachedHttpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      _httpClientCreatedAt = now;
    }
    return _cachedHttpClient!;
  }

  /// التحقق من إعدادات WiFi Only
  Future<bool> _isWifiOnlyEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('wifi_only_sync') ?? false;
    } catch (e) {
      dlog(() => '❌ خطأ في قراءة إعدادات WiFi Only: $e');
      return false;
    }
  }

  /// تسجيل محاولة مزامنة
  void recordSyncAttempt({required bool success}) {
    if (success) {
      _lastSyncTime = DateTime.now();
      _syncAttempts = 0;
      dlog('✅ تم تسجيل مزامنة ناجحة');
    } else {
      _syncAttempts++;
      dlog(
        () => '❌ تم تسجيل محاولة مزامنة فاشلة (المحاولة رقم $_syncAttempts)',
      );
    }
  }

  void updateConnectivityStatusForTest(List<ConnectivityResult> results) {
    _updateConnectivityStatus(results);
  }

  /// الحصول على حالة الاتصال الحالية
  bool get isOnWiFi => _isOnWiFi;

  /// الحصول على عدد المحاولات الحالي
  int get syncAttempts => _syncAttempts;

  /// الحصول على وقت آخر مزامنة
  DateTime? get lastSyncTime => _lastSyncTime;

  /// تحديث إعدادات WiFi Only
  Future<void> setWifiOnlyMode(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wifi_only_sync', enabled);
      dlog(() => '⚙️ تم تحديث إعدادات WiFi Only: ${enabled ? 'مفعل' : 'معطل'}');
    } catch (e) {
      dlog(() => '❌ خطأ في حفظ إعدادات WiFi Only: $e');
    }
  }

  /// إعادة تعيين عداد المحاولات
  void resetSyncAttempts() {
    _syncAttempts = 0;
    dlog('🔄 تم إعادة تعيين عداد المحاولات');
  }

  /// الحصول على إحصائيات الأداء
  Map<String, dynamic> getPerformanceStats() {
    return {
      'isOnWiFi': _isOnWiFi,
      'syncAttempts': _syncAttempts,
      'lastSyncTime': _lastSyncTime?.toIso8601String(),
      'currentSettings': getCurrentPerformanceSettings(),
    };
  }

  /// الحصول على حالة الأداء (مطلوب للشاشة)
  Map<String, dynamic> getPerformanceStatus() {
    return {
      'is_wifi_connected': _isOnWiFi,
      'sync_attempts': _syncAttempts,
      'last_sync_time': _lastSyncTime?.toIso8601String(),
      'connection_type': _isOnWiFi ? 'WiFi' : 'Mobile',
    };
  }

  /// إعداد الفترة التكيفية
  Future<void> setAdaptiveInterval(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('adaptive_interval_enabled', value);
      dlog(() => '⚙️ تم تحديث الفترة التكيفية: ${value ? 'مفعل' : 'معطل'}');
    } catch (e) {
      dlog(() => '❌ خطأ في حفظ إعدادات الفترة التكيفية: $e');
    }
  }

  /// إعداد تحسين البطارية
  Future<void> setBatteryOptimization(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('battery_optimization_enabled', value);
      dlog(() => '⚙️ تم تحديث تحسين البطارية: ${value ? 'مفعل' : 'معطل'}');
    } catch (e) {
      dlog(() => '❌ خطأ في حفظ إعدادات تحسين البطارية: $e');
    }
  }

  /// إعداد WiFi Only
  Future<void> setWifiOnlySync(bool value) async {
    await setWifiOnlyMode(value);
  }

  /// التحقق من تفعيل الفترة التكيفية
  Future<bool> isAdaptiveIntervalEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('adaptive_interval_enabled') ?? true;
    } catch (e) {
      dlog(() => '❌ خطأ في قراءة إعدادات الفترة التكيفية: $e');
      return true;
    }
  }

  /// التحقق من تفعيل تحسين البطارية
  Future<bool> isBatteryOptimizationEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('battery_optimization_enabled') ?? true;
    } catch (e) {
      dlog(() => '❌ خطأ في قراءة إعدادات تحسين البطارية: $e');
      return true;
    }
  }

  /// التحقق من تفعيل WiFi Only
  Future<bool> isWifiOnlyEnabled() async {
    return _isWifiOnlyEnabled();
  }

  /// حساب الفترة المحسنة للمزامنة بناءً على الأداء
  Future<int> calculateOptimizedInterval(int baseInterval) async {
    try {
      final isAdaptive = await isAdaptiveIntervalEnabled();
      if (!isAdaptive) {
        return baseInterval;
      }

      // تحسين الفترة حسب حالة الشبكة وعدد الفشل
      int optimizedInterval = baseInterval;

      // إذا كان على WiFi، قلل الفترة
      if (_isOnWiFi) {
        optimizedInterval = (baseInterval * 0.8).round().clamp(1, baseInterval);
      } else {
        // إذا كان على بيانات الهاتف، زد الفترة
        optimizedInterval = (baseInterval * 1.5).round();
      }

      // زيادة الفترة مع كل فشل متتالي
      if (_syncAttempts > 0) {
        optimizedInterval += _syncAttempts * 30; // إضافة 30 ثانية لكل فشل
      }

      dlog(
        () =>
            '🔧 فترة محسنة: ${optimizedInterval}s (أساسية: ${baseInterval}s، فشل: $_syncAttempts)',
      );
      return optimizedInterval;
    } catch (e) {
      dlog(() => '❌ خطأ في حساب الفترة المحسنة: $e');
      return baseInterval;
    }
  }

  /// تسجيل نجاح المزامنة
  void recordSyncSuccess() {
    recordSyncAttempt(success: true);
    dlog('✅ تم تسجيل مزامنة ناجحة');
  }

  /// تسجيل فشل المزامنة
  void recordSyncFailure() {
    recordSyncAttempt(success: false);
    dlog('❌ تم تسجيل فشل في المزامنة');
  }

  /// تنظيف الموارد
  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;
    _cachedHttpClient?.close(force: true);
    _cachedHttpClient = null;
    _httpClientCreatedAt = null;
    _isInitialized = false;
    dlog('🧹 تم تنظيف موارد مُحسِّن أداء المزامنة');
  }

  /// تنظيف الموارد الثابتة للـ singleton (يُستدعى عند إغلاق التطبيق)
  static Future<void> disposeInstance() async {
    _instance.dispose();
  }
}
