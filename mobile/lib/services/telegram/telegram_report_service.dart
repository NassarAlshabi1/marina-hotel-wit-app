import 'package:drift/drift.dart' as d;

import '../../utils/hotel_time_engine.dart';
import '../local_db.dart';
import 'telegram_config.dart';
import 'telegram_service.dart';
import 'package:marina_hotel_mobile/utils/currency_formatter.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// بيانات التقرير اليومي المرسلة إلى Telegram.
class TelegramDailyReportData {
  const TelegramDailyReportData({
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
    required this.todayRevenue,
    required this.todayExpenses,
    required this.netProfit,
    required this.unsettledDebts,
    required this.alerts,
  });

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
  final double todayRevenue;
  final double todayExpenses;
  final double netProfit;
  final int unsettledDebts;
  final List<String> alerts;
}

/// التقرير اليومي عبر Telegram.
///
/// جميع الملخصات المالية تُفلتر بـ [hotelDayKey] المخزن، وهو مصدر الحقيقة
/// المحاسبي. لا يستخدم التاريخ التقويمي أو تحميل جداول كاملة إلى الذاكرة.
class TelegramReportService {
  TelegramReportService._();

  static TelegramReportService? _instance;
  static TelegramReportService get instance =>
      _instance ??= TelegramReportService._();

  final TelegramApiClient _api = TelegramApiClient.instance;

  /// لا تملك الخدمة موارد مستقلة؛ عميل Telegram مشترك مع الإشعارات الفورية.
  void dispose() {}

  static void disposeInstance() {
    _instance = null;
  }

  /// يرسل تقريراً واحداً فقط لكل يوم فندقي بعد نجاح التسليم.
  Future<bool> sendDailyReport() async {
    try {
      if (!await TelegramConfig.isEnabled() ||
          !await TelegramConfig.isDailyReportEnabled()) {
        return false;
      }

      final hotelDayKey = HotelTimeEngine.getHotelDayKey();
      if (await TelegramConfig.getLastReportSent() == hotelDayKey) {
        dlog('⏭️ Telegram: تم إرسال تقرير اليوم الفندقي بالفعل');
        return true;
      }

      final data = await _gatherReportData();
      if (data == null) return false;

      final success = await _api.sendToDefaultChat(
        text: _buildReportMessage(data),
      );
      if (success) {
        await TelegramConfig.setLastReportSent(hotelDayKey);
        dlog('✅ Telegram: تم إرسال التقرير اليومي بنجاح');
      }
      return success;
    } catch (e) {
      dlog(() => '❌ Telegram: خطأ في التقرير اليومي: $e');
      return false;
    }
  }

  /// إرسال تجريبي لا يغيّر علامة التقرير اليومي، كي لا يمنع إرسال المجدول.
  Future<bool> sendReportNow() async {
    try {
      if (!await TelegramConfig.isEnabled()) return false;
      final data = await _gatherReportData();
      if (data == null) return false;
      return _api.sendToDefaultChat(text: _buildReportMessage(data));
    } catch (e) {
      dlog(() => '❌ Telegram: خطأ في إرسال التقرير التجريبي: $e');
      return false;
    }
  }

  Future<TelegramDailyReportData?> _gatherReportData() async {
    try {
      final db = DatabaseManager.instance;
      final now = DateTime.now();
      final hotelDayKey = HotelTimeEngine.getHotelDayKey(dateTime: now);
      final range = HotelTimeEngine.getHotelDayRange(now);
      final startEpoch = range['start']!.millisecondsSinceEpoch ~/ 1000;
      final endExclusiveEpoch =
          range['end']!
              .add(const Duration(milliseconds: 1))
              .millisecondsSinceEpoch ~/
          1000;

      // تجميعات SQL: صف واحد فقط بدلاً من فك جميع الكيانات في Dart.
      final summary = await db
          .customSelect(
            '''
SELECT
  (SELECT COUNT(*) FROM rooms WHERE deleted_at IS NULL) AS total_rooms,
  (SELECT COUNT(*) FROM rooms WHERE deleted_at IS NULL
      AND status IN ('محجوزة', 'مشغولة')) AS occupied_rooms,
  (SELECT COUNT(*) FROM rooms WHERE deleted_at IS NULL
      AND status IN ('شاغرة', 'متاحة')) AS available_rooms,
  (SELECT COUNT(*) FROM rooms WHERE deleted_at IS NULL
      AND status = 'تنظيف') AS cleaning_rooms,
  (SELECT COUNT(*) FROM rooms WHERE deleted_at IS NULL
      AND status = 'صيانة') AS maintenance_rooms,
  (SELECT COUNT(*) FROM bookings WHERE deleted_at IS NULL
      AND (hotel_day_checkin = ?
        OR (hotel_day_checkin IS NULL AND created_at >= ? AND created_at < ?)))
      AS new_bookings,
  (SELECT COUNT(*) FROM bookings WHERE deleted_at IS NULL
      AND hotel_day_checkin = ?) AS check_ins,
  (SELECT COUNT(*) FROM bookings WHERE deleted_at IS NULL
      AND hotel_day_checkout = ?) AS check_outs,
  (SELECT COUNT(*) FROM bookings WHERE deleted_at IS NULL
      AND status IN ('نشط', 'محجوزة')) AS active_bookings,
  (SELECT COALESCE(SUM(amount), 0.0) FROM payments
      WHERE deleted_at IS NULL AND is_voided = 0 AND hotel_day_key = ?)
      AS revenue,
  (SELECT COALESCE(SUM(amount), 0.0) FROM expenses
      WHERE deleted_at IS NULL AND hotel_day_key = ?) AS expenses,
  (SELECT COUNT(*) FROM debts WHERE deleted_at IS NULL AND is_settled = 0)
      AS unsettled_debts
''',
            variables: [
              d.Variable.withString(hotelDayKey),
              d.Variable.withInt(startEpoch),
              d.Variable.withInt(endExclusiveEpoch),
              d.Variable.withString(hotelDayKey),
              d.Variable.withString(hotelDayKey),
              d.Variable.withString(hotelDayKey),
              d.Variable.withString(hotelDayKey),
            ],
          )
          .getSingle();
      final values = summary.data;
      int count(String name) => (values[name] as num? ?? 0).toInt();
      double amount(String name) => (values[name] as num? ?? 0).toDouble();

      final totalRooms = count('total_rooms');
      final occupiedRooms = count('occupied_rooms');
      final maintenanceRooms = count('maintenance_rooms');
      final revenue = amount('revenue');
      final expenses = amount('expenses');

      final overdueBookings =
          await (db.select(db.bookings)
                ..where(
                  (b) =>
                      b.deletedAt.isNull() &
                      b.actualCheckout.isNull() &
                      b.hotelDayCheckout.isNotNull() &
                      b.hotelDayCheckout.isSmallerThanValue(hotelDayKey) &
                      b.status.isIn(const ['نشط', 'محجوزة']),
                )
                ..limit(20))
              .get();

      final alerts = <String>[
        for (final booking in overdueBookings)
          '⏰ تأخير مغادرة — غرفة ${_escapeHtml(booking.roomNumber)} '
              '(${_escapeHtml(booking.guestName)})',
        if (count('unsettled_debts') > 0)
          '💳 لديك ${count('unsettled_debts')} ديون غير مسددة',
        if (maintenanceRooms > 0) '🔧 $maintenanceRooms غرف تحت الصيانة',
      ];

      return TelegramDailyReportData(
        reportDate: hotelDayKey,
        totalRooms: totalRooms,
        occupiedRooms: occupiedRooms,
        availableRooms: count('available_rooms'),
        cleaningRooms: count('cleaning_rooms'),
        maintenanceRooms: maintenanceRooms,
        occupancyRate: totalRooms == 0 ? 0 : occupiedRooms / totalRooms * 100,
        newBookingsToday: count('new_bookings'),
        checkInsToday: count('check_ins'),
        checkOutsToday: count('check_outs'),
        activeBookings: count('active_bookings'),
        todayRevenue: revenue,
        todayExpenses: expenses,
        netProfit: revenue - expenses,
        unsettledDebts: count('unsettled_debts'),
        alerts: alerts,
      );
    } catch (e) {
      dlog(() => '❌ Telegram: خطأ في تجميع بيانات التقرير: $e');
      return null;
    }
  }

  String _buildReportMessage(TelegramDailyReportData data) {
    final buffer = StringBuffer()
      ..writeln('📊 <b>التقرير اليومي — Marina Hotel</b>')
      ..writeln('📅 اليوم الفندقي: <b>${data.reportDate}</b>')
      ..writeln('━━━━━━━━━━━━━━━━━')
      ..writeln()
      ..writeln('🏨 <b>حالة الغرف</b>')
      ..writeln('┌ الإجمالي: ${data.totalRooms}')
      ..writeln('├ 🔴 مشغولة: ${data.occupiedRooms}')
      ..writeln('├ 🟢 متاحة: ${data.availableRooms}')
      ..writeln('├ 🟡 تنظيف: ${data.cleaningRooms}')
      ..writeln('└ 🔧 صيانة: ${data.maintenanceRooms}')
      ..writeln('📈 نسبة الإشغال: ${data.occupancyRate.toStringAsFixed(1)}%')
      ..writeln()
      ..writeln('📋 <b>حجوزات اليوم الفندقي</b>')
      ..writeln('┌ جديدة: ${data.newBookingsToday}')
      ..writeln('├ تسجيل دخول: ${data.checkInsToday}')
      ..writeln('├ تسجيل خروج: ${data.checkOutsToday}')
      ..writeln('└ نشطة حالياً: ${data.activeBookings}')
      ..writeln()
      ..writeln('💰 <b>ملخص مالي</b>')
      ..writeln(
        '┌ الإيرادات: \$${CurrencyFormatter.formatAmount(data.todayRevenue)}',
      )
      ..writeln(
        '├ المصروفات: \$${CurrencyFormatter.formatAmount(data.todayExpenses)}',
      )
      ..writeln(
        '└ صافي الربح: \$${CurrencyFormatter.formatAmount(data.netProfit)}',
      )
      ..writeln()
      ..writeln('💳 الديون غير المسددة: ${data.unsettledDebts}');

    if (data.alerts.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('⚠️ <b>تنبيهات</b>');
      for (final alert in data.alerts) {
        buffer.writeln('• $alert');
      }
    }

    buffer
      ..writeln()
      ..writeln('<i>Marina Hotel App 🏨</i>');
    return buffer.toString().trimRight();
  }

  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
