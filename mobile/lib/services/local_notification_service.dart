// lib/services/local_notification_service.dart
//
// ✅ خدمة الإشعارات المحلية الموحّدة (Local Notifications)
//
// تُظهر إشعارات على نفس الجهاز عند حدوث أحداث محلية:
//   - حجز جديد
//   - تسجيل دفعة
//   - إضافة مصروف
//   - اكتمال نسخ احتياطي
//   - أحداث عامة (custom)
//
// تختلف عن FCM (الذي يُرسل من جهاز لأجهزة أخرى): الإشعارات المحلية تُظهر
// على الجهاز الذي أنشأ الحدث نفسه — حتى لو لم تكن هناك أجهزة أخرى.
//
// الاستخدام:
//   await LocalNotificationService.instance.notifyBookingCreated(
//     roomNumber: '101',
//     guestName: 'أحمد',
//   );
//
// تصميم:
//   - Singleton (نفس النمط المتبع في FcmService و TelegramNotificationService).
//   - يستخدم FlutterLocalNotificationsPlugin (موجود في pubspec بالفعل).
//   - معرّفات الإشعارات موزّعة حسب النوع لتجنّب التعارض:
//       bookings:  1000-1999
//       payments:  2000-2999
//       expenses:  3000-3999
//       backup:    4000-4099
//       generic:   9000-9999
//   - قنوات منفصلة لكل نوع (Android 8+) ليتمكن المستخدم من تخصيصها من إعدادات النظام.
//   - تهيئة idempotent — يمكن استدعاؤها عدة مرات بأمان.

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// قنوات الإشعارات المحلية — كل نوع حدث له قناة مستقلة.
///
/// على Android 8+، يتحكم المستخدم بكل قناة على حدة من إعدادات النظام
/// (تفعيل/تعطيل، أولوية، صوت، اهتزاز).
class _Channels {
  static const bookings = AndroidNotificationChannel(
    'marina_bookings_channel',
    'الحجوزات',
    description: 'إشعارات إنشاء/تحديث/إلغاء الحجوزات',
    importance: Importance.high,
  );

  static const payments = AndroidNotificationChannel(
    'marina_payments_channel',
    'المدفوعات',
    description: 'إشعارات تسجيل الدفعات',
    importance: Importance.high,
  );

  static const expenses = AndroidNotificationChannel(
    'marina_expenses_channel',
    'المصروفات',
    description: 'إشعارات إضافة المصروفات',
    importance: Importance.defaultImportance,
  );

  static const backup = AndroidNotificationChannel(
    'marina_backup_channel',
    'النسخ الاحتياطي',
    description: 'إشعارات اكتمال النسخ الاحتياطي',
    importance: Importance.low,
  );

  static const generic = AndroidNotificationChannel(
    'marina_generic_channel',
    'إشعارات عامة',
    description: 'إشعارات عامة من التطبيق',
    importance: Importance.defaultImportance,
  );

  static const List<AndroidNotificationChannel> all = [
    bookings,
    payments,
    expenses,
    backup,
    generic,
  ];
}

/// خدمة الإشعارات المحلية الموحّدة.
///
/// تُهيّأ مرة واحدة من `main.dart` عبر `initialize()`. ثم تُستخدم من أي مكان
/// في التطبيق عبر `LocalNotificationService.instance.notifyXyz()`.
class LocalNotificationService {
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();

  static LocalNotificationService get instance => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  final Random _random = Random();

  // معرّفات فريدة لكل إشعار ضمن نطاق نوع الحدث
  int _nextBookingId = 1000;
  int _nextPaymentId = 2000;
  int _nextExpenseId = 3000;
  int _nextBackupId = 4000;
  int _nextGenericId = 9000;

  /// تهيئة الخدمة — idempotent.
  ///
  /// يجب استدعاؤها مرة واحدة في بداية دورة حياة التطبيق (main.dart).
  /// الاستدعاءات اللاحقة لا تفعل شيئاً.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        // طلب إذن الإشعارات على iOS عند التهيئة
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // إنشاء قنوات الإشعارات على Android 8+
      await _createChannels();

      _isInitialized = true;
      debugPrint('✅ LocalNotificationService initialized');
    } catch (e, st) {
      // لا نمنع التطبيق من العمل إذا فشلت تهيئة الإشعارات المحلية
      debugPrint('⚠️ LocalNotificationService init failed: $e\n$st');
    }
  }

  /// إنشاء قنوات الإشعارات على Android.
  /// على iOS لا توجد قنوات — يتم تجاهل الاستدعاء تلقائياً.
  Future<void> _createChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    for (final channel in _Channels.all) {
      await android.createNotificationChannel(channel);
    }
  }

  /// معالج الضغط على الإشعار.
  /// حالياً يسجّل الحدث فقط — يمكن توسيعه لاحقاً للتنقل إلى الشاشة المناسبة.
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint(
      '🔔 Local notification tapped: id=${response.id} '
      'payload=${response.payload}',
    );
    // TODO: عند الحاجة، أضف منطق التنقل لشاشة محددة بناءً على payload.
  }

  // ═══════════════════════════════════════════════════════════════
  //  واجهة عامة — إشعارات الأحداث
  // ═══════════════════════════════════════════════════════════════

  /// إشعار: حجز جديد.
  Future<void> notifyBookingCreated({
    required String roomNumber,
    required String guestName,
    String? guestPhone,
  }) async {
    final body = guestPhone != null && guestPhone.isNotEmpty
        ? 'غرفة $roomNumber — $guestName | $guestPhone'
        : 'غرفة $roomNumber — $guestName';
    await _show(
      id: _nextBookingId++,
      channel: _Channels.bookings,
      title: '🛎️ حجز جديد',
      body: body,
      payload: 'booking_created:$roomNumber',
    );
  }

  /// إشعار: خروج نزيل (تسجيل مغادرة).
  Future<void> notifyBookingCheckedOut({
    required String roomNumber,
    required String guestName,
  }) async {
    await _show(
      id: _nextBookingId++,
      channel: _Channels.bookings,
      title: '🚪 تسجيل خروج',
      body: 'غرفة $roomNumber — $guestName',
      payload: 'booking_checkout:$roomNumber',
    );
  }

  /// إشعار: تسجيل دفعة.
  Future<void> notifyPaymentAdded({
    required String roomNumber,
    required double amount,
    String? method,
    String? guestName,
  }) async {
    final methodStr = (method != null && method.isNotEmpty) ? ' | $method' : '';
    final guestStr =
        (guestName != null && guestName.isNotEmpty) ? ' — $guestName' : '';
    await _show(
      id: _nextPaymentId++,
      channel: _Channels.payments,
      title: '💰 دفعة جديدة',
      body:
          'غرفة $roomNumber$guestStr | ${amount.toStringAsFixed(0)} ريال$methodStr',
      payload: 'payment_added:$roomNumber',
    );
  }

  /// إشعار: إضافة مصروف.
  Future<void> notifyExpenseAdded({
    required String category,
    required double amount,
    String? description,
    String? employeeName,
  }) async {
    final parts = <String>['$category: ${amount.toStringAsFixed(0)} ريال'];
    if (employeeName != null && employeeName.trim().isNotEmpty) {
      parts.add('👤 ${employeeName.trim()}');
    }
    if (description != null && description.trim().isNotEmpty) {
      parts.add(description.trim());
    }
    await _show(
      id: _nextExpenseId++,
      channel: _Channels.expenses,
      title: '📉 مصروف جديد',
      body: parts.join(' | '),
      payload: 'expense_added:$category',
    );
  }

  /// إشعار: اكتمال نسخ احتياطي.
  Future<void> notifyBackupCompleted({
    required String backupPath,
    required int sizeBytes,
  }) async {
    final sizeKb = (sizeBytes / 1024).toStringAsFixed(0);
    await _show(
      id: _nextBackupId++,
      channel: _Channels.backup,
      title: '💾 نسخة احتياطية',
      body: 'تم إنشاء نسخة احتياطية ($sizeKb KB)',
      payload: 'backup_completed',
    );
  }

  /// إشعار عام.
  Future<void> notifyGeneric({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _show(
      id: _nextGenericId++,
      channel: _Channels.generic,
      title: title,
      body: body,
      payload: payload,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  التنفيذ الداخلي
  // ═══════════════════════════════════════════════════════════════

  Future<void> _show({
    required int id,
    required AndroidNotificationChannel channel,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      // محاولة تهيئة تلقائية إذا لم تُهيّأ بعد — للحفاظ على الأمان
      await initialize();
    }

    try {
      final androidDetails = AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      const iosDetails = DarwinNotificationDetails();
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(id, title, body, details, payload: payload);
      debugPrint('🔔 Local notification: $title — $body');
    } catch (e) {
      debugPrint('⚠️ Local notification show failed: $e');
    }
  }

  /// إلغاء كل الإشعارات النشطة (يُستخدم عند تسجيل الخروج مثلاً).
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// هل تمت التهيئة؟
  bool get isInitialized => _isInitialized;
}
