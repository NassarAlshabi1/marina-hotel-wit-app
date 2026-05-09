import 'package:flutter/foundation.dart';

import 'telegram_config.dart';
import 'telegram_service.dart';

/// أنواع أحداث الفندق
enum TelegramEventType {
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

  const TelegramEventType(this.label);
  final String label;
}

/// بيانات الحدث
class TelegramEvent {

  const TelegramEvent({
    required this.type,
    required this.roomNumber,
    this.guestName,
    this.guestPhone,
    this.details,
    this.eventTime,
    this.amount,
  });
  final TelegramEventType type;
  final String roomNumber;
  final String? guestName;
  final String? guestPhone;
  final String? details;
  final DateTime? eventTime;
  final double? amount;
}

/// خدمة إشعارات Telegram الفورية
class TelegramNotificationService {

  TelegramNotificationService._();
  static TelegramNotificationService? _instance;
  static TelegramNotificationService get instance =>
      _instance ??= TelegramNotificationService._();

  final TelegramApiClient _api = TelegramApiClient.instance;

  /// أيقونات لكل نوع حدث
  String _icon(TelegramEventType type) {
    switch (type) {
      case TelegramEventType.newBooking:
        return '📋';
      case TelegramEventType.checkIn:
        return '🔑';
      case TelegramEventType.checkOut:
        return '🚪';
      case TelegramEventType.paymentReceived:
        return '💰';
      case TelegramEventType.maintenance:
        return '🔧';
      case TelegramEventType.cancellation:
        return '❌';
      case TelegramEventType.overstay:
        return '⏰';
      case TelegramEventType.debtReminder:
        return '💳';
      case TelegramEventType.newExpense:
        return '💸';
      case TelegramEventType.unknown:
        return '📢';
    }
  }

  /// إرسال إشعار عن حدث فندقي
  Future<bool> sendEventNotification(TelegramEvent event) async {
    try {
      if (!await TelegramConfig.isEnabled()) return false;
      if (!await TelegramConfig.isNotificationsEnabled()) return false;

      final buffer = StringBuffer();
      buffer.writeln('${_icon(event.type)} <b>${event.type.label}</b>');
      buffer.writeln('━━━━━━━━━━━━━━━━━');

      if (event.guestName != null && event.guestName!.isNotEmpty) {
        buffer.writeln('👤 الضيف: <b>${event.guestName}</b>');
      }

      buffer.writeln('🏨 الغرفة: <b>${event.roomNumber}</b>');

      if (event.guestPhone != null && event.guestPhone!.isNotEmpty) {
        buffer.writeln('📞 الهاتف: ${event.guestPhone}');
      }

      if (event.amount != null && event.amount! > 0) {
        buffer.writeln('💵 المبلغ: <b>\$${event.amount!.toStringAsFixed(2)}</b>');
      }

      if (event.details != null && event.details!.isNotEmpty) {
        buffer.writeln();
        buffer.writeln(event.details);
      }

      if (event.eventTime != null) {
        buffer.writeln();
        buffer.writeln(
          '🕐 ${event.eventTime!.hour.toString().padLeft(2, '0')}:${event.eventTime!.minute.toString().padLeft(2, '0')}',
        );
      }

      buffer.writeln();
      buffer.writeln('<i>Marina Hotel App 🏨</i>');

      final success = await _api.sendToDefaultChat(text: buffer.toString().trimRight());

      if (success) {
        debugPrint('✅ Telegram: تم إرسال إشعار ${event.type.label} - غرفة ${event.roomNumber}');
      }

      return success;
    } catch (Object e) {
      debugPrint('❌ Telegram: خطأ في إرسال الإشعار: $e');
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

    return sendEventNotification(TelegramEvent(
      type: TelegramEventType.newBooking,
      roomNumber: roomNumber,
      guestName: guestName,
      guestPhone: guestPhone,
      details: details.isEmpty ? null : details.toString().trimRight(),
      eventTime: DateTime.now(),
    ),);
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

    return sendEventNotification(TelegramEvent(
      type: TelegramEventType.checkIn,
      roomNumber: roomNumber,
      guestName: guestName,
      guestPhone: guestPhone,
      details: details.isEmpty ? null : details.toString().trimRight(),
      eventTime: DateTime.now(),
    ),);
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

    return sendEventNotification(TelegramEvent(
      type: TelegramEventType.checkOut,
      roomNumber: roomNumber,
      guestName: guestName,
      details: details.isEmpty ? null : details.toString().trimRight(),
      eventTime: DateTime.now(),
    ),);
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

    return sendEventNotification(TelegramEvent(
      type: TelegramEventType.paymentReceived,
      roomNumber: roomNumber,
      guestName: guestName,
      amount: amount,
      details: details.toString().trimRight(),
      eventTime: DateTime.now(),
    ),);
  }

  /// إشعار طلب صيانة
  Future<bool> notifyMaintenance({
    required String roomNumber,
    required String description,
    String? reportedBy,
  }) {
    return sendEventNotification(TelegramEvent(
      type: TelegramEventType.maintenance,
      roomNumber: roomNumber,
      guestName: reportedBy,
      details: description,
      eventTime: DateTime.now(),
    ),);
  }

  /// إشعار إلغاء حجز
  Future<bool> notifyCancellation({
    required String roomNumber,
    required String guestName,
    String? reason,
  }) {
    return sendEventNotification(TelegramEvent(
      type: TelegramEventType.cancellation,
      roomNumber: roomNumber,
      guestName: guestName,
      details: reason,
      eventTime: DateTime.now(),
    ),);
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

    return sendEventNotification(TelegramEvent(
      type: TelegramEventType.overstay,
      roomNumber: roomNumber,
      guestName: guestName,
      details: details.toString().trimRight(),
      eventTime: DateTime.now(),
    ),);
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

    return sendEventNotification(TelegramEvent(
      type: TelegramEventType.newExpense,
      roomNumber: '-',
      amount: amount,
      details: details.toString().trimRight(),
      eventTime: DateTime.now(),
    ),);
  }
}
