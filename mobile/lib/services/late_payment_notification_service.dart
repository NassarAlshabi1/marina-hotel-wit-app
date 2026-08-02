// Late Payment Notification Service
//
// يُرسل إشعاراً محلياً للنظام عند دخول نافذة 22:00 (10 مساءً) إذا كانت
// هناك غرف محجوزة برصيد متبقي لم يُسدد بعد. الهدف: تنبيه موظف الاستقبال
// بأن السداد سيتأخر قريباً (خلال ساعة) ليتدارك الأمر قبل أن تصبح الغرف
// "متأخرة فعلياً" في 23:00.
//
// الاستراتيجية:
//   1. Timer يومي يُفعل عند تشغيل التطبيق
//   2. يفحص كل دقيقة: هل دخلنا نافذة 22:00؟
//   3. إذا نعم + يوجد غرف محجوزة برصيد متبقي + لم نُرسل إشعاراً اليوم →
//      نُرسل إشعاراً واحداً محلياً (وليس لكل غرفة)
//   4. يُعاد الإرسال في 23:00 إذا استمر التأخر (إشعار "متأخر فعلي")
//   5. يُعاد ضبط الحالة يومياً عند منتصف الليل

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'local_db.dart';

class LatePaymentNotificationService {
  LatePaymentNotificationService._();
  static final LatePaymentNotificationService instance = LatePaymentNotificationService._();

  Timer? _timer;
  bool _isRunning = false;

  /// تتبع آخر إشعار أُرسل لمنع التكرار:
  /// - 'late_22' = إشعار نافذة 22:00 أُرسل اليوم
  /// - 'overdue_23' = إشعار نافذة 23:00 أُرسل اليوم
  /// يُعاد ضبطها يومياً عند منتصف الليل.
  String? _lastSentToday;
  String? _lastSentDate; // yyyy-MM-dd

  /// قناة الإشعارات المخصصة لتنبيهات السداد.
  static const String _channelId = 'marina_late_payment_channel';
  static const String _channelName = 'تنبيهات السداد المتأخر';
  static const String _channelDescription = 'تنبيهات عند تأخر سداد الغرف المحجوزة (22:00+)';

  /// IDs ثابتة للإشعارات حتى نتمكن من تحديثها بدل تكرارها.
  static const int _lateNotificationId = 9001;
  static const int _overdueNotificationId = 9002;

  /// يبدأ خدمة الإشعارات. آمنة للاستدعاء多次 — لا تفعل شيئاً إذا كانت تعمل.
  void start() {
    if (_isRunning) {
      return;
    }
    _isRunning = true;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    // فحص فوري عند البدء (يفيد إذا فُتح التطبيق بعد 22:00).
    _tick();
    debugPrint('🔔 LatePaymentNotificationService started');
  }

  /// يوقف الخدمة (يُستخدم عند إغلاق التطبيق أو في الاختبارات).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    debugPrint('🔕 LatePaymentNotificationService stopped');
  }

  /// الفحص الدوري: يُستدعى كل دقيقة.
  Future<void> _tick() async {
    try {
      final now = DateTime.now();
      final today = _dayKey(now);

      // ✅ إعادة ضبط الحالة اليومية عند تغير التاريخ.
      if (_lastSentDate != today) {
        _lastSentDate = today;
        _lastSentToday = null;
      }

      final hour = now.hour;

      // ✅ نافذة 22:00-23:00: تنبيه مبكر
      if (hour >= 22 && hour < 23) {
        if (_lastSentToday != 'late_22') {
          final count = await _countLatePaymentRooms();
          if (count > 0) {
            await _showLateNotification(count);
            _lastSentToday = 'late_22';
          }
        }
        return;
      }

      // ✅ نافذة 23:00-05:00: تأخر فعلي
      if (hour >= 23 || hour < 5) {
        if (_lastSentToday != 'overdue_23') {
          final count = await _countLatePaymentRooms();
          if (count > 0) {
            await _showOverdueNotification(count);
            _lastSentToday = 'overdue_23';
          }
        }
        return;
      }
    } catch (e, st) {
      debugPrint('❌ LatePaymentNotificationService tick error: $e\n$st');
    }
  }

  /// يعدّ عدد الغرف المحجوزة بنشاط مع رصيد متبقي > 0.
  Future<int> _countLatePaymentRooms() async {
    try {
      final db = DatabaseManager.instance;
      // نستخدم استعلامًا مباشرًا على الـ bookings بدل المرور عبر providers
      // لأن هذه الخدمة تعمل في الـ background وقد لا يتوفر BuildContext.
      // القيم في IN(...) ثابتة (StatusUtils.activeBookingStatuses) — آمن من SQL injection.
      final result = await db
          .customSelect(
            'SELECT COUNT(*) AS cnt FROM bookings '
            'WHERE deleted_at IS NULL '
            "AND status IN ('محجوزة','محجوز','نشط','active','confirmed','قيد الحجز','in_progress','مؤقت','provisional') "
            'AND remaining_balance_cached > 0',
          )
          .getSingle();
      final v = result.data['cnt'];
      final count = (v is int)
          ? v
          : (v is num)
          ? v.toInt()
          : 0;
      return count;
    } catch (e) {
      debugPrint('❌ Failed to count late-payment rooms: $e');
      return 0;
    }
  }

  Future<void> _showLateNotification(int roomsCount) async {
    final title = '⏰ تنبيه: $roomsCount غرفة بحاجة للسداد';
    final body =
        'حان وقت تحصيل دفعات الغرف المحجوزة قبل منتصف الليل '
        '($roomsCount غرفة برصيد متبقي). اضغط لعرض التفاصيل.';

    await _showNotification(
      id: _lateNotificationId,
      title: title,
      body: body,
      importance: Importance.high,
      priority: Priority.high,
    );
    debugPrint('🔔 Late payment notification sent: $roomsCount rooms');
  }

  Future<void> _showOverdueNotification(int roomsCount) async {
    final title = '⚠️ تأخر سداد: $roomsCount غرفة';
    final body =
        'هناك $roomsCount غرفة متأخرة السداد بعد منتصف الليل. '
        'يرجى تحصيل الدفعات في أقرب وقت.';

    await _showNotification(
      id: _overdueNotificationId,
      title: title,
      body: body,
      importance: Importance.max,
      priority: Priority.max,
    );
    debugPrint('🔔 Overdue payment notification sent: $roomsCount rooms');
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    required Importance importance,
    required Priority priority,
  }) async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();

      // ✅ تأكد من التهيئة — نُفترض أن SyncNotificationManager سبق وفعّلها،
      // لكن نضيف تهيئة احتياطية هنا لضمان عمل الإشعار حتى لو لم تُفعّل.
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(android: androidSettings);
      await plugin.initialize(initSettings);

      // ✅ إنشاء القناة المخصصة (Android 8+).
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: importance,
        priority: priority,
        icon: '@mipmap/ic_launcher',
        // ✅ اهتزاز قصير للفت الانتباه (افتراضي true لكن نُعيده صراحةً للتوضيح).
        // ignore: avoid_redundant_argument_values
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 250, 250, 250]),
        // ✅ ضوء LED برتقالي عند إظهار الإشعار على شاشة القفل.
        ledColor: const Color.fromARGB(255, 255, 152, 0),
        ledOnMs: 1000,
        ledOffMs: 1000,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await plugin.show(id, title, body, details);
    } catch (e, st) {
      debugPrint('❌ Failed to show late-payment notification: $e\n$st');
    }
  }

  /// يلغي جميع الإشعارات النشطة (يُستخدم في الاختبارات أو عند الإغلاق).
  Future<void> cancelAll() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancel(_lateNotificationId);
      await plugin.cancel(_overdueNotificationId);
    } catch (_) {
      // silent
    }
  }

  String _dayKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
