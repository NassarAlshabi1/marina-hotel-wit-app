import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مُحسِّن الأداء والبطارية للمزامنة الذكية
class SyncPerformanceOptimizer {
  static SyncPerformanceOptimizer? _instance;
  static SyncPerformanceOptimizer get instance => _instance ??= SyncPerformanceOptimizer._();
  
  SyncPerformanceOptimizer._();

  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _batteryCheckTimer;
  
  // إعدادات الأداء
  bool _isLowPowerMode = false;
  bool _isOnWiFi = false;
  bool _isBatteryLow = false;
  int _consecutiveFailures = 0;
  
  static const String _prefsAdaptiveIntervalKey = 'sync_adaptive_interval';
  static const String _prefsBatteryOptimizationKey = 'sync_battery_optimization';
  static const String _prefsWifiOnlyKey = 'sync_wifi_only';
  static const String _prefsLowPowerModeKey = 'sync_low_power_mode';
  
  static const int _maxConsecutiveFailures = 3;
  static const int _baseInterval = 5; // دقائق
  static const int _maxInterval = 60; // دقائق
  static const int _minInterval = 1; // دقيقة

  /// تهيئة مُحسِّن الأداء
  Future<void> initialize() async {
    await _loadSettings();
    await _setupConnectivityMonitoring();
    await _setupBatteryMonitoring();
    
    debugPrint('⚡ مُحسِّن أداء المزامنة: تم التهيئة');
  }

  /// تحميل إعدادات الأداء
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isLowPowerMode = prefs.getBool(_prefsLowPowerModeKey) ?? false;
    debugPrint('🔋 وضع توفير الطاقة: $_isLowPowerMode');
  }

  /// إعداد مراقبة الاتصال
  Future<void> _setupConnectivityMonitoring() async {
    // فحص الاتصال الحالي
    final connectivity = Connectivity();
    final currentStatus = await connectivity.checkConnectivity();
    _updateConnectivityStatus(currentStatus);
    
    // مراقبة تغييرات الاتصال
    _connectivitySubscription = connectivity.onConnectivityChanged.listen(
      _updateConnectivityStatus,
    );
  }

  /// تحديث حالة الاتصال
  void _updateConnectivityStatus(ConnectivityResult status) {
    final wasOnWiFi = _isOnWiFi;
    _isOnWiFi = status == ConnectivityResult.wifi;
    
    if (wasOnWiFi != _isOnWiFi) {
      debugPrint('📡 تغيير نوع الاتصال: ${_isOnWiFi ? "WiFi" : "Mobile Data"}');
    }
  }

  /// إعداد مراقبة البطارية (محاكاة)
  Future<void> _setupBatteryMonitoring() async {
    // مراقبة دورية لحالة البطارية (كل 30 دقيقة)
    _batteryCheckTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _checkBatteryStatus(),
    );
  }

  /// فحص حالة البطارية (محاكاة)
  Future<void> _checkBatteryStatus() async {
    // محاكاة فحص البطارية - يمكن استخدام battery_plus في المستقبل
    final random = Random();
    final simulatedBatteryLevel = random.nextInt(100);
    
    final wasBatteryLow = _isBatteryLow;
    _isBatteryLow = simulatedBatteryLevel < 20;
    
    if (wasBatteryLow != _isBatteryLow) {
      debugPrint('🔋 حالة البطارية: ${_isBatteryLow ? "منخفضة" : "عادية"} ($simulatedBatteryLevel%)');
    }
  }

  /// حساب فترة المزامنة المُحسَّنة
  int calculateOptimizedInterval(int baseInterval) {
    int optimizedInterval = baseInterval;
    
    // زيادة الفترة في وضع توفير الطاقة
    if (_isLowPowerMode) {
      optimizedInterval *= 3;
      debugPrint('🔋 وضع توفير الطاقة: زيادة الفترة إلى $optimizedInterval دقائق');
    }
    
    // زيادة الفترة عند انخفاض البطارية
    if (_isBatteryLow) {
      optimizedInterval *= 2;
      debugPrint('🔋 بطارية منخفضة: زيادة الفترة إلى $optimizedInterval دقائق');
    }
    
    // تقليل الفترة عند استخدام WiFi
    if (_isOnWiFi && !_isLowPowerMode && !_isBatteryLow) {
      optimizedInterval = (optimizedInterval * 0.8).round();
      debugPrint('📡 WiFi متاح: تقليل الفترة إلى $optimizedInterval دقائق');
    }
    
    // زيادة الفترة تدريجياً عند فشل متكرر
    if (_consecutiveFailures > 0) {
      final multiplier = 1 + (_consecutiveFailures * 0.5);
      optimizedInterval = (optimizedInterval * multiplier).round();
      debugPrint('❌ فشل متكرر ($_consecutiveFailures): زيادة الفترة إلى $optimizedInterval دقائق');
    }
    
    // تطبيق الحدود الدنيا والعليا
    optimizedInterval = optimizedInterval.clamp(_minInterval, _maxInterval);
    
    return optimizedInterval;
  }

  /// تسجيل نجاح المزامنة
  void recordSyncSuccess() {
    if (_consecutiveFailures > 0) {
      debugPrint('✅ نجحت المزامنة بعد $_consecutiveFailures فشل');
      _consecutiveFailures = 0;
    }
  }

  /// تسجيل فشل المزامنة
  void recordSyncFailure() {
    _consecutiveFailures++;
    debugPrint('❌ فشل في المزامنة (المحاولة $_consecutiveFailures)');
    
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      debugPrint('⚠️ فشل متكرر، سيتم زيادة فترة المزامنة التلقائية');
    }
  }

  /// تحديد ما إذا كان يجب تخطي المزامنة لتوفير الطاقة
  bool shouldSkipSync() {
    // تخطي إذا لم يكن هناك اتصال
    if (!_isOnWiFi && await _isWifiOnlyEnabled()) {
      debugPrint('📶 WiFi فقط مُفعل وليس على WiFi - تخطي المزامنة');
      return true;
    }
    
    // تخطي في وضع توفير الطاقة الشديد
    if (_isLowPowerMode && _isBatteryLow) {
      debugPrint('🔋 وضع توفير طاقة شديد - تخطي المزامنة');
      return true;
    }
    
    return false;
  }

  /// الإعدادات

  Future<void> setLowPowerMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsLowPowerModeKey, enabled);
    _isLowPowerMode = enabled;
    debugPrint('🔋 وضع توفير الطاقة: ${enabled ? "مُفعل" : "معطل"}');
  }

  Future<bool> isLowPowerModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsLowPowerModeKey) ?? false;
  }

  Future<void> setBatteryOptimization(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsBatteryOptimizationKey, enabled);
    debugPrint('🔋 تحسين البطارية: ${enabled ? "مُفعل" : "معطل"}');
  }

  Future<bool> isBatteryOptimizationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsBatteryOptimizationKey) ?? true; // مُفعل افتراضياً
  }

  Future<void> setWifiOnlySync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsWifiOnlyKey, enabled);
    debugPrint('📶 المزامنة على WiFi فقط: ${enabled ? "مُفعل" : "معطل"}');
  }

  Future<bool> _isWifiOnlyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsWifiOnlyKey) ?? false;
  }

  Future<bool> isWifiOnlyEnabled() async {
    return await _isWifiOnlyEnabled();
  }

  Future<void> setAdaptiveInterval(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAdaptiveIntervalKey, enabled);
    debugPrint('🤖 الفترة التكيفية: ${enabled ? "مُفعل" : "معطل"}');
  }

  Future<bool> isAdaptiveIntervalEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsAdaptiveIntervalKey) ?? true; // مُفعل افتراضياً
  }

  /// معلومات الحالة
  
  Map<String, dynamic> getPerformanceStatus() {
    return {
      'low_power_mode': _isLowPowerMode,
      'is_on_wifi': _isOnWiFi,
      'is_battery_low': _isBatteryLow,
      'consecutive_failures': _consecutiveFailures,
      'connection_type': _isOnWiFi ? 'WiFi' : 'Mobile Data',
    };
  }

  /// تنظيف الموارد
  void dispose() {
    _connectivitySubscription?.cancel();
    _batteryCheckTimer?.cancel();
    debugPrint('🛑 مُحسِّن الأداء: تم التنظيف');
  }
}

/// مساعد لحساب الفترات التكيفية المتقدمة
class AdaptiveSyncCalculator {
  
  /// حساب فترة مزامنة ذكية بناءً على نشاط التطبيق
  static int calculateSmartInterval({
    required int baseInterval,
    required DateTime lastUserActivity,
    required int recentChangesCount,
    required bool isBusinessHours,
  }) {
    int smartInterval = baseInterval;
    final now = DateTime.now();
    final timeSinceActivity = now.difference(lastUserActivity);
    
    // تسريع المزامنة خلال ساعات العمل
    if (isBusinessHours) {
      smartInterval = (smartInterval * 0.7).round(); // تسريع بـ 30%
      debugPrint('🏢 ساعات العمل: تسريع المزامنة إلى $smartInterval دقائق');
    }
    
    // تسريع المزامنة عند وجود تغييرات حديثة كثيرة
    if (recentChangesCount > 10) {
      smartInterval = (smartInterval * 0.5).round(); // تسريع بـ 50%
      debugPrint('📈 نشاط عالي ($recentChangesCount تغييرات): تسريع إلى $smartInterval دقائق');
    }
    
    // إبطاء المزامنة عند عدم النشاط
    if (timeSinceActivity.inHours > 2) {
      smartInterval *= 2; // إبطاء بـ 100%
      debugPrint('😴 عدم نشاط لـ ${timeSinceActivity.inHours} ساعات: إبطاء إلى $smartInterval دقائق');
    }
    
    return smartInterval.clamp(1, 120); // بين 1-120 دقيقة
  }

  /// تحديد ساعات العمل
  static bool isBusinessHours(DateTime time) {
    final hour = time.hour;
    final dayOfWeek = time.weekday;
    
    // من الأحد إلى الخميس، من 8 صباحاً إلى 11 مساءً
    if (dayOfWeek >= 1 && dayOfWeek <= 5) { // الاثنين-الجمعة
      return hour >= 8 && hour <= 23;
    }
    
    // الجمعة والسبت (نهاية الأسبوع): ساعات مختلفة
    if (dayOfWeek == 6 || dayOfWeek == 7) { // السبت والأحد
      return hour >= 10 && hour <= 24; // ساعات أطول في نهاية الأسبوع
    }
    
    return false;
  }
}

/// مدير التحكم في استهلاك البيانات
class DataUsageManager {
  static DataUsageManager? _instance;
  static DataUsageManager get instance => _instance ??= DataUsageManager._();
  
  DataUsageManager._();
  
  int _todayBytesUsed = 0;
  DateTime _lastResetDate = DateTime.now();
  
  static const String _prefsDailyLimitKey = 'sync_daily_data_limit';
  static const String _prefsBytesUsedKey = 'sync_bytes_used_today';
  static const String _prefsLastResetKey = 'sync_last_reset_date';
  
  static const int _defaultDailyLimitMB = 50; // 50 ميجابايت يومياً

  /// تسجيل استهلاك البيانات
  Future<void> recordDataUsage(int bytes) async {
    await _checkDailyReset();
    
    _todayBytesUsed += bytes;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsBytesUsedKey, _todayBytesUsed);
    
    final usedMB = _todayBytesUsed / (1024 * 1024);
    debugPrint('📊 استهلاك البيانات اليوم: ${usedMB.toStringAsFixed(1)} MB');
    
    // تحذير عند اقتراب من الحد اليومي
    final dailyLimit = await getDailyLimit();
    if (usedMB > dailyLimit * 0.8) {
      debugPrint('⚠️ اقتراب من حد البيانات اليومي (${usedMB.toStringAsFixed(1)}/${dailyLimit} MB)');
    }
  }

  /// فحص ما إذا كان يجب إعادة تعيين العداد اليومي
  Future<void> _checkDailyReset() async {
    final today = DateTime.now();
    
    if (today.day != _lastResetDate.day || 
        today.month != _lastResetDate.month || 
        today.year != _lastResetDate.year) {
      
      debugPrint('📅 إعادة تعيين عداد البيانات اليومي');
      _todayBytesUsed = 0;
      _lastResetDate = today;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsBytesUsedKey, 0);
      await prefs.setString(_prefsLastResetKey, today.toIso8601String());
    }
  }

  /// فحص ما إذا كان تم تجاوز الحد اليومي
  Future<bool> isLimitExceeded() async {
    await _checkDailyReset();
    
    final dailyLimitBytes = (await getDailyLimit()) * 1024 * 1024; // تحويل لبايت
    return _todayBytesUsed > dailyLimitBytes;
  }

  /// الحصول على الحد اليومي للبيانات (MB)
  Future<int> getDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsDailyLimitKey) ?? _defaultDailyLimitMB;
  }

  /// تعيين الحد اليومي للبيانات
  Future<void> setDailyLimit(int limitMB) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsDailyLimitKey, limitMB);
    debugPrint('📊 الحد اليومي للبيانات: $limitMB MB');
  }

  /// الحصول على إحصائيات الاستهلاك
  Future<Map<String, dynamic>> getUsageStats() async {
    await _checkDailyReset();
    
    final dailyLimit = await getDailyLimit();
    final usedMB = _todayBytesUsed / (1024 * 1024);
    final remainingMB = dailyLimit - usedMB;
    final usagePercentage = (usedMB / dailyLimit * 100).clamp(0, 100);
    
    return {
      'used_mb': usedMB,
      'limit_mb': dailyLimit,
      'remaining_mb': remainingMB,
      'usage_percentage': usagePercentage,
      'is_limit_exceeded': usedMB > dailyLimit,
    };
  }
}

/// إعدادات أداء المزامنة
class SyncPerformanceSettings {
  static const Map<String, Map<String, dynamic>> predefinedProfiles = {
    'high_performance': {
      'name': 'أداء عالي',
      'interval': 2,
      'low_power_mode': false,
      'wifi_only': false,
      'daily_limit_mb': 100,
      'description': 'مزامنة سريعة ومتكررة (للمكاتب)',
    },
    'balanced': {
      'name': 'متوازن',
      'interval': 5,
      'low_power_mode': false,
      'wifi_only': false,
      'daily_limit_mb': 50,
      'description': 'توازن بين السرعة وتوفير البطارية',
    },
    'battery_saver': {
      'name': 'توفير البطارية',
      'interval': 15,
      'low_power_mode': true,
      'wifi_only': true,
      'daily_limit_mb': 25,
      'description': 'أقل استهلاك للبطارية والبيانات',
    },
    'wifi_only': {
      'name': 'WiFi فقط',
      'interval': 3,
      'low_power_mode': false,
      'wifi_only': true,
      'daily_limit_mb': 200,
      'description': 'مزامنة على WiFi فقط بدون حد للبيانات',
    },
  };

  /// تطبيق ملف تعريف أداء محدد مسبقاً
  static Future<void> applyProfile(String profileKey) async {
    final profile = predefinedProfiles[profileKey];
    if (profile == null) return;
    
    final optimizer = SyncPerformanceOptimizer.instance;
    final dataManager = DataUsageManager.instance;
    
    await optimizer.setLowPowerMode(profile['low_power_mode'] as bool);
    await optimizer.setWifiOnlySync(profile['wifi_only'] as bool);
    await dataManager.setDailyLimit(profile['daily_limit_mb'] as int);
    
    // يمكن إضافة تحديث sync interval هنا إذا كان متاحاً في SmartSyncManager
    
    debugPrint('⚙️ تم تطبيق ملف التعريف: ${profile['name']}');
  }

  /// الحصول على ملف التعريف الحالي
  static Future<String> getCurrentProfile() async {
    final optimizer = SyncPerformanceOptimizer.instance;
    final dataManager = DataUsageManager.instance;
    
    final lowPowerMode = await optimizer.isLowPowerModeEnabled();
    final wifiOnly = await optimizer.isWifiOnlyEnabled();
    final dailyLimit = await dataManager.getDailyLimit();
    
    // مقارنة مع الملفات المحددة مسبقاً
    for (final entry in predefinedProfiles.entries) {
      final profile = entry.value;
      if (profile['low_power_mode'] == lowPowerMode &&
          profile['wifi_only'] == wifiOnly &&
          profile['daily_limit_mb'] == dailyLimit) {
        return entry.key;
      }
    }
    
    return 'custom'; // إعدادات مخصصة
  }
}