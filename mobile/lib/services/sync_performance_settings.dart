import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

/// إعدادات أداء المزامنة - يحتوي على ملفات التعريف المحددة مسبقاً وإدارة الإعدادات
class SyncPerformanceSettings {
  /// ملفات التعريف المحددة مسبقاً للأداء
  static const Map<String, Map<String, dynamic>> predefinedProfiles = {
    'performance': {
      'name': 'أداء عالي',
      'description': 'أقصى سرعة ودقة في المزامنة',
      'interval': 1,
      'wifi_only': false,
      'low_power_mode': false,
      'daily_limit_mb': 500,
    },
    'balanced': {
      'name': 'متوازن',
      'description': 'توازن بين الأداء والبطارية',
      'interval': 5,
      'wifi_only': false,
      'low_power_mode': false,
      'daily_limit_mb': 200,
    },
    'battery_saver': {
      'name': 'توفير البطارية',
      'description': 'أقل استهلاك للبطارية والبيانات',
      'interval': 15,
      'wifi_only': true,
      'low_power_mode': true,
      'daily_limit_mb': 50,
    },
  };

  /// الحصول على ملف التعريف الحالي
  static Future<String> getCurrentProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentProfile =
          prefs.getString('sync_performance_profile') ?? 'balanced';

      // التأكد من أن ملف التعريف موجود في القائمة المحددة مسبقاً
      if (predefinedProfiles.containsKey(currentProfile)) {
        return currentProfile;
      } else {
        // إذا كان ملف التعريف غير صحيح، قم بإعادة تعيينه إلى الافتراضي
        await _setCurrentProfile('balanced');
        return 'balanced';
      }
    } catch (e) {
      debugPrint('❌ خطأ في قراءة ملف التعريف الحالي: $e');
      return 'balanced'; // القيمة الافتراضية
    }
  }

  /// تطبيق ملف تعريف محدد
  static Future<void> applyProfile(String profileKey) async {
    try {
      // التحقق من وجود ملف التعريف
      if (!predefinedProfiles.containsKey(profileKey)) {
        throw ArgumentError('ملف التعريف "$profileKey" غير موجود');
      }

      final profile = predefinedProfiles[profileKey]!;
      final prefs = await SharedPreferences.getInstance();

      // حفظ ملف التعريف المختار
      await _setCurrentProfile(profileKey);

      // تطبيق الإعدادات من ملف التعريف
      await prefs.setInt('sync_interval_minutes', profile['interval'] as int);
      await prefs.setBool('wifi_only_sync', profile['wifi_only'] as bool);
      await prefs.setBool(
        'low_power_mode_enabled',
        profile['low_power_mode'] as bool,
      );
      await prefs.setInt(
        'daily_data_limit_mb',
        profile['daily_limit_mb'] as int,
      );

      // تطبيق إعدادات إضافية حسب ملف التعريف
      await _applyProfileSpecificSettings(profileKey, profile);

      debugPrint('✅ تم تطبيق ملف التعريف "$profileKey" بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في تطبيق ملف التعريف "$profileKey": $e');
      rethrow;
    }
  }

  /// حفظ ملف التعريف الحالي
  static Future<void> _setCurrentProfile(String profileKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_performance_profile', profileKey);
  }

  /// تطبيق إعدادات خاصة بكل ملف تعريف
  static Future<void> _applyProfileSpecificSettings(
    String profileKey,
    Map<String, dynamic> profile,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    switch (profileKey) {
      case 'performance':
        // إعدادات الأداء العالي
        await prefs.setBool(
          'adaptive_interval_enabled',
          false,
        ); // فترة ثابتة للأداء
        await prefs.setBool(
          'battery_optimization_enabled',
          false,
        ); // تعطيل تحسين البطارية
        await prefs.setInt('batch_size', 100); // حجم دفعة أكبر
        await prefs.setInt('connection_timeout_seconds', 30);

      case 'balanced':
        // إعدادات متوازنة
        await prefs.setBool('adaptive_interval_enabled', true); // فترة تكيفية
        await prefs.setBool(
          'battery_optimization_enabled',
          true,
        ); // تحسين البطارية معتدل
        await prefs.setInt('batch_size', 50); // حجم دفعة متوسط
        await prefs.setInt('connection_timeout_seconds', 20);

      case 'battery_saver':
        // إعدادات توفير البطارية
        await prefs.setBool(
          'adaptive_interval_enabled',
          true,
        ); // فترة تكيفية طويلة
        await prefs.setBool(
          'battery_optimization_enabled',
          true,
        ); // أقصى تحسين للبطارية
        await prefs.setInt('batch_size', 25); // حجم دفعة صغير
        await prefs.setInt('connection_timeout_seconds', 10);
        // إعدادات إضافية لتوفير البطارية
        await prefs.setBool('background_sync_enabled', false);
        await prefs.setInt('max_retry_attempts', 1);
    }
  }

  /// الحصول على جميع الإعدادات الحالية
  static Future<Map<String, dynamic>> getAllSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentProfile = await getCurrentProfile();

      return {
        'current_profile': currentProfile,
        'sync_interval_minutes': prefs.getInt('sync_interval_minutes') ?? 5,
        'wifi_only_sync': prefs.getBool('wifi_only_sync') ?? false,
        'low_power_mode_enabled':
            prefs.getBool('low_power_mode_enabled') ?? false,
        'daily_data_limit_mb': prefs.getInt('daily_data_limit_mb') ?? 200,
        'adaptive_interval_enabled':
            prefs.getBool('adaptive_interval_enabled') ?? true,
        'battery_optimization_enabled':
            prefs.getBool('battery_optimization_enabled') ?? true,
        'batch_size': prefs.getInt('batch_size') ?? 50,
        'connection_timeout_seconds':
            prefs.getInt('connection_timeout_seconds') ?? 20,
        'background_sync_enabled':
            prefs.getBool('background_sync_enabled') ?? true,
        'max_retry_attempts': prefs.getInt('max_retry_attempts') ?? 3,
      };
    } catch (e) {
      debugPrint('❌ خطأ في قراءة جميع الإعدادات: $e');
      return {};
    }
  }

  /// إعادة تعيين الإعدادات إلى القيم الافتراضية
  static Future<void> resetToDefaults() async {
    try {
      await applyProfile('balanced'); // تطبيق ملف التعريف المتوازن كافتراضي
      debugPrint('🔄 تم إعادة تعيين الإعدادات إلى القيم الافتراضية');
    } catch (e) {
      debugPrint('❌ خطأ في إعادة تعيين الإعدادات: $e');
      rethrow;
    }
  }

  /// التحقق من صحة ملف التعريف
  static bool isValidProfile(String profileKey) {
    return predefinedProfiles.containsKey(profileKey);
  }

  /// الحصول على قائمة بأسماء ملفات التعريف المتاحة
  static List<String> getAvailableProfileKeys() {
    return predefinedProfiles.keys.toList();
  }

  /// الحصول على معلومات ملف تعريف محدد
  static Map<String, dynamic>? getProfileInfo(String profileKey) {
    return predefinedProfiles[profileKey];
  }
}
