// lib/services/remote_config_service.dart
// خدمة Firebase Remote Config — تحكم عن بُعد في إعدادات التطبيق
// 20 مفتاح تحكم يغطي: الإشعارات، المواعيد، الحجوزات، الحسابات، النسخ الاحتياطي، الأداء

import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// خدمة Remote Config لمشروع مارينا هوتل
///
/// الاستخدام:
/// ```dart
/// await RemoteConfigService.instance.initialize();
/// final hour = RemoteConfigService.instance.checkoutHour;
/// final phone = RemoteConfigService.instance.whatsappPhone;
/// ```
class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  static RemoteConfigService get instance => _instance;
  RemoteConfigService._internal();

  FirebaseRemoteConfig? _remoteConfig;
  bool _isInitialized = false;
  DateTime? _lastFetchTime;
  String? _lastFetchStatus;

  /// هل تم التهيئة؟
  bool get isInitialized => _isInitialized;

  /// وقت آخر جلب
  DateTime? get lastFetchTime => _lastFetchTime;

  /// حالة آخر جلب
  String? get lastFetchStatus => _lastFetchStatus;

  // ═══════════════════════════════════════════════════════════════
  //  التهيئة
  // ═══════════════════════════════════════════════════════════════

  /// تهيئة Remote Config — يُستدعى من main()
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _remoteConfig = FirebaseRemoteConfig.instance;

      // إعدادات الجلب
      await _remoteConfig!.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 12),
      ));

      // تعيين القيم الافتراضية
      await _remoteConfig!.setDefaults(_defaults);

      // جلب القيم فوراً (مع إنتاجية)
      try {
        final status = await _remoteConfig!.fetchAndActivate();
        _lastFetchStatus = status.toString();
        _lastFetchTime = DateTime.now();
        developer.log(
          'Remote Config activated: $status',
          name: 'RemoteConfig',
        );
      } catch (e) {
        developer.log(
          'Remote Config fetch failed (using defaults): $e',
          name: 'RemoteConfig',
        );
        _lastFetchStatus = 'fetch_failed';
      }

      _isInitialized = true;
      developer.log(
        'Remote Config initialized (${kDebugMode ? 'DEBUG' : 'RELEASE'})',
        name: 'RemoteConfig',
      );
    } catch (e) {
      developer.log(
        'Remote Config initialization failed: $e',
        name: 'RemoteConfig',
        error: e,
      );
    }
  }

  /// جلب القيم يدوياً (إجبار تحديث)
  Future<bool> forceFetch() async {
    if (_remoteConfig == null) return false;

    try {
      final status = await _remoteConfig!.fetchAndActivate();
      _lastFetchStatus = status.toString();
      _lastFetchTime = DateTime.now();
      developer.log(
        'Remote Config force fetch: $status',
        name: 'RemoteConfig',
      );
      return status;
    } catch (e) {
      _lastFetchStatus = 'error: $e';
      developer.log(
        'Remote Config force fetch error: $e',
        name: 'RemoteConfig',
        error: e,
      );
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  🔑 الإشعارات والاتصال (5 مفاتيح)
  // ═══════════════════════════════════════════════════════════════

  /// رقم هاتف WhatsApp المستقبل (CallMeBot)
  /// الافتراضي: '967773749389'
  /// الملف المرتبط: whatsapp_notification_service.dart:56
  String get whatsappPhone =>
      _remoteConfig?.getString('whatsapp_phone') ?? '967773749389';

  /// مفتاح API CallMeBot
  /// الافتراضي: '7379268'
  /// الملف المرتبط: whatsapp_notification_service.dart:57
  String get whatsappApiKey =>
      _remoteConfig?.getString('whatsapp_api_key') ?? '7379268';

  /// تفعيل/تعطيل إشعارات WhatsApp
  /// الافتراضي: true
  /// الملف المرتبط: whatsapp_notification_service.dart (فحص أولي)
  bool get whatsappEnabled =>
      _remoteConfig?.getBool('whatsapp_enabled') ?? true;

  /// تفعيل/تعطيل إشعارات Lark
  /// الافتراضي: false
  /// الملف المرتبط: lark_config.dart:26
  bool get larkEnabledRemote =>
      _remoteConfig?.getBool('lark_enabled') ?? false;

  /// رقم هاتف الفندق (يظهر في رسائل الديون)
  /// الافتراضي: '9677734587456'
  /// الملف المرتبط: late_payment_whatsapp_screen.dart:92
  String get hotelContactPhone =>
      _remoteConfig?.getString('hotel_contact_phone') ?? '9677734587456';

  // ═══════════════════════════════════════════════════════════════
  //  ⏰ مواعيد التقارير (4 مفاتيح)
  // ═══════════════════════════════════════════════════════════════

  /// وقت النسخ الاحتياطي اليومي
  /// الافتراضي: '21:00'
  /// الملف المرتبط: alarm_backup.dart:36
  String get dailyBackupTime =>
      _remoteConfig?.getString('daily_backup_time') ?? '21:00';

  /// وقت تقرير WhatsApp اليومي
  /// الافتراضي: '21:00'
  /// الملف المرتبط: alarm_backup.dart (مستقبلاً)
  String get whatsappReportTime =>
      _remoteConfig?.getString('whatsapp_report_time') ?? '21:00';

  /// وقت تقرير Lark اليومي
  /// الافتراضي: '08:00'
  /// الملف المرتبط: lark_config.dart:20, alarm_backup.dart:158
  String get larkReportTime =>
      _remoteConfig?.getString('lark_report_time') ?? '08:00';

  /// وقت تقرير Telegram اليومي
  /// الافتراضي: '02:00'
  /// الملف المرتبط: telegram_config.dart:14, alarm_backup.dart:203
  String get telegramReportTime =>
      _remoteConfig?.getString('telegram_report_time') ?? '02:00';

  // ═══════════════════════════════════════════════════════════════
  //  🏨 قواعد الحجوزات (3 مفاتيح)
  // ═══════════════════════════════════════════════════════════════

  /// ساعة تسجيل الخروج (اليوم الفندقي يبدأ من هذه الساعة)
  /// الافتراضي: 14
  /// الملف المرتبط: utils/time.dart, booking_derived_fields_service.dart:123,358
  int get checkoutHour =>
      _remoteConfig?.getInt('checkout_hour') ?? 14;

  /// حد أيام الديون المتأخرة (أيام)
  /// الافتراضي: 30
  /// الملف المرتبط: late_payment_whatsapp_screen.dart:106
  int get latePaymentThresholdDays =>
      _remoteConfig?.getInt('late_payment_threshold_days') ?? 30;

  /// هل الدفعات يجب أن تكون أعداداً صحيحة فقط؟ (بدون كسور)
  /// الافتراضي: true
  /// الملف المرتبط: booking_checkout_screen.dart:588
  bool get wholeNumberPaymentsOnly =>
      _remoteConfig?.getBool('whole_number_payments_only') ?? true;

  // ═══════════════════════════════════════════════════════════════
  //  💰 الحسابات (2 مفتاح)
  // ═══════════════════════════════════════════════════════════════

  /// نوع الخصم الافتراضي: 'per_night' أو 'total'
  /// الافتراضي: 'per_night'
  /// الملف المرتبط: bookings_repository.dart:48
  String get defaultDiscountType =>
      _remoteConfig?.getString('default_discount_type') ?? 'per_night';

  /// سقف مضاعف السعر (لحماية من أسعار خاطئة)
  /// الافتراضي: 3.0
  /// الملف المرتبط: stay_balance_calculator.dart:234
  double get maxRateMultiplier =>
      _remoteConfig?.getDouble('max_rate_multiplier') ?? 3.0;

  // ═══════════════════════════════════════════════════════════════
  //  💾 النسخ الاحتياطي (2 مفتاح)
  // ═══════════════════════════════════════════════════════════════

  /// عدد النسخ الاحتياطية القصوى
  /// الافتراضي: 10
  /// الملف المرتبط: auto_backup_manager.dart:64
  int get maxBackupCount =>
      _remoteConfig?.getInt('max_backup_count') ?? 10;

  /// فترة الاحتفاظ بالنسخ (أيام)
  /// الافتراضي: 14
  /// الملف المرتبط: auto_backup_manager.dart:67
  int get backupRetentionDays =>
      _remoteConfig?.getInt('backup_retention_days') ?? 14;

  // ═══════════════════════════════════════════════════════════════
  //  📱 الإشعارات والرسائل (2 مفتاح)
  // ═══════════════════════════════════════════════════════════════

  /// الحد الأقصى لطول رسالة WhatsApp (حرف)
  /// الافتراضي: 1000
  /// الملف المرتبط: whatsapp_service.dart:34
  int get whatsappMessageMaxLength =>
      _remoteConfig?.getInt('whatsapp_message_max_length') ?? 1000;

  /// مهلة API CallMeBot (ثانية)
  /// الافتراضي: 15
  /// الملف المرتبط: whatsapp_service.dart:126
  int get whatsappApiTimeout =>
      _remoteConfig?.getInt('whatsapp_api_timeout') ?? 15;

  // ═══════════════════════════════════════════════════════════════
  //  🔧 إعدادات عامة (2 مفتاح)
  // ═══════════════════════════════════════════════════════════════

  /// كود الدولة الافتراضي (لتنسيق أرقام الهواتف)
  /// الافتراضي: '967' (اليمن)
  /// الملف المرتبط: late_payment_whatsapp_screen.dart:34,50
  String get countryCodeDefault =>
      _remoteConfig?.getString('country_code_default') ?? '967';

  /// مهلة API العامة (ثانية)
  /// الافتراضي: 30
  /// الملف المرتبط: constants.dart:12
  int get apiTimeoutSeconds =>
      _remoteConfig?.getInt('api_timeout_seconds') ?? 30;

  // ═══════════════════════════════════════════════════════════════
  //  القيم الافتراضية
  // ═══════════════════════════════════════════════════════════════

  static const Map<String, dynamic> _defaults = {
    // الإشعارات والاتصال
    'whatsapp_phone': '967773749389',
    'whatsapp_api_key': '7379268',
    'whatsapp_enabled': true,
    'lark_enabled': false,
    'hotel_contact_phone': '9677734587456',

    // مواعيد التقارير
    'daily_backup_time': '21:00',
    'whatsapp_report_time': '21:00',
    'lark_report_time': '08:00',
    'telegram_report_time': '02:00',

    // قواعد الحجوزات
    'checkout_hour': 14,
    'late_payment_threshold_days': 30,
    'whole_number_payments_only': true,

    // الحسابات
    'default_discount_type': 'per_night',
    'max_rate_multiplier': 3.0,

    // النسخ الاحتياطي
    'max_backup_count': 10,
    'backup_retention_days': 14,

    // الإشعارات والرسائل
    'whatsapp_message_max_length': 1000,
    'whatsapp_api_timeout': 15,

    // إعدادات عامة
    'country_code_default': '967',
    'api_timeout_seconds': 30,
  };

  // ═══════════════════════════════════════════════════════════════
  //  أدوات التشخيص
  // ═══════════════════════════════════════════════════════════════

  /// الحصول على جميع القيم الحالية كخريطة
  Map<String, dynamic> getAllValues() {
    if (_remoteConfig == null) return Map.from(_defaults);

    return {
      // الإشعارات والاتصال
      'whatsapp_phone': whatsappPhone,
      'whatsapp_api_key': whatsappApiKey,
      'whatsapp_enabled': whatsappEnabled,
      'lark_enabled': larkEnabledRemote,
      'hotel_contact_phone': hotelContactPhone,

      // مواعيد التقارير
      'daily_backup_time': dailyBackupTime,
      'whatsapp_report_time': whatsappReportTime,
      'lark_report_time': larkReportTime,
      'telegram_report_time': telegramReportTime,

      // قواعد الحجوزات
      'checkout_hour': checkoutHour,
      'late_payment_threshold_days': latePaymentThresholdDays,
      'whole_number_payments_only': wholeNumberPaymentsOnly,

      // الحسابات
      'default_discount_type': defaultDiscountType,
      'max_rate_multiplier': maxRateMultiplier,

      // النسخ الاحتياطي
      'max_backup_count': maxBackupCount,
      'backup_retention_days': backupRetentionDays,

      // الإشعارات والرسائل
      'whatsapp_message_max_length': whatsappMessageMaxLength,
      'whatsapp_api_timeout': whatsappApiTimeout,

      // إعدادات عامة
      'country_code_default': countryCodeDefault,
      'api_timeout_seconds': apiTimeoutSeconds,
    };
  }

  /// معلومات التشخيص
  Map<String, dynamic> get diagnostics => {
    'isInitialized': _isInitialized,
    'lastFetchTime': _lastFetchTime?.toIso8601String(),
    'lastFetchStatus': _lastFetchStatus,
    'settings': _remoteConfig?.settings.toString(),
    'valueSource': _defaults.keys.map((key) {
      final source = _remoteConfig?.getValue(key).source.toString().split('.').last;
      return '$key=$source';
    }).join(', '),
  };
}
