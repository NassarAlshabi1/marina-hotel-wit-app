// lib/services/posthog_service.dart
// خدمة PostHog للتحليلات + Session Replay + Feature Flags
//
// المرجع: https://posthog.com/docs
// Flutter SDK: https://pub.dev/packages/posthog_flutter (v4.11.0)
//
// المميزات:
// - تتبع الأحداث (event tracking)
// - تسجيل الشاشات (screen tracking)
// - تحديد هوية المستخدم (user identification)
// - Feature Flags للتحكم التجريبي
// - Session Replay (تسجيل جلسات المستخدم بصرياً)
// - Error tracking (تتبع الأخطاء)
//
// التكلفة: مجاني حتى 1M حدث/شهر + 5K session replay/شهر
// PostHog Cloud (US): https://us.posthog.com (project 529460)
// Ingestion endpoint: https://us.i.posthog.com

import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import '../utils/env.dart';

/// خدمة PostHog — تحليلات + Session Replay + Feature Flags
///
/// نمط الاستخدام:
/// ```dart
/// // تهيئة (في main.dart)
/// await PostHogService.instance.initialize();
///
/// // تتبع حدث
/// await PostHogService.instance.track('booking_created', properties: {
///   'roomNumber': '101',
///   'amount': 150.0,
/// });
///
/// // تتبع شاشة
/// await PostHogService.instance.screen('bookings_list');
///
/// // تحديد المستخدم
/// await PostHogService.instance.identify('user-123', properties: {
///   'name': 'Ahmed',
///   'role': 'admin',
/// });
///
/// // Feature Flag
/// final enabled = await PostHogService.instance.isFeatureEnabled('new_dashboard');
/// ```
class PostHogService {
  factory PostHogService() => _instance;
  PostHogService._internal();
  static final PostHogService _instance = PostHogService._internal();
  static PostHogService get instance => _instance;

  bool _isInitialized = false;
  bool _isEnabled = true;

  /// هل تم تهيئة PostHog بنجاح؟
  bool get isInitialized => _isInitialized;

  /// هل PostHog مفعّل؟ (يمكن تعطيله من الإعدادات)
  bool get isEnabled => _isEnabled && _isInitialized;

  /// تهيئة PostHog
  ///
  /// يجب استدعاؤها مرة واحدة في بداية التطبيق (main.dart).
  /// إذا لم يكن POSTHOG_API_KEY مُهيأ، تتجاهل الخدمة بصمت.
  /// PostHog API Key — مُدمج من AndroidManifest meta-data
  /// (يمكن تجاوزه عبر --dart-define=POSTHOG_API_KEY)
  static const String _defaultApiKey = String.fromEnvironment(
    'POSTHOG_API_KEY',
    defaultValue: 'phc_AunnUfNB2zemediAycLLbFYEgqdtL9k7ej8PhYHwFL6q',
  );

  /// PostHog Host — ingestion endpoint للـ US Cloud
  static const String _defaultHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://us.i.posthog.com',
  );

  Future<void> initialize() async {
    if (_isInitialized) return;

    // استخدام المفتاح من --dart-define أو القيمة الافتراضية (المُدمجة من AndroidManifest)
    final apiKey = Env.posthogApiKey.isNotEmpty ? Env.posthogApiKey : _defaultApiKey;
    final host = Env.posthogHost.isNotEmpty ? Env.posthogHost : _defaultHost;

    if (apiKey.isEmpty) {
      developer.log(
        'ℹ️ PostHog not configured — skipping initialization',
        name: 'PostHogService',
      );
      return;
    }

    try {
      final config = PostHogConfig(apiKey)
        ..host = host
        // تفعيل تتبع دورة حياة التطبيق (foreground/background)
        ..captureApplicationLifecycleEvents = true
        // تفعيل Session Replay (5K تسجيل/شهر مجاناً)
        ..sessionReplay = true
        // تفعيل Feature Flags التلقائي
        ..preloadFeatureFlags = true
        // وضع التصحيح في development فقط
        ..debug = kDebugMode;

      await Posthog().setup(config);
      _isInitialized = true;

      developer.log(
        '✅ PostHog initialized (host=$host, key=${apiKey.substring(0, 12)}...)',
        name: 'PostHogService',
      );
    } catch (e) {
      developer.log(
        '⚠️ PostHog initialization failed: $e',
        name: 'PostHogService',
      );
      // لا نوقف التطبيق بسبب فشل التحليلات
    }
  }

  /// تفعيل/تعطيل PostHog (من شاشة الإعدادات)
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    if (_isInitialized) {
      try {
        if (enabled) {
          await Posthog().enable();
        } else {
          await Posthog().disable();
        }
      } catch (e) {
        developer.log(
          '⚠️ PostHog setEnabled failed: $e',
          name: 'PostHogService',
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  Event Tracking
  // ═══════════════════════════════════════════════════════════════

  /// تتبع حدث مخصص
  ///
  /// أمثلة:
  /// ```dart
  /// await track('booking_created', properties: {
  ///   'roomNumber': '101',
  ///   'guestName': 'Ahmed',
  ///   'amount': 150.0,
  ///   'nights': 3,
  /// });
  ///
  /// await track('payment_processed', properties: {
  ///   'method': 'cash',
  ///   'amount': 500.0,
  /// });
  /// ```
  Future<void> track(
    String eventName, {
    Map<String, Object>? properties,
  }) async {
    if (!isEnabled) return;

    try {
      await Posthog().capture(
        eventName: eventName,
        properties: properties,
      );
    } catch (e) {
      // تجاهل أخطاء التحليلات بصمت
      developer.log(
        'PostHog track error: $e',
        name: 'PostHogService',
      );
    }
  }

  /// تتبع مشاهدة شاشة
  ///
  /// أمثلة:
  /// ```dart
  /// await screen('bookings_list');
  /// await screen('payments_main');
  /// await screen('settings');
  /// ```
  Future<void> screen(
    String screenName, {
    Map<String, Object>? properties,
  }) async {
    if (!isEnabled) return;

    try {
      await Posthog().screen(
        screenName: screenName,
        properties: properties,
      );
    } catch (e) {
      // تجاهل بصمت
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  User Identification
  // ═══════════════════════════════════════════════════════════════

  /// تحديد هوية المستخدم الحالي
  ///
  /// استخدم بعد تسجيل الدخول:
  /// ```dart
  /// await identify('user-123', properties: {
  ///   'name': 'Ahmed Ali',
  ///   'role': 'admin',
  ///   'email': 'ahmed@marina.com',
  /// });
  /// ```
  Future<void> identify(
    String userId, {
    Map<String, Object>? properties,
  }) async {
    if (!isEnabled) return;

    try {
      await Posthog().identify(
        userId: userId,
        userProperties: properties,
      );
    } catch (e) {
      // تجاهل بصمت
    }
  }

  /// إعادة تعيين هوية المستخدم (عند تسجيل الخروج)
  Future<void> reset() async {
    if (!isEnabled) return;

    try {
      await Posthog().reset();
    } catch (e) {
      // تجاهل بصمت
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  Feature Flags
  // ═══════════════════════════════════════════════════════════════

  /// التحقق من تفعيل Feature Flag
  ///
  /// أمثلة:
  /// ```dart
  /// if (await isFeatureEnabled('new_dashboard')) {
  ///   // عرض لوحة التحكم الجديدة
  /// }
  ///
  /// if (await isFeatureEnabled('beta_ai_chat')) {
  ///   // إظهار زر AI Chat
  /// }
  /// ```
  Future<bool> isFeatureEnabled(String flagKey) async {
    if (!isEnabled) return false;

    try {
      return await Posthog().isFeatureEnabled(flagKey);
    } catch (e) {
      return false;
    }
  }

  /// الحصول على قيمة Feature Flag (مع إمكانية التخصيص)
  ///
  /// أمثلة:
  /// ```dart
  /// final variant = await getFeatureFlag('checkout_flow');
  /// if (variant == 'simplified') {
  ///   // عرض checkout المبسط
  /// }
  /// ```
  Future<Object?> getFeatureFlag(String flagKey) async {
    if (!isEnabled) return null;

    try {
      return await Posthog().getFeatureFlag(flagKey);
    } catch (e) {
      return null;
    }
  }

  /// إعادة تحميل Feature Flags (يدوياً)
  Future<void> reloadFeatureFlags() async {
    if (!isEnabled) return;

    try {
      await Posthog().reloadFeatureFlags();
    } catch (e) {
      // تجاهل بصمت
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  Error Tracking
  // ═══════════════════════════════════════════════════════════════

  /// تسجيل خطأ في PostHog
  ///
  /// مكمل لـ Firebase Crashlytics — يرسل الخطأ إلى PostHog أيضاً
  /// ليظهر في session replay مع باقي أحداث الجلسة.
  Future<void> captureError(
    dynamic error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, Object>? properties,
  }) async {
    if (!isEnabled) return;

    try {
      await Posthog().capture(
        eventName: r'$exception',
        properties: {
          r'$exception_type': error.runtimeType.toString(),
          r'$exception_message': error.toString(),
          r'$exception_stack_trace': stackTrace?.toString() ?? '',
          if (context != null) 'context': context,
          ...?properties,
        },
      );
    } catch (e) {
      // تجاهل بصمت
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  Predefined Events (Marina Hotel specific)
  // ═══════════════════════════════════════════════════════════════

  /// حدث: إنشاء حجز جديد
  Future<void> trackBookingCreated({
    required String roomNumber,
    required String guestName,
    required double amount,
    required int nights,
  }) async {
    await track(
      'booking_created',
      properties: {
        'roomNumber': roomNumber,
        'guestName': guestName,
        'amount': amount,
        'nights': nights,
      },
    );
  }

  /// حدث: معالجة دفعة
  Future<void> trackPaymentProcessed({
    required String method,
    required double amount,
    String? bookingUuid,
  }) async {
    await track(
      'payment_processed',
      properties: {
        'method': method,
        'amount': amount,
        if (bookingUuid != null) 'bookingUuid': bookingUuid,
      },
    );
  }

  /// حدث: اكتمال المزامنة
  Future<void> trackSyncCompleted({
    required int itemsPushed,
    required int itemsPulled,
    required Duration duration,
    bool success = true,
  }) async {
    await track(
      'sync_completed',
      properties: {
        'itemsPushed': itemsPushed,
        'itemsPulled': itemsPulled,
        'durationMs': duration.inMilliseconds,
        'success': success,
      },
    );
  }

  /// حدث: فشل المزامنة
  Future<void> trackSyncFailed({
    required String error,
    required String operation,
  }) async {
    await track(
      'sync_failed',
      properties: {
        'error': error,
        'operation': operation,
      },
    );
  }

  /// حدث: إنشاء نسخة احتياطية
  Future<void> trackBackupCreated({
    required String type,
    required int sizeBytes,
    bool success = true,
  }) async {
    await track(
      'backup_created',
      properties: {
        'type': type,
        'sizeBytes': sizeBytes,
        'success': success,
      },
    );
  }

  /// حدث: تسجيل دخول مستخدم
  Future<void> trackLogin({
    required String userId,
    required String role,
  }) async {
    await track(
      'user_login',
      properties: {
        'userId': userId,
        'role': role,
      },
    );
    await identify(
      userId,
      properties: {
        'role': role,
        'lastLoginAt': DateTime.now().toIso8601String(),
      },
    );
  }

  /// حدث: تسجيل خروج
  Future<void> trackLogout() async {
    await track('user_logout');
    await reset();
  }
}
