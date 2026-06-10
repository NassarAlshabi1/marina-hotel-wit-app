import 'package:flutter/foundation.dart';

import 'lark_api_client.dart';
import 'lark_config.dart';

/// أنواع أحداث الفندق التي يمكن إرسال إشعارات عنها
enum LarkEventType {
  newBooking('حجز جديد', 'green'),
  checkIn('تسجيل دخول', 'blue'),
  checkOut('تسجيل خروج', 'orange'),
  paymentReceived('دفعة مستلمة', 'green'),
  serviceRequest('طلب خدمة', 'red'),
  maintenance('طلب صيانة', 'yellow'),
  roomCleaning('تنظيف غرفة', 'turquoise'),
  cancellation('إلغاء حجز', 'red'),
  overstay('تأخير مغادرة', 'red'),
  debtReminder('تذكير دَين', 'purple'),
  newExpense('مصروف جديد', 'orange'),
  unknown('حدث', 'grey');

  const LarkEventType(this.label, this.themeColor);
  final String label;
  final String themeColor;
}

/// بيانات الحدث المطلوب إرسال إشعار عنه
class LarkEvent {

  const LarkEvent({
    required this.type,
    required this.roomNumber,
    this.guestName,
    this.guestPhone,
    this.details,
    this.eventTime,
    this.amount,
  });
  final LarkEventType type;
  final String roomNumber;
  final String? guestName;
  final String? guestPhone;
  final String? details;
  final DateTime? eventTime;
  final double? amount;
}

/// خدمة إشعارات Lark الفورية
/// ترسل إشعارات فورية عند أحداث الفندق المختلفة
class LarkNotificationService {

  LarkNotificationService._();
  static final LarkNotificationService instance = LarkNotificationService._();

  final LarkApiClient _api = LarkApiClient.instance();

  /// إرسال إشعار عن حدث فندقي
  /// تُستدعى من Repositories بعد كل عملية إنشاء/تعديل
  Future<bool> sendEventNotification(LarkEvent event) async {
    try {
      // التحقق من تفعيل Lark والإشعارات
      if (!await LarkConfig.isEnabled()) {
        return false;
      }
      if (!await LarkConfig.isNotificationsEnabled()) {
        return false;
      }

      final webhookUrl = await LarkConfig.getWebhookUrl();
      if (webhookUrl.isEmpty) {
        debugPrint('⚠️ Lark: Webhook URL غير مضبوط');
        return false;
      }

      final cardTitle = _buildCardTitle(event);
      final cardContent = _buildCardContent(event);

      final success = await _api.sendWebhookCard(
        webhookUrl: webhookUrl,
        title: cardTitle,
        content: cardContent,
        themeColor: event.type.themeColor,
      );

      if (success) {
        debugPrint('✅ Lark: تم إرسال إشعار ${event.type.label} - غرفة ${event.roomNumber}');
      }

      return success;
    } catch (e) {
      debugPrint('❌ Lark: خطأ في إرسال الإشعار: $e');
      return false;
    }
  }

  /// بناء عنوان البطاقة
  String _buildCardTitle(LarkEvent event) {
    final icon = _eventIcon(event.type);
    return '$icon ${event.type.label} - غرفة ${event.roomNumber}';
  }

  /// بناء محتوى البطاقة
  String _buildCardContent(LarkEvent event) {
    final buffer = StringBuffer();

    if (event.guestName != null && event.guestName!.isNotEmpty) {
      buffer.writeln('**الضيف:** ${event.guestName}');
    }

    if (event.guestPhone != null && event.guestPhone!.isNotEmpty) {
      buffer.writeln('**الهاتف:** ${event.guestPhone}');
    }

    buffer.writeln('**الغرفة:** ${event.roomNumber}');

    if (event.amount != null && event.amount! > 0) {
      buffer.writeln('**المبلغ:** \$${event.amount!.toStringAsFixed(2)}');
    }

    if (event.details != null && event.details!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('${event.details}');
    }

    if (event.eventTime != null) {
      buffer.writeln();
      buffer.writeln(
        '**الوقت:** ${event.eventTime!.hour.toString().padLeft(2, '0')}:${event.eventTime!.minute.toString().padLeft(2, '0')}',
      );
    }

    return buffer.toString().trimRight();
  }

  /// الحصول على رمز تعبيري مناسب للحدث
  String _eventIcon(LarkEventType type) {
    switch (type) {
      case LarkEventType.newBooking:
        return '📋';
      case LarkEventType.checkIn:
        return '🔑';
      case LarkEventType.checkOut:
        return '🚪';
      case LarkEventType.paymentReceived:
        return '💰';
      case LarkEventType.serviceRequest:
        return '📞';
      case LarkEventType.maintenance:
        return '🔧';
      case LarkEventType.roomCleaning:
        return '🧹';
      case LarkEventType.cancellation:
        return '❌';
      case LarkEventType.overstay:
        return '⏰';
      case LarkEventType.debtReminder:
        return '💳';
      case LarkEventType.newExpense:
        return '💸';
      case LarkEventType.unknown:
        return '📢';
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
    details.writeln('**تاريخ الدخول:** $checkinDate');
    if (checkoutDate != null) {
      details.writeln('**تاريخ الخروج:** $checkoutDate');
    }
    if (nights != null) {
      details.writeln('**عدد الليالي:** $nights');
    }
    if (totalDue != null) {
      details.writeln('**الإجمالي:** \$${totalDue.toStringAsFixed(2)}');
    }

    return sendEventNotification(LarkEvent(
      type: LarkEventType.newBooking,
      roomNumber: roomNumber,
      guestName: guestName,
      guestPhone: guestPhone,
      details: details.toString().trimRight(),
      eventTime: DateTime.now(),
    ),);
  }

  /// إشعار تسجيل دخول ضيف
  Future<bool> notifyCheckIn({
    required String roomNumber,
    required String guestName,
    String? guestPhone,
    int? expectedNights,
  }) {
    final details = StringBuffer();
    if (expectedNights != null) {
      details.writeln('**الليالي المتوقعة:** $expectedNights');
    }

    return sendEventNotification(LarkEvent(
      type: LarkEventType.checkIn,
      roomNumber: roomNumber,
      guestName: guestName,
      guestPhone: guestPhone,
      details: details.isEmpty ? null : details.toString().trimRight(),
      eventTime: DateTime.now(),
    ),);
  }

  /// إشعار تسجيل خروج ضيف
  Future<bool> notifyCheckOut({
    required String roomNumber,
    required String guestName,
    int? actualNights,
    double? totalPaid,
    double? remaining,
  }) {
    final details = StringBuffer();
    if (actualNights != null) {
      details.writeln('**عدد الليالي الفعلية:** $actualNights');
    }
    if (totalPaid != null) {
      details.writeln('**إجمالي المدفوع:** \$${totalPaid.toStringAsFixed(2)}');
    }
    if (remaining != null && remaining > 0) {
      details.writeln('**المتبقي:** \$${remaining.toStringAsFixed(2)}');
    }

    return sendEventNotification(LarkEvent(
      type: LarkEventType.checkOut,
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
    details.writeln('**طريقة الدفع:** $paymentMethod');
    if (remaining != null) {
      if (remaining > 0) {
        details.writeln('**المتبقي:** \$${remaining.toStringAsFixed(2)}');
      } else {
        details.writeln('**الحالة:** ✅ مسدد بالكامل');
      }
    }

    return sendEventNotification(LarkEvent(
      type: LarkEventType.paymentReceived,
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
    return sendEventNotification(LarkEvent(
      type: LarkEventType.maintenance,
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
    return sendEventNotification(LarkEvent(
      type: LarkEventType.cancellation,
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
    details.writeln('**موعد المغادرة المخطط:** $plannedCheckout');
    if (extraNights != null) {
      details.writeln('**ليالي إضافية:** $extraNights');
    }
    if (extraCharge != null) {
      details.writeln('**تكلفة إضافية:** \$${extraCharge.toStringAsFixed(2)}');
    }

    return sendEventNotification(LarkEvent(
      type: LarkEventType.overstay,
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
    return sendEventNotification(LarkEvent(
      type: LarkEventType.newExpense,
      roomNumber: '-',
      amount: amount,
      details: '$category\n${description ?? ''}',
      eventTime: DateTime.now(),
    ),);
  }
}
