// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: discarded_futures
// lib/services/crashlytics_service.dart
// خدمة Crashlytics لتتبع الأخطاء والإبلاغ عنها
// مرتبطة بـ Firebase Crashlytics + DiagnosticsLogger

import 'dart:async';
import 'dart:developer' as developer;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'telegram/whatsapp_notification_service.dart';

/// مستويات الأهمية للأخطاء
enum CrashlyticsSeverity {
  fatal, // خطأ قاتل - يوقف المزامنة
  error, // خطأ خطير - يجب الإصلاح
  warning, // تحذير - يمكن الاستمرار
  info, // معلومة - للتتبع فقط
}

/// خدمة Crashlytics لتتبع أخطاء التطبيق والمزامنة
///
/// يستخدم:
/// - Firebase Crashlytics لإرسال التقارير
/// - DiagnosticsLogger للتسجيل المحلي
///
/// الاستخدام:
/// ```dart
/// await CrashlyticsService.instance.initialize();
///
/// // تسجيل خطأ في شاشة
/// await CrashlyticsService.instance.recordScreenError(
///   screen: 'PaymentsScreen',
///   action: 'processPayment',
///   error: e,
///   stackTrace: stack,
/// );
///
/// // تسجيل خطأ مزامنة
/// await CrashlyticsService.instance.recordSyncError(
///   operation: 'push_bookings',
///   error: e.toString(),
///   severity: CrashlyticsSeverity.error,
/// );
/// ```
class CrashlyticsService {
  factory CrashlyticsService() => _instance;
  CrashlyticsService._internal();
  static final CrashlyticsService _instance = CrashlyticsService._internal();
  static CrashlyticsService get instance => _instance;

  FirebaseCrashlytics? _crashlytics;
  bool _isEnabled = true;
  bool _isInitialized = false;
  bool _isFirebaseConnected = false;
  final List<Map<String, dynamic>> _errorHistory = [];
  static const int _maxHistorySize = 100;

  /// هل تم التهيئة؟ (دائماً true بعد التهيئة)
  bool get isInitialized => _isInitialized;

  /// هل Firebase متصل بنجاح؟
  bool get isFirebaseConnected => _isFirebaseConnected;

  // ═══════════════════════════════════════════════════════════════
  //  ✅ Context Update Methods — تُحدّث مفاتيح Crashlytics ديناميكياً
  //  تستدعى من أي مكان في التطبيق لإضافة سياق للـ crash reports
  // ═══════════════════════════════════════════════════════════════

  /// تحديث رقم الغرفة الحالية (يظهر في crash reports)
  Future<void> setRoomNumber(String roomNumber) async {
    try {
      await _crashlytics?.setCustomKey('room_number', roomNumber);
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// تحديث حالة المزامنة (idle, pushing, pulling, conflicting, error)
  Future<void> setSyncStatus(String status) async {
    try {
      await _crashlytics?.setCustomKey('sync_status', status);
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// تحديث دور المستخدم (admin, receptionist, manager)
  Future<void> setUserRole(String role) async {
    try {
      await _crashlytics?.setCustomKey('user_role', role);
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// تحديث اليوم الفندقي الحالي
  Future<void> setHotelDayKey(String hotelDayKey) async {
    try {
      await _crashlytics?.setCustomKey('hotel_day_key', hotelDayKey);
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// تحديد محرك المزامنة النشط (appwrite, google_drive, secondary)
  Future<void> setSyncEngine(String engine) async {
    try {
      await _crashlytics?.setCustomKey('sync_engine', engine);
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// تحديث نوع الشبكة (wifi, mobile, none)
  Future<void> setNetworkType(String networkType) async {
    try {
      await _crashlytics?.setCustomKey('network_type', networkType);
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// تحديث معرف الجهاز
  Future<void> setDeviceId(String deviceId) async {
    try {
      await _crashlytics?.setCustomKey('device_id', deviceId);
    } catch (e) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// تحديث كل السياق دفعة واحدة (مُسهّل للـ main.dart)
  Future<void> setContext({
    String? roomNumber,
    String? syncStatus,
    String? userRole,
    String? hotelDayKey,
    String? syncEngine,
    String? networkType,
    String? deviceId,
  }) async {
    final futures = <Future<void>>[];
    if (roomNumber != null) futures.add(setRoomNumber(roomNumber));
    if (syncStatus != null) futures.add(setSyncStatus(syncStatus));
    if (userRole != null) futures.add(setUserRole(userRole));
    if (hotelDayKey != null) futures.add(setHotelDayKey(hotelDayKey));
    if (syncEngine != null) futures.add(setSyncEngine(syncEngine));
    if (networkType != null) futures.add(setNetworkType(networkType));
    if (deviceId != null) futures.add(setDeviceId(deviceId));
    await Future.wait(futures);
  }

  /// تهيئة الخدمة — يجب استدعاؤها في main()
  /// يعمل دائماً حتى لو فشل Firebase — التسجيل المحلي متاح
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      _crashlytics = FirebaseCrashlytics.instance;

      // في وضع التطوير: نفعّل Crashlytics أيضاً للاختبار
      // في وضع الإنتاج: يُفعّل دائماً
      await _crashlytics!.setCrashlyticsCollectionEnabled(true);

      // إعداد مفاتيح مخصصة عامة
      await _crashlytics!.setCustomKey('app_name', 'marina_hotel');
      await _crashlytics!.setCustomKey('app_version', '1.0.0');

      // ✅ مفاتيح مخصصة للسياق (تظهر في كل crash report)
      await _crashlytics!.setCustomKey('room_number', '');
      await _crashlytics!.setCustomKey('sync_status', 'idle');
      await _crashlytics!.setCustomKey('user_role', '');
      await _crashlytics!.setCustomKey('hotel_day_key', '');
      await _crashlytics!.setCustomKey('sync_engine', '');
      await _crashlytics!.setCustomKey('network_type', '');
      await _crashlytics!.setCustomKey('device_id', '');

      await _crashlytics!.log('CrashlyticsService initialized');

      _isFirebaseConnected = true;
      _isInitialized = true;

      developer.log(
        '✅ CrashlyticsService initialized (${kDebugMode ? 'DEBUG' : 'RELEASE'})',
        name: 'CrashlyticsService',
      );
    } catch (e) {
      developer.log(
        '⚠️ Crashlytics Firebase failed — local logging active: $e',
        name: 'CrashlyticsService',
      );
      // حتى لو فشل Firebase، الخدمة تعمل بالتسجيل المحلي
      _isFirebaseConnected = false;
      _isInitialized = true;
    }
  }

  /// تهيئة معالجات الأخطاء العامة — يُستدعى بعد initialize()
  ///
  /// يربط FlutterError.onError و PlatformDispatcher.onError بـ Crashlytics
  /// مع الحفاظ على DiagnosticsLogger
  void setupErrorHandlers({
    required void Function(FlutterErrorDetails) originalFlutterHandler,
    required void Function(Object error, StackTrace stack)
    originalPlatformHandler,
    required void Function(Object error, StackTrace stack) originalZonedHandler,
  }) {
    // Flutter errors (تُرسل إلى Crashlytics + الأصلية)
    FlutterError.onError = (details) {
      _recordFlutterError(details);
      originalFlutterHandler(details); // DiagnosticsLogger
    };

    // Platform errors (Isolate errors)
    PlatformDispatcher.instance.onError = (error, stack) {
      _recordPlatformError(error, stack);
      originalPlatformHandler(error, stack); // DiagnosticsLogger
      return true;
    };
  }

  /// تمكين/تعطيل الخدمة
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    _crashlytics?.setCrashlyticsCollectionEnabled(enabled);
  }

  // ═══════════════════════════════════════════════════════════════
  //  تسجيل أخطاء الشاشات
  // ═══════════════════════════════════════════════════════════════

  /// تسجيل خطأ في شاشة محددة
  ///
  /// يُستخدم داخل try-catch في أي شاشة:
  /// ```dart
  /// try {
  ///   await processPayment();
  /// } catch (e, stack) {
  ///   await CrashlyticsService.instance.recordScreenError(
  ///     screen: 'PaymentsScreen',
  ///     action: 'processPayment',
  ///     error: e,
  ///     stackTrace: stack,
  ///   );
  /// }
  /// ```
  Future<void> recordScreenError({
    required String screen,
    required String action,
    required dynamic error,
    StackTrace? stackTrace,
    CrashlyticsSeverity severity = CrashlyticsSeverity.error,
    Map<String, dynamic> extra = const {},
  }) async {
    if (!_isEnabled || !_isInitialized) {
      return;
    }

    final errorStr = error.toString();

    // حفظ في التاريخ المحلي
    _addToHistory('screen', screen, action, errorStr, severity);

    // تسجيل في developer log
    developer.log(
      '💥 [$screen] $action: $errorStr',
      name: 'Crashlytics',
      error: error,
      stackTrace: stackTrace,
    );

    // إرسال إلى Firebase Crashlytics
    try {
      await _crashlytics?.setCustomKey('screen', screen);
      await _crashlytics?.setCustomKey('action', action);
      await _crashlytics?.setCustomKey('severity', severity.name);

      for (final entry in extra.entries) {
        await _crashlytics?.setCustomKey(
          'screen_${entry.key}',
          entry.value.toString(),
        );
      }

      await _crashlytics?.recordError(
        error,
        stackTrace ?? StackTrace.current,
        reason: '$screen — $action',
        fatal: severity == CrashlyticsSeverity.fatal,
        information: [
          'Screen: $screen',
          'Action: $action',
          'Severity: ${severity.name}',
          ...extra.entries.map((e) => '${e.key}: ${e.value}'),
        ],
      );
    } catch (e) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');
      // لا نوقف التطبيق بسبب فشل Crashlytics
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  تسجيل أخطاء المزامنة
  // ═══════════════════════════════════════════════════════════════

  /// تسجيل خطأ مزامنة
  Future<void> recordSyncError({
    required String operation,
    required String error,
    StackTrace? stackTrace,
    CrashlyticsSeverity severity = CrashlyticsSeverity.error,
    Map<String, dynamic> context = const {},
  }) async {
    if (!_isEnabled || !_isInitialized) {
      return;
    }

    _addToHistory('sync', operation, '', error, severity);

    developer.log(
      '💥 Sync Error [$severity]: $operation - $error',
      name: 'Crashlytics',
      error: error,
      stackTrace: stackTrace,
    );

    try {
      await _crashlytics?.setCustomKey('last_sync_operation', operation);
      await _crashlytics?.setCustomKey(
        'sync_error_count',
        _errorHistory.length,
      );

      for (final entry in context.entries) {
        await _crashlytics?.setCustomKey(
          'sync_ctx_${entry.key}',
          entry.value.toString(),
        );
      }

      final isFatal = severity == CrashlyticsSeverity.fatal;
      await _crashlytics?.recordError(
        Exception('[$operation] $error'),
        stackTrace ?? StackTrace.current,
        reason: operation,
        fatal: isFatal,
        information: [
          'Operation: $operation',
          'Severity: ${severity.name}',
          ...context.entries.map((e) => '${e.key}: ${e.value}'),
        ],
      );
    } catch (e) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// تسجيل خطأ قاتل في المزامنة
  Future<void> recordFatalSyncError({
    required String operation,
    required dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic> context = const {},
  }) async {
    await recordSyncError(
      operation: operation,
      error: error.toString(),
      stackTrace: stackTrace,
      severity: CrashlyticsSeverity.fatal,
      context: context,
    );
    // إرسال تنبيه WhatsApp فوري للأخطاء القاتلة
    unawaited(
      WhatsAppNotificationService.instance.notifySyncError(
        operation: operation,
        error: error.toString().substring(
          0,
          error.toString().length > 200 ? 200 : error.toString().length,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  تسجيل أخطاء عامة
  // ═══════════════════════════════════════════════════════════════

  /// تسجيل خطأ غير متوقع
  Future<void> recordUnexpectedError({
    required dynamic error,
    StackTrace? stackTrace,
    String? context,
  }) async {
    if (!_isEnabled || !_isInitialized) {
      return;
    }

    try {
      await _crashlytics?.recordError(
        error,
        stackTrace ?? StackTrace.current,
        reason: context ?? 'unexpected_error',
      );
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// تسجيل رسالة سجل (log)
  Future<void> log(String message) async {
    if (!_isEnabled || !_isInitialized) {
      return;
    }

    try {
      await _crashlytics?.log(message);
    } catch (e) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// تسجيل خطأ معزز مع سياق كامل
  Future<void> recordErrorWithContext({
    required String title,
    required dynamic error,
    StackTrace? stackTrace,
    bool fatal = false,
    Map<String, dynamic>? customKeys,
  }) async {
    if (!_isEnabled || !_isInitialized) {
      return;
    }

    try {
      if (customKeys != null) {
        for (final entry in customKeys.entries) {
          await _crashlytics?.setCustomKey(entry.key, entry.value.toString());
        }
      }

      await _crashlytics?.recordError(
        error,
        stackTrace ?? StackTrace.current,
        reason: title,
        fatal: fatal,
        information:
            customKeys?.entries.map((e) => '${e.key}: ${e.value}').toList() ??
            [],
      );
    } catch (e) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  // ═══════════════════════════════════════════════════════════════
  //  إدارة المستخدم والسياق
  // ═══════════════════════════════════════════════════════════════

  /// تسجيل معرف المستخدم
  Future<void> setUserIdentifier(String userId) async {
    if (!_isEnabled || !_isInitialized) {
      return;
    }

    try {
      await _crashlytics?.setUserIdentifier(userId);
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// تعيين مفتاح مخصص
  Future<void> setCustomKey(String key, dynamic value) async {
    if (!_isEnabled || !_isInitialized) {
      return;
    }

    try {
      await _crashlytics?.setCustomKey(key, value.toString());
    } catch (e) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// تعيين اسم الشاشة الحالية (للتتبع)
  Future<void> setCurrentScreen(String screenName) async {
    await log('SCREEN: $screenName');
  }

  // ═══════════════════════════════════════════════════════════════
  //  إدارة التقارير
  // ═══════════════════════════════════════════════════════════════

  /// إجبار إرسال التقارير المعلقة
  Future<void> sendUnsentReports() async {
    if (!_isEnabled || !_isInitialized) {
      return;
    }

    try {
      await _crashlytics?.sendUnsentReports();
    } catch (e) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  /// الحصول على تاريخ الأخطاء
  List<Map<String, dynamic>> getErrorHistory() =>
      List.unmodifiable(_errorHistory);

  /// مسح تاريخ الأخطاء
  void clearErrorHistory() {
    _errorHistory.clear();
  }

  /// عدد الأخطاء المسجلة
  int get errorCount => _errorHistory.length;

  // ═══════════════════════════════════════════════════════════════
  //  دوال خاصة
  // ═══════════════════════════════════════════════════════════════

  void _recordFlutterError(FlutterErrorDetails details) {
    if (!_isEnabled || !_isInitialized) {
      return;
    }

    try {
      _crashlytics?.recordFlutterFatalError(details);
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  void _recordPlatformError(Object error, StackTrace stack) {
    if (!_isEnabled || !_isInitialized) {
      return;
    }

    try {
      _crashlytics?.recordError(error, stack, fatal: true);
    } catch (e) {
      debugPrint('⚠️ Swallowed error in crashlytics_service.dart: ');}
  }

  void _addToHistory(
    String category,
    String source,
    String action,
    String error,
    CrashlyticsSeverity severity,
  ) {
    _errorHistory.add({
      'category': category,
      'source': source,
      'action': action,
      'error': error,
      'severity': severity.name,
      'timestamp': DateTime.now().toIso8601String(),
    });

    if (_errorHistory.length > _maxHistorySize) {
      _errorHistory.removeAt(0);
    }
  }
}
