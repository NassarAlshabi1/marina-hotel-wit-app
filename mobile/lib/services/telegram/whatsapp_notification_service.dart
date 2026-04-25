import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'telegram_config.dart';

/// أنواع أحداث الفندق
enum WhatsAppEventType {
  newBooking('حجز جديد'),
  checkIn('تسجيل دخول'),
  checkOut('تسجيل خروج'),
  paymentReceived('دفعة مستلمة'),
  maintenance('طلب صيانة'),
  cancellation('إلغاء حجز'),
  overstay('تأخير مغادرة'),
  debtReminder('تذكير دَين'),
  newExpense('مصروف جديد'),
  unknown('حدث');

  const WhatsAppEventType(this.label);
  final String label;
}

/// بيانات الحدث
class WhatsAppEvent {
  final WhatsAppEventType type;
  final String roomNumber;
  final String? guestName;
  final String? guestPhone;
  final String? details;
  final DateTime? eventTime;
  final double? amount;

  const WhatsAppEvent({
    required this.type,
    required this.roomNumber,
    this.guestName,
    this.guestPhone,
    this.details,
    this.eventTime,
    this.amount,
  });
}

/// خدمة إشعارات واتساب الفورية عبر CallMeBot
class WhatsAppNotificationService {
  static WhatsAppNotificationService? _instance;
  static WhatsAppNotificationService get instance =>
      _instance ??= WhatsAppNotificationService._();

  WhatsAppNotificationService._();

  // CallMeBot WhatsApp API
  static const String _callMeBotUrl = 'https://api.callmebot.com/whatsapp.php';
  static const String _defaultPhone = '967773749389';
  static const String _defaultApiKey = '7379268';
  final http.Client _httpClient = http.Client();

  /// أيقونات لكل نوع حدث
  String _icon(WhatsAppEventType type) {
    switch (type) {
      case WhatsAppEventType.newBooking:
        return '📋';
      case WhatsAppEventType.checkIn:
        return '🔑';
      case WhatsAppEventType.checkOut:
        return '🚪';
      case WhatsAppEventType.paymentReceived:
        return '💰';
      case WhatsAppEventType.maintenance:
        return '🔧';
      case WhatsAppEventType.cancellation:
        return '❌';
      case WhatsAppEventType.overstay:
        return '⏰';
      case WhatsAppEventType.debtReminder:
        return '💳';
      case WhatsAppEventType.newExpense:
        return '💸';
      case WhatsAppEventType.unknown:
        return '📢';
    }
  }

  /// إرسال رسالة عبر CallMeBot WhatsApp API
  Future<bool> _sendViaCallMeBot(String message) async {
    try {
      final url = Uri.parse(
        '$_callMeBotUrl'
        '?phone=$_defaultPhone'
        '&text=${Uri.encodeComponent(message)}'
        '&apikey=$_defaultApiKey',
      );

      final response = await _httpClient.get(url);
      final body = response.body;

      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(body) as Map<String, dynamic>;
          if (json['success'] == true || json['sent'] == true) {
            return true;
          }
        } catch (_) {
          if (body.toLowerCase().contains('sent') ||
              body.toLowerCase().contains('ok') ||
              body.toLowerCase().contains('success')) {
            return true;
          }
        }
        debugPrint('⚠️ WhatsApp: فشل الإرسال — $body');
        return false;
      }
      debugPrint('⚠️ WhatsApp: HTTP ${response.statusCode} — $body');
      return false;
    } catch (e) {
      debugPrint('❌ WhatsApp: خطأ في الإرسال — $e');
      return false;
    }
  }

  /// إرسال إشعار عن حدث فندقي
  Future<bool> sendEventNotification(WhatsAppEvent event) async {
    try {
      if (!await TelegramConfig.isEnabled()) return false;
      if (!await TelegramConfig.isNotificationsEnabled()) return false;

      final buffer = StringBuffer();
      buffer.writeln('${_icon(event.type)} *${event.type.label}*');
      buffer.writeln('━━━━━━━━━━━━━━━━━');

      if (event.guestName != null && event.guestName!.isNotEmpty) {
        buffer.writeln('👤 الضيف: *${event.guestName}*');
      }

      buffer.writeln('🏨 الغرفة: *${event.roomNumber}*');

      if (event.guestPhone != null && event.guestPhone!.isNotEmpty) {
        buffer.writeln('📞 الهاتف: ${event.guestPhone}');
      }

      if (event.amount != null && event.amount! > 0) {
        buffer.writeln('💵 المبلغ: *\$${event.amount!.toStringAsFixed(2)}*');
      }

      if (event.details != null && event.details!.isNotEmpty) {
        buffer.writeln('');
        buffer.writeln(event.details!);
      }

      if (event.eventTime != null) {
        buffer.writeln('');
        buffer.writeln(
          '🕐 ${event.eventTime!.hour.toString().padLeft(2, '0')}:${event.eventTime!.minute.toString().padLeft(2, '0')}',
        );
      }

      buffer.writeln('');
      buffer.writeln('Marina Hotel App 🏨');

      final success = await _sendViaCallMeBot(buffer.toString().trimRight());

      if (success) {
        debugPrint('✅ WhatsApp: تم إرسال إشعار ${event.type.label} - غرفة ${event.roomNumber}');
      }

      return success;
    } catch (e) {
      debugPrint('❌ WhatsApp: خطأ في إرسال الإشعار: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────
  // دوال مختصرة لكل نوع حدث
  // ─────────────────────────────────────────────────

  /// إشعار حجز جديد
  Future<bool> notifyNewBooking({
    required String roomNumber,
    required String guestName,
    String? guestPhone,
    String? checkinDate,
    String? checkoutDate,
    int? nights,
    double? totalDue,
  }) {
    final details = StringBuffer();
    if (checkinDate != null) details.writeln('📅 الدخول: $checkinDate');
    if (checkoutDate != null) details.writeln('📅 الخروج: $checkoutDate');
    if (nights != null) details.writeln('🌙 الليالي: $nights');
    if (totalDue != null) details.writeln('💰 الإجمالي: \$${totalDue.toStringAsFixed(2)}');

    return sendEventNotification(WhatsAppEvent(
      type: WhatsAppEventType.newBooking,
      roomNumber: roomNumber,
      guestName: guestName,
      guestPhone: guestPhone,
      details: details.isEmpty ? null : details.toString().trimRight(),
      eventTime: DateTime.now(),
    ));
  }

  /// إشعار تسجيل دخول
  Future<bool> notifyCheckIn({
    required String roomNumber,
    required String guestName,
    String? guestPhone,
    int? expectedNights,
  }) {
    final details = StringBuffer();
    if (expectedNights != null) details.writeln('🌙 الليالي المتوقعة: $expectedNights');

    return sendEventNotification(WhatsAppEvent(
      type: WhatsAppEventType.checkIn,
      roomNumber: roomNumber,
      guestName: guestName,
      guestPhone: guestPhone,
      details: details.isEmpty ? null : details.toString().trimRight(),
      eventTime: DateTime.now(),
    ));
  }

  /// إشعار تسجيل خروج
  Future<bool> notifyCheckOut({
    required String roomNumber,
    required String guestName,
    int? actualNights,
    double? totalPaid,
    double? remaining,
  }) {
    final details = StringBuffer();
    if (actualNights != null) details.writeln('🌙 الليالي الفعلية: $actualNights');
    if (totalPaid != null) details.writeln('💰 المدفوع: \$${totalPaid.toStringAsFixed(2)}');
    if (remaining != null && remaining > 0) {
      details.writeln('⚠️ المتبقي: \$${remaining.toStringAsFixed(2)}');
    }

    return sendEventNotification(WhatsAppEvent(
      type: WhatsAppEventType.checkOut,
      roomNumber: roomNumber,
      guestName: guestName,
      details: details.isEmpty ? null : details.toString().trimRight(),
      eventTime: DateTime.now(),
    ));
  }

  /// إشعار استلام دفعة
  Future<bool> notifyPayment({
    required String roomNumber,
    required String guestName,
    required double amount,
    required String paymentMethod,
    double? remaining,
  }) {
    final details = StringBuffer();
    details.writeln('💳 طريقة الدفع: $paymentMethod');
    if (remaining != null) {
      if (remaining > 0) {
        details.writeln('⚠️ المتبقي: \$${remaining.toStringAsFixed(2)}');
      } else {
        details.writeln('✅ مسدد بالكامل');
      }
    }

    return sendEventNotification(WhatsAppEvent(
      type: WhatsAppEventType.paymentReceived,
      roomNumber: roomNumber,
      guestName: guestName,
      amount: amount,
      details: details.toString().trimRight(),
      eventTime: DateTime.now(),
    ));
  }

  /// إشعار طلب صيانة
  Future<bool> notifyMaintenance({
    required String roomNumber,
    required String description,
    String? reportedBy,
  }) {
    return sendEventNotification(WhatsAppEvent(
      type: WhatsAppEventType.maintenance,
      roomNumber: roomNumber,
      guestName: reportedBy,
      details: description,
      eventTime: DateTime.now(),
    ));
  }

  /// إشعار إلغاء حجز
  Future<bool> notifyCancellation({
    required String roomNumber,
    required String guestName,
    String? reason,
  }) {
    return sendEventNotification(WhatsAppEvent(
      type: WhatsAppEventType.cancellation,
      roomNumber: roomNumber,
      guestName: guestName,
      details: reason,
      eventTime: DateTime.now(),
    ));
  }

  /// إشعار تأخير مغادرة
  Future<bool> notifyOverstay({
    required String roomNumber,
    required String guestName,
    required String plannedCheckout,
    int? extraNights,
    double? extraCharge,
  }) {
    final details = StringBuffer();
    details.writeln('📅 موعد المغادرة المخطط: $plannedCheckout');
    if (extraNights != null) details.writeln('➕ ليالي إضافية: $extraNights');
    if (extraCharge != null) details.writeln('💵 تكلفة إضافية: \$${extraCharge.toStringAsFixed(2)}');

    return sendEventNotification(WhatsAppEvent(
      type: WhatsAppEventType.overstay,
      roomNumber: roomNumber,
      guestName: guestName,
      details: details.toString().trimRight(),
      eventTime: DateTime.now(),
    ));
  }

  /// إشعار مصروف جديد
  Future<bool> notifyNewExpense({
    required String category,
    required double amount,
    String? description,
  }) {
    final details = StringBuffer();
    details.writeln('📂 التصنيف: $category');
    if (description != null && description.isNotEmpty) {
      details.writeln(description);
    }

    return sendEventNotification(WhatsAppEvent(
      type: WhatsAppEventType.newExpense,
      roomNumber: '-',
      amount: amount,
      details: details.toString().trimRight(),
      eventTime: DateTime.now(),
    ));
  }
}
