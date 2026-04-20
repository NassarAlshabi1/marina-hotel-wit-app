import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// معرّف نوع النموذج
enum WhatsAppTemplateType {
  paymentConfirmation,     // تأكيد دفعة جديدة
  extendedStayPayment,     // دفعة تمديد إقامة
  refundConfirmation,      // تأكيد مردود (مغادرة مبكرة)
  accountStatement,        // كشف حساب
  paymentReminder,         // تذكير بمبلغ متبقي
  extensionConfirmation,   // تأكيد تمديد إقامة
  latePaymentAlert,        // تنبيه تأخر دفع
  activeBookingReminder,   // تذكير متبقي لحجز نشط
  salaryNotification,      // إشعار سحب/خصم راتب
  standalonePaymentAlert,  // إشعار دفعة مستقلة (للمشرف)
}

/// بيانات نموذج واحد
class WhatsAppTemplate {
  final WhatsAppTemplateType type;
  final String id;
  final String name;
  final String description;
  String content;
  bool enabled;

  WhatsAppTemplate({
    required this.type,
    required this.id,
    required this.name,
    required this.description,
    required this.content,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'content': content,
        'enabled': enabled,
      };

  factory WhatsAppTemplate.fromJson(Map<String, dynamic> json) {
    return WhatsAppTemplate(
      type: WhatsAppTemplateType.values.firstWhere(
        (t) => t.id == json['id'],
        orElse: () => WhatsAppTemplateType.paymentConfirmation,
      ),
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      content: json['content'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  /// هل هذا النوع من النماذج مفعّل؟ (يقرأ من SharedPreferences)
  static Future<bool> isEnabled(WhatsAppTemplateType type) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'wa_template_enabled_${type.id}';
    // إذا لم يُحفظ بعد → يكون مفعّل بالافتراضي
    return prefs.getBool(key) ?? true;
  }

  /// تعديل حالة النموذج
  static Future<void> setEnabled(WhatsAppTemplateType type, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wa_template_enabled_${type.id}', enabled);
  }

  /// الحصول على محتوى النموذج (المخصص أو الافتراضي)
  static Future<String> getContent(WhatsAppTemplateType type) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'wa_template_content_${type.id}';
    final custom = prefs.getString(key);
    if (custom != null && custom.isNotEmpty) return custom;
    return type.defaultContent;
  }

  /// حفظ محتوى مخصص للنموذج
  static Future<void> setContent(WhatsAppTemplateType type, String content) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wa_template_content_${type.id}', content);
  }

  /// إعادة المحتوى إلى الافتراضي
  static Future<void> resetContent(WhatsAppTemplateType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wa_template_content_${type.id}');
    await prefs.setBool('wa_template_enabled_${type.id}', true);
  }

  /// استبدال المتغيرات في النموذج
  String fill(Map<String, String> variables) {
    String result = content;
    variables.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }
}

/// معرّف النموذج
extension WhatsAppTemplateTypeX on WhatsAppTemplateType {
  String get id {
    switch (this) {
      case WhatsAppTemplateType.paymentConfirmation:
        return 'payment_confirmation';
      case WhatsAppTemplateType.extendedStayPayment:
        return 'extended_stay_payment';
      case WhatsAppTemplateType.refundConfirmation:
        return 'refund_confirmation';
      case WhatsAppTemplateType.accountStatement:
        return 'account_statement';
      case WhatsAppTemplateType.paymentReminder:
        return 'payment_reminder';
      case WhatsAppTemplateType.extensionConfirmation:
        return 'extension_confirmation';
      case WhatsAppTemplateType.latePaymentAlert:
        return 'late_payment_alert';
      case WhatsAppTemplateType.activeBookingReminder:
        return 'active_booking_reminder';
      case WhatsAppTemplateType.salaryNotification:
        return 'salary_notification';
      case WhatsAppTemplateType.standalonePaymentAlert:
        return 'standalone_payment_alert';
    }
  }

  String get name {
    switch (this) {
      case WhatsAppTemplateType.paymentConfirmation:
        return 'تأكيد دفعة';
      case WhatsAppTemplateType.extendedStayPayment:
        return 'دفعة تمديد إقامة';
      case WhatsAppTemplateType.refundConfirmation:
        return 'تأكيد مردود';
      case WhatsAppTemplateType.accountStatement:
        return 'كشف حساب';
      case WhatsAppTemplateType.paymentReminder:
        return 'تذكير بمبلغ متبقي';
      case WhatsAppTemplateType.extensionConfirmation:
        return 'تأكيد تمديد';
      case WhatsAppTemplateType.latePaymentAlert:
        return 'تنبيه تأخر دفع';
      case WhatsAppTemplateType.activeBookingReminder:
        return 'تذكير متبقي - حجوزات نشطة';
      case WhatsAppTemplateType.salaryNotification:
        return 'إشعار راتب موظف';
      case WhatsAppTemplateType.standalonePaymentAlert:
        return 'إشعار دفعة مستقلة';
    }
  }

  String get description {
    switch (this) {
      case WhatsAppTemplateType.paymentConfirmation:
        return 'يُرسل عند تسجيل دفعة جديدة من النزيل';
      case WhatsAppTemplateType.extendedStayPayment:
        return 'يُرسل عند دفع ليالي إضافية';
      case WhatsAppTemplateType.refundConfirmation:
        return 'يُرسل عند تسجيل مردود لمغادرة مبكرة';
      case WhatsAppTemplateType.accountStatement:
        return 'كشف حساب تفصيلي يُرسل يدوياً من الإجراءات';
      case WhatsAppTemplateType.paymentReminder:
        return 'تذكير بمبلغ متبقي يُرسل يدوياً';
      case WhatsAppTemplateType.extensionConfirmation:
        return 'يُرسل عند تمديد الإقامة مع الدفع';
      case WhatsAppTemplateType.latePaymentAlert:
        return 'تنبيه تأخر دفع ديون من شاشة التنبيهات';
      case WhatsAppTemplateType.activeBookingReminder:
        return 'تذكير متبقي من شاشة الحجوزات النشطة';
      case WhatsAppTemplateType.salaryNotification:
        return 'يُرسل للموظف عند تسجيل سحب/خصم راتب';
      case WhatsAppTemplateType.standalonePaymentAlert:
        return 'إشعار دفعة جديدة يُرسل للمشرف';
    }
  }

  String get defaultContent {
    switch (this) {
      case WhatsAppTemplateType.paymentConfirmation:
        return 'عزيزي {guestName}\n'
            'تم استلام دفعتك بقيمة {amount} ريال\n'
            'رقم الغرفة: {roomNumber}\n'
            '{extra}\n'
            'المبلغ المتبقي: {remaining} ريال\n'
            'شكراً لاختيارك فندق مارينا\n'
            'للاستفسار: {hotelPhone}';

      case WhatsAppTemplateType.extendedStayPayment:
        return 'عزيزي {guestName}، تم استلام دفعة بقيمة: {amount} ريال\n'
            'رقم الغرفة: {roomNumber}\n'
            'دفع {nightsPaid} ليلة/ليالي إضافية\n'
            'المبلغ المتبقي: {remaining} ريال\n'
            'شكراً لاختيارك فندق مارينا\n'
            'للاستفسار: {hotelPhone}';

      case WhatsAppTemplateType.refundConfirmation:
        return 'عزيزي {guestName}، تم تسجيل مغادرتكم المبكرة\n'
            'رقم الغرفة: {roomNumber}\n'
            'مبلغ المردود: {refundAmount} ريال\n'
            'عدد الليالي غير المستخدمة: {unusedNights} ليلة/ليالي\n'
            'شكراً لاختيارك فندق مارينا\n'
            'للاستفسار: {hotelPhone}';

      case WhatsAppTemplateType.accountStatement:
        return 'كشف حساب - MARINA HOTEL\n'
            '━━━━━━━━━━━\n'
            'العميل: {guestName}\n'
            'الغرفة: {roomNumber} | {nights} ليلة | الوصول: {checkin}\n'
            'المغادرة: {checkout}\n'
            '━━━━━━━━━━━\n'
            'الإجمالي: {total} ريال\n'
            '{discountInfo}\n'
            'المدفوع: {paid} ريال\n'
            'المتبقي: {remaining} ريال\n'
            'الحالة: {status}\n'
            '━━━━━━━━━━━\n'
            '{payments}\n'
            '{debtInfo}\n'
            '━━━━━━━━━━━\n'
            'مارينا هوتل | {hotelPhone}';

      case WhatsAppTemplateType.paymentReminder:
        return 'عزيزي {guestName}\n'
            'تذكير بالمبلغ المتبقي\n'
            'رقم الغرفة: {roomNumber}\n'
            'المبلغ الإجمالي: {totalAmount}\n'
            'المبلغ المدفوع: {paidAmount}\n'
            'المبلغ المتبقي: {remainingAmount}\n\n'
            'نرجو منكم تسديد المبلغ المتبقي في أقرب وقت ممكن\n\n'
            'شكراً لتعاونكم معنا\n'
            'للاستفسار: {hotelPhone}';

      case WhatsAppTemplateType.extensionConfirmation:
        return 'عزيزي {guestName}، تم تمديد إقامتكم\n'
            'رقم الغرفة: {roomNumber}\n'
            'ليالي إضافية: {additionalNights} ليلة/ليالي\n'
            'المبلغ المدفوع: {amount} ريال\n'
            'تاريخ المغادرة الجديد: {newCheckout}\n'
            'شكراً لاختيارك فندق مارينا\n'
            'للاستفسار: {hotelPhone}';

      case WhatsAppTemplateType.latePaymentAlert:
        return 'تنبيه من فندق مارينا\n'
            '━━━━━━━━━━━━━━━\n\n'
            'عزيزي/عزيزتي {guestName}\n\n'
            'نتوجه لكم بهذا التنبيه بخصوص مبلغ متأخر السداد:\n\n'
            '{daysOverdueInfo}'
            'رقم الغرفة: {roomNumber}\n'
            'فترة الإقامة: {checkin} إلى {checkout}\n'
            'إجمالي المبلغ: {totalAmount}\n'
            'المدفوع: {paidAmount}\n'
            'المبلغ المتبقي: {remainingAmount}\n'
            '{debtReason}\n\n'
            'نرجو منكم التكرم بتسديد المبلغ المتبقي في أقرب وقت ممكن.\n\n'
            'مع خالص التحية والتقدير\n'
            'فندق مارينا\n'
            'للاستفسار: {hotelPhone}';

      case WhatsAppTemplateType.activeBookingReminder:
        return 'عزيزي/عزيزتي {guestName}\n'
            '━━━━━━━━━━━━━━━\n\n'
            'تحية طيبة من فندق مارينا\n\n'
            'نتوجه لكم بتذكير بخصوص المبلغ المتبقي لإقامتكم:\n\n'
            'رقم الغرفة: {roomNumber}\n'
            'تاريخ الوصول: {checkin}\n'
            'تاريخ المغادرة: {checkout}\n'
            'عدد الليالي: {nights}\n\n'
            'الإجمالي: {total} ريال\n'
            'المدفوع: {paid} ريال\n'
            'المبلغ المتبقي: {remaining} ريال\n'
            '{overdueWarning}\n\n'
            'نرجو منكم التكرم بتسديد المبلغ المتبقي في أقرب وقت ممكن.\n\n'
            'مع خالص التحية والتقدير\n'
            'فندق مارينا\n'
            'للاستفسار: {hotelPhone}';

      case WhatsAppTemplateType.salaryNotification:
        return 'مرحباً {employeeName}\n\n'
            'تم تسجيل {actionText} راتب بقيمة {amount}\n'
            'التاريخ: {date}\n'
            '{remainingText}\n\n'
            'فندق مارينا\n'
            'للاستفسار: {hotelPhone}';

      case WhatsAppTemplateType.standalonePaymentAlert:
        return 'إشعار دفعة جديدة\n'
            '━━━━━━━━━━━━━━━\n'
            'المبلغ: {amount}\n'
            'طريقة الدفع: {method}\n'
            'التاريخ: {date}\n'
            'اليوم الفندقي: {hotelDay}\n'
            '{notes}\n'
            '━━━━━━━━━━━━━━━\n'
            'فندق مارينا';
    }
  }

  IconData get icon {
    switch (this) {
      case WhatsAppTemplateType.paymentConfirmation:
        return Icons.receipt;
      case WhatsAppTemplateType.extendedStayPayment:
        return Icons.night_shelter;
      case WhatsAppTemplateType.refundConfirmation:
        return Icons.assignment_return;
      case WhatsAppTemplateType.accountStatement:
        return Icons.description;
      case WhatsAppTemplateType.paymentReminder:
        return Icons.notifications_active;
      case WhatsAppTemplateType.extensionConfirmation:
        return Icons.date_range;
      case WhatsAppTemplateType.latePaymentAlert:
        return Icons.warning_amber;
      case WhatsAppTemplateType.activeBookingReminder:
        return Icons.pending_actions;
      case WhatsAppTemplateType.salaryNotification:
        return Icons.account_balance_wallet;
      case WhatsAppTemplateType.standalonePaymentAlert:
        return Icons.info;
    }
  }
}

/// مدير النماذج المركزي
class WhatsAppTemplateManager {
  static const String _hotelPhoneKey = 'wa_hotel_phone';
  static const String _defaultHotelPhone = '9677734587456';

  /// الحصول على رقم الفندق
  static Future<String> getHotelPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_hotelPhoneKey) ?? _defaultHotelPhone;
  }

  /// تعديل رقم الفندق
  static Future<void> setHotelPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hotelPhoneKey, phone);
  }

  /// هل النموذج مفعّل؟
  static Future<bool> isTemplateEnabled(WhatsAppTemplateType type) async {
    return WhatsAppTemplate.isEnabled(type);
  }

  /// تعديل حالة النموذج
  static Future<void> setTemplateEnabled(
      WhatsAppTemplateType type, bool enabled) async {
    await WhatsAppTemplate.setEnabled(type, enabled);
  }

  /// بناء الرسالة من النموذج مع استبدال المتغيرات
  /// يُرجع null إذا كان النموذج معطّل
  static Future<String?> buildMessage(
    WhatsAppTemplateType type,
    Map<String, String> variables,
  ) async {
    final enabled = await isTemplateEnabled(type);
    if (!enabled) return null;

    var content = await WhatsAppTemplate.getContent(type);
    final hotelPhone = await getHotelPhone();

    // استبدال المتغيرات
    variables.forEach((key, value) {
      content = content.replaceAll('{$key}', value);
    });

    // استبدال رقم الفندق
    content = content.replaceAll('{hotelPhone}', hotelPhone);

    return content;
  }

  /// بناء الرسالة بدون التحقق من التفعيل (للاستخدام الداخلي)
  static Future<String> buildMessageForce(
    WhatsAppTemplateType type,
    Map<String, String> variables,
  ) async {
    var content = await WhatsAppTemplate.getContent(type);
    final hotelPhone = await getHotelPhone();

    variables.forEach((key, value) {
      content = content.replaceAll('{$key}', value);
    });
    content = content.replaceAll('{hotelPhone}', hotelPhone);

    return content;
  }

  /// الحصول على محتوى النموذج (للعرض في الإعدادات)
  static Future<String> getTemplateContent(WhatsAppTemplateType type) async {
    return WhatsAppTemplate.getContent(type);
  }

  /// حفظ محتوى مخصص
  static Future<void> saveTemplateContent(
      WhatsAppTemplateType type, String content) async {
    await WhatsAppTemplate.setContent(type, content);
  }

  /// إعادة نموذج للافتراضي
  static Future<void> resetTemplate(WhatsAppTemplateType type) async {
    await WhatsAppTemplate.resetContent(type);
  }

  /// إعادة جميع النماذج للافتراضي
  static Future<void> resetAllTemplates() async {
    for (final type in WhatsAppTemplateType.values) {
      await WhatsAppTemplate.resetContent(type);
    }
  }

  /// الحصول على قائمة جميع النماذج مع حالاتها
  static Future<List<WhatsAppTemplate>> getAllTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final templates = <WhatsAppTemplate>[];

    for (final type in WhatsAppTemplateType.values) {
      final content = prefs.getString('wa_template_content_${type.id}');
      final enabled = prefs.getBool('wa_template_enabled_${type.id}') ?? true;
      final isCustom = content != null && content.isNotEmpty;

      templates.add(WhatsAppTemplate(
        type: type,
        id: type.id,
        name: type.name,
        description: type.description,
        content: isCustom ? content : type.defaultContent,
        enabled: enabled,
      ));
    }

    return templates;
  }

  /// حفظ جميع النماذج دفعة واحدة
  static Future<void> saveAllTemplates(
      List<WhatsAppTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    for (final template in templates) {
      await prefs.setString(
          'wa_template_content_${template.id}', template.content);
      await prefs.setBool(
          'wa_template_enabled_${template.id}', template.enabled);
    }
  }

  /// تصدير النماذج كـ JSON
  static Future<String> exportTemplates() async {
    final templates = await getAllTemplates();
    final jsonList = templates.map((t) => t.toJson()).toList();
    return jsonEncode(jsonList);
  }

  /// استيراد النماذج من JSON
  static Future<int> importTemplates(String jsonString) async {
    try {
      final list = jsonDecode(jsonString) as List;
      int count = 0;
      for (final item in list) {
        final template = WhatsAppTemplate.fromJson(item as Map<String, dynamic>);
        await saveTemplateContent(template.type, template.content);
        await setTemplateEnabled(template.type, template.enabled);
        count++;
      }
      return count;
    } catch (e) {
      debugPrint('خطأ في استيراد النماذج: $e');
      return 0;
    }
  }
}
