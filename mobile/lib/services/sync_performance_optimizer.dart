import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';

import 'sync_performance_settings.dart';

/// مُحسِّن أداء المزامنة
/// يراقب حالة الاتصال ويحسن أداء المزامنة بناءً على نوع الشبكة
class SyncPerformanceOptimizer {

  factory SyncPerformanceOptimizer() => _instance;

  SyncPerformanceOptimizer._internal();
  static final SyncPerformanceOptimizer _instance =
      SyncPerformanceOptimizer._internal();

  // إضافة static getter instance للوصول للـ singleton
  static SyncPerformanceOptimizer get instance => _instance;

  // إصلاح المشكلة الأولى: تغيير نوع البيانات من ConnectivityResult إلى List<ConnectivityResult>
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOnWiFi = false;
  bool _isInitialized = false;
  DateTime? _lastSyncTime;
  DateTime? _lastAttemptTime;
  int _syncAttempts = 0;
  int _performanceLevel = 2; // 1=high, 2=medium, 3=low-end

  // إعدادات الأداء حسب نوع الشبكة ومستوى الأداء
  static const Map<int, Map<String, Map<String, dynamic>>> _performanceSettings = {
    1: { // High performance
      'wifi': {'batchSize': 100, 'timeout': 30, 'retryAttempts': 3, 'syncInterval': 60},
      'mobile': {'batchSize': 50, 'timeout': 15, 'retryAttempts': 2, 'syncInterval': 120},
      'none': {'batchSize': 0, 'timeout': 0, 'retryAttempts': 0, 'syncInterval': 0},
    },
    2: { // Medium (default)
      'wifi': {'batchSize': 75, 'timeout': 45, 'retryAttempts': 3, 'syncInterval': 90},
      'mobile': {'batchSize': 35, 'timeout': 20, 'retryAttempts': 2, 'syncInterval': 180},
      'none': {'batchSize': 0, 'timeout': 0, 'retryAttempts': 0, 'syncInterval': 0},
    },
    3: { // Low-end devices - reduced batch, longer intervals, fewer retries
      'wifi': {'batchSize': 30, 'timeout': 60, 'retryAttempts': 2, 'syncInterval': 180},
      'mobile': {'batchSize': 15, 'timeout': 30, 'retryAttempts': 1, 'syncInterval': 300},
      'none': {'batchSize': 0, 'timeout': 0, 'retryAttempts': 0, 'syncInterval': 0},
    },
  };

  /// تهيئة مراقب الاتصال — تفعيل متوازن بشكل دائم
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      // تحميل مستوى الأداء — دائماً متوازن
      await _loadPerformanceLevel();

      // تطبيق إعدادات "متوازن" من SyncPerformanceSettings
      await SyncPerformanceSettings.applyProfile('balanced');

      // فحص حالة الاتصال الحالية
      final connectivity = Connectivity();
      final currentResults = await connectivity.checkConnectivity();
      _updateConnectivityStatus(currentResults);

      // الاشتراك في تغييرات حالة الاتصال
      _connectivitySubscription = connectivity.onConnectivityChanged.listen(
        _updateConnectivityStatus,
        onError: (Object error) {
          AppLogger.warning('❌ خطأ في مراقبة الاتصال: $error', tag: 'APP');
        },
      );

      _isInitialized = true;
      AppLogger.info('✅ تم تهيئة مُحسِّن أداء المزامنة (مستوى: متوازن - مثبت دائماً)', tag: 'APP');
    } catch (e) {
      AppLogger.warning('❌ خطأ في تهيئة مُحسِّن أداء المزامنة: $e', tag: 'APP');
    }
  }

  /// إصلاح المشكلة الثالثة: تحديث دالة _updateConnectivityStatus للتعامل مع List<ConnectivityResult>
  void _updateConnectivityStatus(List<ConnectivityResult> results) {
    final wasOnWiFi = _isOnWiFi;

    // معالجة الحالات الاستثنائية (قائمة فارغة)
    if (results.isEmpty) {
      _isOnWiFi = false;
      AppLogger.warning('⚠️ قائمة نتائج الاتصال فارغة - افتراض عدم وجود اتصال', tag: 'APP');
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
      AppLogger.info('📡 تغيير نوع الاتصال: $connectionType', tag: 'APP');
      AppLogger.info(
  '🔄 حالة WiFi: ${_isOnWiFi ? 'متصل' : 'غير متصل'}',
  tag: 'APP',
);

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
    final levelSettings = _performanceSettings[_performanceLevel] ?? _performanceSettings[2]!;
    return Map.from(levelSettings[networkType]!);
  }

  /// تعيين مستوى الأداء — دائماً "متوازن" (المستوى 2) بشكل دائم
  Future<void> setPerformanceLevel(int level) async {
    _performanceLevel = 2; // دائماً متوازن
    final prefs = getSharedPrefs();
    await prefs.setInt('performance_level', 2);
    AppLogger.info('⚙️ مستوى الأداء مثبت على: متوازن (2)', tag: 'APP');
  }

  /// الحصول على مستوى الأداء الحالي
  int get performanceLevel => _performanceLevel;

  /// تحميل مستوى الأداء — دائماً "متوازن" (المستوى 2)
  Future<void> _loadPerformanceLevel() async {
    // تفعيل متوازن بشكل دائم — لا نقرأ من SharedPreferences
    _performanceLevel = 2;
    // نحفظه أيضاً للتأكد من التطابق مع SyncPerformanceSettings
    try {
      final prefs = getSharedPrefs();
      await prefs.setInt('performance_level', 2);
    } catch (e) { AppLogger.warning('⚠️ silent catch', tag: 'SYNC', error: e);}
  }

  /// التحقق من إمكانية بدء المزامنة
  /// إصلاح المشكلة الثانية: إضافة async للدالة
  Future<bool> shouldSkipSync() async {
    // التحقق من وجود اتصال بالإنترنت
    if (!await _hasInternetConnection()) {
      AppLogger.warning('⏭️ تم تخطي المزامنة: لا يوجد اتصال بالإنترنت', tag: 'APP');
      return true;
    }

    // التحقق من إعدادات WiFi Only
    if (await _isWifiOnlyEnabled() && !_isOnWiFi) {
      AppLogger.warning('⏭️ تم تخطي المزامنة: مطلوب WiFi فقط', tag: 'APP');
      return true;
    }

    // التحقق من الحد الأدنى للفترة بين المزامنة
    if (_lastSyncTime != null) {
      final settings = getCurrentPerformanceSettings();
      final minInterval = Duration(seconds: settings['syncInterval'] as int);
      final timeSinceLastSync = DateTime.now().difference(_lastSyncTime!);

      if (timeSinceLastSync < minInterval) {
        AppLogger.warning(
  '⏭️ تم تخطي المزامنة: لم تمر الفترة المطلوبة بعد (${timeSinceLastSync.inSeconds}/${minInterval.inSeconds} ثانية)',
  tag: 'APP',
);
        return true;
      }
    }

    // التحقق من عدد المحاولات الفاشلة
    final settings = getCurrentPerformanceSettings();
    if (_syncAttempts >= (settings['retryAttempts'] as num)) {
      // ✅ إصلاح: نتحقق من مرور فترة cooldown منذ آخر محاولة (وليس آخر نجاح)
      const cooldownMinutes = 30;
      if (_lastAttemptTime != null &&
          DateTime.now().difference(_lastAttemptTime!).inMinutes >= cooldownMinutes) {
        AppLogger.info('🔄 انتهت فترة cooldown - إعادة تعيين المحاولات والمحاولة مجدداً', tag: 'APP');
        _syncAttempts = 0;
        return false;
      }
      AppLogger.warning('⏭️ تم تخطي المزامنة: تم الوصول للحد الأقصى للمحاولات (cooldown $cooldownMinutes دقيقة)', tag: 'APP');
      return true;
    }

    return false;
  }

  /// التحقق من وجود اتصال إنترنت فعلي
  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (e) { AppLogger.warning('⚠️ silent catch', tag: 'SYNC', error: e);
      return false;
    } on TimeoutException catch (e) { AppLogger.warning('⚠️ silent catch', tag: 'SYNC', error: e);
      return false;
    } catch (e) {
      AppLogger.warning('❌ خطأ في فحص الاتصال: $e', tag: 'APP');
      return false;
    }
  }

  /// التحقق من إعدادات WiFi Only
  Future<bool> _isWifiOnlyEnabled() async {
    try {
      final prefs = getSharedPrefs();
      return prefs.getBool('wifi_only_sync') ?? false;
    } catch (e) {
      AppLogger.warning('❌ خطأ في قراءة إعدادات WiFi Only: $e', tag: 'APP');
      return false;
    }
  }

  /// تسجيل محاولة مزامنة
  void recordSyncAttempt({required bool success}) {
    _lastAttemptTime = DateTime.now();
    if (success) {
      _lastSyncTime = DateTime.now();
      _syncAttempts = 0;
      AppLogger.info('✅ تم تسجيل مزامنة ناجحة', tag: 'APP');
    } else {
      _syncAttempts++;
      AppLogger.error(
  '❌ تم تسجيل محاولة مزامنة فاشلة (المحاولة رقم $_syncAttempts)',
  tag: 'APP',
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
      final prefs = getSharedPrefs();
      await prefs.setBool('wifi_only_sync', enabled);
      AppLogger.info(
  '⚙️ تم تحديث إعدادات WiFi Only: ${enabled ? 'مفعل' : 'معطل'}',
  tag: 'APP',
);
    } catch (e) {
      AppLogger.warning('❌ خطأ في حفظ إعدادات WiFi Only: $e', tag: 'APP');
    }
  }

  /// إعادة تعيين عداد المحاولات
  void resetSyncAttempts() {
    _syncAttempts = 0;
    AppLogger.info('🔄 تم إعادة تعيين عداد المحاولات', tag: 'APP');
  }

  /// الحصول على إحصائيات الأداء
  Map<String, dynamic> getPerformanceStats() {
    return {
      'isOnWiFi': _isOnWiFi,
      'syncAttempts': _syncAttempts,
      'lastSyncTime': _lastSyncTime?.toIso8601String(),
      'lastAttemptTime': _lastAttemptTime?.toIso8601String(),
      'currentSettings': getCurrentPerformanceSettings(),
    };
  }

  /// الحصول على حالة الأداء (مطلوب للشاشة)
  Map<String, dynamic> getPerformanceStatus() {
    return {
      'is_wifi_connected': _isOnWiFi,
      'sync_attempts': _syncAttempts,
      'last_sync_time': _lastSyncTime?.toIso8601String(),
      'last_attempt_time': _lastAttemptTime?.toIso8601String(),
      'connection_type': _isOnWiFi ? 'WiFi' : 'Mobile',
    };
  }

  /// إعداد الفترة التكيفية
  Future<void> setAdaptiveInterval(bool value) async {
    try {
      final prefs = getSharedPrefs();
      await prefs.setBool('adaptive_interval_enabled', value);
      AppLogger.info(
  '⚙️ تم تحديث الفترة التكيفية: ${value ? 'مفعل' : 'معطل'}',
  tag: 'APP',
);
    } catch (e) {
      AppLogger.warning('❌ خطأ في حفظ إعدادات الفترة التكيفية: $e', tag: 'APP');
    }
  }

  /// إعداد تحسين البطارية
  Future<void> setBatteryOptimization(bool value) async {
    try {
      final prefs = getSharedPrefs();
      await prefs.setBool('battery_optimization_enabled', value);
      AppLogger.info(
  '⚙️ تم تحديث تحسين البطارية: ${value ? 'مفعل' : 'معطل'}',
  tag: 'APP',
);
    } catch (e) {
      AppLogger.warning('❌ خطأ في حفظ إعدادات تحسين البطارية: $e', tag: 'APP');
    }
  }

  /// إعداد WiFi Only
  Future<void> setWifiOnlySync(bool value) async {
    await setWifiOnlyMode(value);
  }

  /// التحقق من تفعيل الفترة التكيفية
  Future<bool> isAdaptiveIntervalEnabled() async {
    try {
      final prefs = getSharedPrefs();
      return prefs.getBool('adaptive_interval_enabled') ?? true;
    } catch (e) {
      AppLogger.warning('❌ خطأ في قراءة إعدادات الفترة التكيفية: $e', tag: 'APP');
      return true;
    }
  }

  /// التحقق من تفعيل تحسين البطارية
  Future<bool> isBatteryOptimizationEnabled() async {
    try {
      final prefs = getSharedPrefs();
      return prefs.getBool('battery_optimization_enabled') ?? true;
    } catch (e) {
      AppLogger.warning('❌ خطأ في قراءة إعدادات تحسين البطارية: $e', tag: 'APP');
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

      AppLogger.warning(
  '🔧 فترة محسنة: ${optimizedInterval}s (أساسية: ${baseInterval}s، فشل: $_syncAttempts)',
  tag: 'APP',
);
      return optimizedInterval;
    } catch (e) {
      AppLogger.warning('❌ خطأ في حساب الفترة المحسنة: $e', tag: 'APP');
      return baseInterval;
    }
  }

  /// تسجيل نجاح المزامنة
  void recordSyncSuccess() {
    recordSyncAttempt(success: true);
    AppLogger.info('✅ تم تسجيل مزامنة ناجحة', tag: 'APP');
  }

  /// تسجيل فشل المزامنة
  void recordSyncFailure() {
    recordSyncAttempt(success: false);
    AppLogger.warning('❌ تم تسجيل فشل في المزامنة', tag: 'APP');
  }

  /// تنظيف الموارد
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isInitialized = false;
    AppLogger.info('🧹 تم تنظيف موارد مُحسِّن أداء المزامنة', tag: 'APP');
  }

  /// تنظيف الموارد الثابتة للـ singleton (يُستدعى عند إغلاق التطبيق)
  static Future<void> disposeInstance() async {
    _instance.dispose();
  }
}
