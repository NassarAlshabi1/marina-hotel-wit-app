import 'package:flutter/foundation.dart';

import '../../utils/hotel_time_engine.dart';
import '../local_db.dart';
import 'lark_api_client.dart';
import 'lark_config.dart';

/// نموذج بيانات التقرير اليومي
class DailyReportData {

  DailyReportData({
    required this.hotelDayKey,
    required this.reportDate,
    required this.totalRooms,
    required this.occupiedRooms,
    required this.availableRooms,
    required this.cleaningRooms,
    required this.maintenanceRooms,
    required this.occupancyRate,
    required this.newBookingsToday,
    required this.checkInsToday,
    required this.checkOutsToday,
    required this.activeBookings,
    required this.overstayBookings,
    required this.totalIncome,
    required this.totalExpenses,
    required this.netRevenue,
    required this.totalPayments,
    required this.totalExpensesCount,
    required this.unsettledDebts,
  });
  final String hotelDayKey;
  final String reportDate;
  final int totalRooms;
  final int occupiedRooms;
  final int availableRooms;
  final int cleaningRooms;
  final int maintenanceRooms;
  final double occupancyRate;

  final int newBookingsToday;
  final int checkInsToday;
  final int checkOutsToday;
  final int activeBookings;
  final int overstayBookings;

  final double totalIncome;
  final double totalExpenses;
  final double netRevenue;

  final int totalPayments;
  final int totalExpensesCount;
  final int unsettledDebts;

  Map<String, dynamic> toJson() => {
    'hotelDayKey': hotelDayKey,
    'reportDate': reportDate,
    'totalRooms': totalRooms,
    'occupiedRooms': occupiedRooms,
    'availableRooms': availableRooms,
    'cleaningRooms': cleaningRooms,
    'maintenanceRooms': maintenanceRooms,
    'occupancyRate': occupancyRate,
    'newBookingsToday': newBookingsToday,
    'checkInsToday': checkInsToday,
    'checkOutsToday': checkOutsToday,
    'activeBookings': activeBookings,
    'overstayBookings': overstayBookings,
    'totalIncome': totalIncome,
    'totalExpenses': totalExpenses,
    'netRevenue': netRevenue,
    'totalPayments': totalPayments,
    'totalExpensesCount': totalExpensesCount,
    'unsettledDebts': unsettledDebts,
  };
}

/// خدمة التقارير اليومية التلقائية
/// تجمع بيانات اليوم الفندقي وترسلها عبر Lark في الوقت المحدد
class LarkReportService {

  LarkReportService._();
  static final LarkReportService instance = LarkReportService._();

  final LarkApiClient _api = LarkApiClient.instance();

  /// تجميع بيانات التقرير اليومي من قاعدة البيانات
  Future<DailyReportData> collectReportData() async {
    try {
      final db = DatabaseManager.instance;
      final hotelDayKey = HotelTimeEngine.getHotelDayKey();
      final now = DateTime.now();

      // ─────────────────────────────────
      // بيانات الغرف
      // ─────────────────────────────────
      final allRooms = await db.select(db.rooms).get();
      final totalRooms = allRooms.length;
      int occupiedRooms = 0;
      int availableRooms = 0;
      int cleaningRooms = 0;
      int maintenanceRooms = 0;

      for (final room in allRooms) {
        final status = room.status.toLowerCase();
        if (status == 'محجوزة' || status == 'مشغولة') {
          occupiedRooms++;
        } else if (status == 'شاغرة' || status == 'متاحة') {
          availableRooms++;
        } else if (status == 'تنظيف') {
          cleaningRooms++;
        } else if (status == 'صيانة') {
          maintenanceRooms++;
        }
      }

      final occupancyRate = totalRooms > 0
          ? (occupiedRooms / totalRooms * 100)
          : 0.0;

      // ─────────────────────────────────

      final allBookings = await db.select(db.bookings).get()
        ..where((b) => b.deletedAt == null);

      int newBookingsToday = 0;
      int checkInsToday = 0;
      int checkOutsToday = 0;
      int activeBookings = 0;
      int overstayBookings = 0;

      for (final booking in allBookings) {
        if (booking.deletedAt != null) {
          continue;
        }

        final status = booking.status.toLowerCase();

        // حجوزات نشطة
        if (status == 'نشط' || status == 'محجوزة') {
          activeBookings++;
        }

        // حجوزات جديدة اليوم
        if (booking.checkinDate == hotelDayKey ||
            booking.createdAtIso?.substring(0, 10) == hotelDayKey) {
          newBookingsToday++;
        }

        // تسجيلات دخول اليوم
        if (booking.hotelDayCheckin == hotelDayKey) {
          checkInsToday++;
        }

        // تسجيلات خروج اليوم
        if (booking.hotelDayCheckout == hotelDayKey ||
            booking.actualCheckout?.substring(0, 10) == hotelDayKey) {
          checkOutsToday++;
        }

        // تأخير مغادرة
        if (booking.checkoutDate != null &&
            booking.actualCheckout == null &&
            booking.checkoutDate!.compareTo(hotelDayKey) < 0) {
          overstayBookings++;
        }
      }

      // ─────────────────────────────────
      // بيانات المدفوعات
      // ─────────────────────────────────
      final paymentsQuery = await db.select(db.payments).get();
      double totalIncome = 0;
      int totalPayments = 0;

      for (final payment in paymentsQuery) {
        if (payment.hotelDayKey == hotelDayKey && !payment.isVoided) {
          totalIncome += payment.amount;
          totalPayments++;
        }
      }

      // ─────────────────────────────────
      // بيانات المصروفات
      // ─────────────────────────────────
      final expensesQuery = await db.select(db.expenses).get();
      double totalExpenses = 0;
      int totalExpensesCount = 0;

      for (final expense in expensesQuery) {
        if (expense.hotelDayKey == hotelDayKey) {
          totalExpenses += expense.amount;
          totalExpensesCount++;
        }
      }

      // ─────────────────────────────────
      // بيانات الديون غير المسددة
      // ─────────────────────────────────
      final debtsQuery = await db.select(db.debts).get();
      int unsettledDebts = 0;
      for (final debt in debtsQuery) {
        if (debt.isSettled == 0 && debt.deletedAt == null) {
          unsettledDebts++;
        }
      }

      return DailyReportData(
        hotelDayKey: hotelDayKey,
        reportDate: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        totalRooms: totalRooms,
        occupiedRooms: occupiedRooms,
        availableRooms: availableRooms,
        cleaningRooms: cleaningRooms,
        maintenanceRooms: maintenanceRooms,
        occupancyRate: occupancyRate,
        newBookingsToday: newBookingsToday,
        checkInsToday: checkInsToday,
        checkOutsToday: checkOutsToday,
        activeBookings: activeBookings,
        overstayBookings: overstayBookings,
        totalIncome: totalIncome,
        totalExpenses: totalExpenses,
        netRevenue: totalIncome - totalExpenses,
        totalPayments: totalPayments,
        totalExpensesCount: totalExpensesCount,
        unsettledDebts: unsettledDebts,
      );
    } catch (e) {
      debugPrint('❌ Lark Report: خطأ في تجميع بيانات التقرير: $e');
      rethrow;
    }
  }

  /// بناء محتوى التقرير بتنسيق Markdown
  String _buildReportMarkdown(DailyReportData data) {
    final buffer = StringBuffer();

    buffer.writeln('**📅 التاريخ:** ${data.reportDate}');
    buffer.writeln();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');

    // قسم الغرف
    buffer.writeln();
    buffer.writeln('**🏨 حالة الغرف**');
    buffer.writeln();
    buffer.writeln(
      '| الإجمالي | صيانة | تنظيف | متاحة | مشغولة |',
    );
    buffer.writeln(
      '|:---:|:---:|:---:|:---:|:---:|',
    );
    buffer.writeln(
      '| ${data.totalRooms} | ${data.maintenanceRooms} | ${data.cleaningRooms} | ${data.availableRooms} | ${data.occupiedRooms} |',
    );
    buffer.writeln();
    buffer.writeln(
      '**نسبة الإشغال:** ${data.occupancyRate.toStringAsFixed(1)}%',
    );

    buffer.writeln();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');

    // قسم الحجوزات
    buffer.writeln();
    buffer.writeln('**📋 الحجوزات**');
    buffer.writeln();
    buffer.writeln('- **حجوزات جديدة اليوم:** ${data.newBookingsToday}');
    buffer.writeln('- **تسجيلات دخول:** ${data.checkInsToday}');
    buffer.writeln('- **تسجيلات خروج:** ${data.checkOutsToday}');
    buffer.writeln('- **حجوزات نشطة:** ${data.activeBookings}');

    if (data.overstayBookings > 0) {
      buffer.writeln('- ⚠️ **تأخير مغادرة:** ${data.overstayBookings}');
    }

    buffer.writeln();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');

    // قسم المالية
    buffer.writeln();
    buffer.writeln('**💰 المالية**');
    buffer.writeln();
    buffer.writeln(
      '| المصروفات | صافي الربح | الإيرادات | البند |',
    );
    buffer.writeln(
      '|:---:|:---:|:---:|:---|',
    );
    buffer.writeln(
      '| \$${data.totalExpenses.toStringAsFixed(2)} | '
      '\$${data.netRevenue.toStringAsFixed(2)} | '
      '\$${data.totalIncome.toStringAsFixed(2)} | **المبالغ** |',
    );
    buffer.writeln();
    buffer.writeln(
      '| ${data.totalExpensesCount} مصروف | ${data.totalPayments} دفعة | **العدد** |',
    );

    if (data.unsettledDebts > 0) {
      buffer.writeln();
      buffer.writeln('⚠️ **ديون غير مسددة:** ${data.unsettledDebts}');
    }

    return buffer.toString();
  }

  /// بناء البطاقة التفاعلية للتقرير اليومي
  Map<String, dynamic> _buildReportCard(DailyReportData data) {
    // تحديد لون البطاقة حسب الأداء
    String themeColor = 'blue';
    if (data.occupancyRate >= 80) {
      themeColor = 'green';
    } else if (data.occupancyRate >= 50) {
      themeColor = 'blue';
    }
    else if (data.occupancyRate >= 30) {
      themeColor = 'orange';
    }
    else {
      themeColor = 'red';
    }

    final occupancyEmoji = data.occupancyRate >= 80
        ? '🟢'
        : data.occupancyRate >= 50
            ? '🔵'
            : data.occupancyRate >= 30
                ? '🟠'
                : '🔴';

    final elements = <Map<String, dynamic>>[];

    // التاريخ
    elements.add({
      'tag': 'div',
      'fields': [
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '**📅 التاريخ**\n${data.reportDate}',
          },
        },
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '**$occupancyEmoji الإشغال**\n${data.occupancyRate.toStringAsFixed(1)}%',
          },
        },
      ],
    });

    elements.add({'tag': 'hr'});

    // الغرف
    elements.add({
      'tag': 'div',
      'fields': [
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '🏨 **الغرف**',
          },
        },
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '${data.occupiedRooms}/${data.totalRooms} مشغولة',
          },
        },
      ],
    });

    elements.add({
      'tag': 'div',
      'fields': [
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '🟢 متاحة: ${data.availableRooms}',
          },
        },
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '🧹 تنظيف: ${data.cleaningRooms}',
          },
        },
      ],
    });

    elements.add({
      'tag': 'div',
      'fields': [
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '🔧 صيانة: ${data.maintenanceRooms}',
          },
        },
      ],
    });

    elements.add({'tag': 'hr'});

    // الحجوزات
    elements.add({
      'tag': 'div',
      'fields': [
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '📋 **حجوزات جديدة**\n${data.newBookingsToday}',
          },
        },
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '🔑 **تسجيلات دخول**\n${data.checkInsToday}',
          },
        },
      ],
    });

    elements.add({
      'tag': 'div',
      'fields': [
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '🚪 **تسجيلات خروج**\n${data.checkOutsToday}',
          },
        },
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '📋 **حجوزات نشطة**\n${data.activeBookings}',
          },
        },
      ],
    });

    if (data.overstayBookings > 0) {
      elements.add({
        'tag': 'div',
        'text': {
          'tag': 'lark_md',
          'content': '⚠️ **تنبيه:** ${data.overstayBookings} تأخير مغادرة!',
        },
      });
    }

    elements.add({'tag': 'hr'});

    // المالية
    elements.add({
      'tag': 'div',
      'fields': [
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '💰 **الإيرادات**\n\$${data.totalIncome.toStringAsFixed(2)}',
          },
        },
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '💸 **المصروفات**\n\$${data.totalExpenses.toStringAsFixed(2)}',
          },
        },
      ],
    });

    elements.add({
      'tag': 'div',
      'fields': [
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '📈 **صافي الربح**\n\$${data.netRevenue.toStringAsFixed(2)}',
          },
        },
        {
          'is_short': true,
          'text': {
            'tag': 'lark_md',
            'content': '💳 **ديون معلقة**\n${data.unsettledDebts}',
          },
        },
      ],
    });

    elements.add({'tag': 'hr'});

    // تذييل
    elements.add({
      'tag': 'note',
      'elements': [
        {
          'tag': 'plain_text',
          'content': '📊 تقرير تلقائي - Marina Hotel App',
        },
      ],
    });

    return {
      'msg_type': 'interactive',
      'card': {
        'header': {
          'title': {
            'tag': 'plain_text',
            'content': '📊 التقرير اليومي - مارينا هوتل',
          },
          'template': themeColor,
        },
        'elements': elements,
      },
    };
  }

  /// إرسال التقرير اليومي عبر Webhook
  Future<bool> sendDailyReport({DailyReportData? reportData}) async {
    try {
      if (!await LarkConfig.isEnabled()) {
        debugPrint('⚠️ Lark Report: Lark غير مفعّل');
        return false;
      }
      if (!await LarkConfig.isDailyReportEnabled()) {
        debugPrint('⚠️ Lark Report: التقارير اليومية غير مفعّلة');
        return false;
      }

      // التحقق من عدم إرسال تقرير مكرر لنفس اليوم
      final today = HotelTimeEngine.getHotelDayKey();
      final lastSent = await LarkConfig.getLastReportSent();
      if (lastSent == today) {
        debugPrint('ℹ️ Lark Report: تم إرسال تقرير اليوم بالفعل');
        return false;
      }

      final webhookUrl = await LarkConfig.getWebhookUrl();
      if (webhookUrl.isEmpty) {
        debugPrint('⚠️ Lark Report: Webhook URL غير مضبوط');
        return false;
      }

      // تجميع البيانات أو استخدام البيانات الممرّرة
      final data = reportData ?? await collectReportData();

      // بناء وإرسال البطاقة
      final card = _buildReportCard(data);
      final success = await _api.sendWebhookMessage(
        webhookUrl: webhookUrl,
        message: card,
      );

      if (success) {
        // تسجيل آخر تقرير تم إرساله
        await LarkConfig.setLastReportSent(today);
        debugPrint('✅ Lark Report: تم إرسال التقرير اليومي بنجاح (يوم فندقي: $today)');

        // محاولة إرسال نسخة عبر Bot API أيضاً إذا كان معرّف المحادثة مضبوطاً
        final chatId = await LarkConfig.getDailyReportChatId();
        if (chatId.isNotEmpty) {
          try {
            await _api.sendBotMessage(
              chatId: chatId,
              msgType: 'interactive',
              content: card['card'] as Map<String, dynamic>? ?? {},
            );
            debugPrint('✅ Lark Report: تم إرسال نسخة للمجموعة $chatId');
          } catch (e) {
            debugPrint('⚠️ Lark Report: فشل إرسال نسخة المجموعة: $e');
          }
        }
      }

      return success;
    } catch (e) {
      debugPrint('❌ Lark Report: خطأ في إرسال التقرير اليومي: $e');
      return false;
    }
  }

  /// إرسال تقرير فوري (يدوي) تجاوزاً لفحص التكرار
  Future<bool> sendReportNow({DailyReportData? reportData}) async {
    try {
      final webhookUrl = await LarkConfig.getWebhookUrl();
      if (webhookUrl.isEmpty) {
        return false;
      }

      final data = reportData ?? await collectReportData();
      final card = _buildReportCard(data);

      return await _api.sendWebhookMessage(
        webhookUrl: webhookUrl,
        message: card,
      );
    } catch (e) {
      debugPrint('❌ Lark Report: خطأ في إرسال التقرير: $e');
      return false;
    }
  }

  /// الحصول على نص التقرير بتنسيق نص عادي (للمعاينة)
  Future<String> getReportPreviewText() async {
    try {
      final data = await collectReportData();
      return _buildReportMarkdown(data);
    } catch (e) {
      return 'خطأ في تجميع البيانات: $e';
    }
  }

  /// الحصول على بيانات التقرير (للمعاينة في الواجهة)
  Future<DailyReportData> getReportData() async {
    return collectReportData();
  }
}
