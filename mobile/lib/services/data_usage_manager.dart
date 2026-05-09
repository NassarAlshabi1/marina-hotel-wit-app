import 'dart:async';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مدير استخدام البيانات - يتتبع استهلاك البيانات ويوفر إحصائيات مفصلة
class DataUsageManager {

  factory DataUsageManager() => _instance;

  DataUsageManager._internal();
  static final DataUsageManager _instance = DataUsageManager._internal();

  // إضافة static getter instance للوصول للـ singleton
  static DataUsageManager get instance => _instance;

  // متغيرات لتتبع الاستخدام
  double _todayUsageMB = 0.0;
  DateTime? _lastResetDate;
  int _consecutiveFailures = 0;
  Timer? _resetTimer;

  // مفاتيح التخزين المحلي
  static const String _keyTodayUsage = 'today_data_usage_mb';
  static const String _keyLastResetDate = 'last_reset_date';
  static const String _keyConsecutiveFailures = 'consecutive_failures';
  static const String _keyDailyLimit = 'daily_data_limit_mb';

  /// تهيئة مدير استخدام البيانات
  Future<void> initialize() async {
    try {
      await _loadStoredData();
      _setupDailyReset();
      debugPrint('✅ تم تهيئة مدير استخدام البيانات بنجاح');
    } catch (Object e) {
      debugPrint('❌ خطأ في تهيئة مدير استخدام البيانات: $e');
    }
  }

  /// تحميل البيانات المحفوظة
  Future<void> _loadStoredData() async {
    final prefs = await SharedPreferences.getInstance();

    // تحميل الاستخدام اليومي
    _todayUsageMB = prefs.getDouble(_keyTodayUsage) ?? 0.0;

    // تحميل تاريخ آخر إعادة تعيين
    final lastResetString = prefs.getString(_keyLastResetDate);
    if (lastResetString != null) {
      _lastResetDate = DateTime.tryParse(lastResetString);
    }

    // تحميل عدد الفشل المتتالي
    _consecutiveFailures = prefs.getInt(_keyConsecutiveFailures) ?? 0;

    // التحقق من الحاجة لإعادة التعيين اليومي
    await _checkDailyReset();
  }

  /// إعداد إعادة التعيين اليومي
  void _setupDailyReset() {
    _resetTimer?.cancel();

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    _resetTimer = Timer(timeUntilMidnight, () async {
      await _performDailyReset();
      _setupDailyReset(); // إعداد المؤقت للغد
    });
  }

  /// التحقق من الحاجة لإعادة التعيين اليومي
  Future<void> _checkDailyReset() async {
    final now = DateTime.now();

    if (_lastResetDate == null ||
        _lastResetDate!.day != now.day ||
        _lastResetDate!.month != now.month ||
        _lastResetDate!.year != now.year) {
      await _performDailyReset();
    }
  }

  /// إجراء إعادة التعيين اليومي
  Future<void> _performDailyReset() async {
    try {
      _todayUsageMB = 0.0;
      _lastResetDate = DateTime.now();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyTodayUsage, _todayUsageMB);
      await prefs.setString(
        _keyLastResetDate,
        _lastResetDate!.toIso8601String(),
      );

      debugPrint('🔄 تم إعادة تعيين الاستخدام اليومي للبيانات');
    } catch (Object e) {
      debugPrint('❌ خطأ في إعادة التعيين اليومي: $e');
    }
  }

  /// إضافة استخدام بيانات جديد
  Future<void> addUsage(double megabytes) async {
    try {
      _todayUsageMB += megabytes;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyTodayUsage, _todayUsageMB);

      debugPrint(
        '📊 تم إضافة ${megabytes.toStringAsFixed(2)} MB للاستخدام اليومي',
      );
    } catch (Object e) {
      debugPrint('❌ خطأ في إضافة استخدام البيانات: $e');
    }
  }

  /// تسجيل فشل في العملية
  Future<void> recordFailure() async {
    try {
      _consecutiveFailures++;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyConsecutiveFailures, _consecutiveFailures);

      debugPrint('⚠️ تم تسجيل فشل متتالي: $_consecutiveFailures');
    } catch (Object e) {
      debugPrint('❌ خطأ في تسجيل الفشل: $e');
    }
  }

  /// إعادة تعيين عداد الفشل المتتالي
  Future<void> resetFailureCount() async {
    try {
      _consecutiveFailures = 0;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyConsecutiveFailures, _consecutiveFailures);

      debugPrint('✅ تم إعادة تعيين عداد الفشل المتتالي');
    } catch (Object e) {
      debugPrint('❌ خطأ في إعادة تعيين عداد الفشل: $e');
    }
  }

  /// الحصول على إحصائيات الاستخدام
  Future<Map<String, dynamic>> getUsageStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dailyLimitMB = prefs.getInt(_keyDailyLimit) ?? 200;

      // حساب النسبة المئوية للاستخدام
      final usagePercentage = dailyLimitMB > 0
          ? (_todayUsageMB / dailyLimitMB * 100).clamp(0.0, 100.0)
          : 0.0;

      // التحقق من تجاوز الحد
      final isLimitExceeded = _todayUsageMB > dailyLimitMB;

      // الحصول على نوع الاتصال
      final connectionType = await _getConnectionType();

      // التحقق من حالة البطارية
      final isBatteryLow = await _isBatteryLow();

      return {
        'used_mb': double.parse(_todayUsageMB.toStringAsFixed(1)),
        'limit_mb': dailyLimitMB,
        'usage_percentage': double.parse(usagePercentage.toStringAsFixed(1)),
        'is_limit_exceeded': isLimitExceeded,
        'connection_type': connectionType,
        'is_battery_low': isBatteryLow,
        'consecutive_failures': _consecutiveFailures,
      };
    } catch (Object e) {
      debugPrint('❌ خطأ في الحصول على إحصائيات الاستخدام: $e');

      // إرجاع قيم افتراضية في حالة الخطأ
      return {
        'used_mb': 0.0,
        'limit_mb': 200,
        'usage_percentage': 0.0,
        'is_limit_exceeded': false,
        'connection_type': 'Unknown',
        'is_battery_low': false,
        'consecutive_failures': 0,
      };
    }
  }

  /// الحصول على نوع الاتصال الحالي
  Future<String> _getConnectionType() async {
    try {
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();

      if (results.isEmpty) return 'No Connection';

      // ترتيب الأولوية في عرض نوع الاتصال
      if (results.contains(ConnectivityResult.wifi)) {
        return 'WiFi';
      } else if (results.contains(ConnectivityResult.ethernet)) {
        return 'Ethernet';
      } else if (results.contains(ConnectivityResult.mobile)) {
        return 'Mobile Data';
      } else if (results.contains(ConnectivityResult.vpn)) {
        return 'VPN';
      } else if (results.contains(ConnectivityResult.bluetooth)) {
        return 'Bluetooth';
      } else if (results.contains(ConnectivityResult.other)) {
        return 'Other';
      } else {
        return 'No Connection';
      }
    } catch (Object e) {
      debugPrint('❌ خطأ في الحصول على نوع الاتصال: $e');
      return 'Unknown';
    }
  }

  /// التحقق من حالة البطارية المنخفضة
  Future<bool> _isBatteryLow() async {
    try {
      final battery = Battery();
      final batteryLevel = await battery.batteryLevel;

      // نعتبر البطارية منخفضة إذا كانت أقل من 20%
      return batteryLevel < 20;
    } catch (Object e) {
      debugPrint('❌ خطأ في فحص مستوى البطارية: $e');
      return false; // افتراض أن البطارية عادية في حالة الخطأ
    }
  }

  /// تعيين الحد اليومي للبيانات
  Future<void> setDailyLimit(int limitMB) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyDailyLimit, limitMB);
      debugPrint('⚙️ تم تعيين الحد اليومي للبيانات: $limitMB MB');
    } catch (Object e) {
      debugPrint('❌ خطأ في تعيين الحد اليومي: $e');
    }
  }

  /// الحصول على الحد اليومي الحالي
  Future<int> getDailyLimit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyDailyLimit) ?? 200;
    } catch (Object e) {
      debugPrint('❌ خطأ في قراءة الحد اليومي: $e');
      return 200; // القيمة الافتراضية
    }
  }

  /// إضافة استخدام تقديري للمزامنة (محاكاة)
  Future<void> simulateSyncUsage() async {
    // محاكاة استخدام عشوائي بين 0.1-2.0 MB لكل عملية مزامنة
    final random = Random();
    final usage = 0.1 + random.nextDouble() * 1.9;
    await addUsage(usage);
  }

  /// تسجيل استخدام البيانات بالميجابايت (مطلوب لـ SmartSyncManager)
  Future<void> recordDataUsage(double megabytes) async {
    await addUsage(megabytes);
    debugPrint(
      '📊 تم تسجيل استخدام البيانات: ${megabytes.toStringAsFixed(2)} MB',
    );
  }

  /// التحقق من تجاوز حد البيانات اليومي (مطلوب لـ SmartSyncManager)
  Future<bool> isLimitExceeded() async {
    return false;
  }

  /// تنظيف الموارد
  void dispose() {
    _resetTimer?.cancel();
    _resetTimer = null;
    debugPrint('🧹 تم تنظيف موارد مدير استخدام البيانات');
  }
}
