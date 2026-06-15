import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';

import '../../utils/hotel_time_engine.dart';
import '../local_db.dart';
import '../remote_config_service.dart';
import 'telegram_config.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

/// بيانات التقرير اليومي
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

/// خدمة التقارير اليومية عبر Telegram
class TelegramReportService {

  factory TelegramReportService.instance() => _instance ??= TelegramReportService._();
  TelegramReportService._();
  static TelegramReportService? _instance;

  // الإرسال عبر CallMeBot WhatsApp
  static const String _callMeBotUrl = 'https://api.callmebot.com/whatsapp.php';
  // بيانات الاتصال من Firebase Remote Config (قابلة للتغيير من Firebase Console)
  // Fallback chain: Remote Config → SharedPreferences → Env
  Future<String> _getPhone() async {
    final rc = RemoteConfigService.instance.whatsappPhone;
    if (rc.isNotEmpty) return rc;
    final prefs = getSharedPrefs();
    return prefs.getString('whatsapp_phone') ?? '';
  }

  Future<String> _getApiKey() async {
    final rc = RemoteConfigService.instance.whatsappApiKey;
    if (rc.isNotEmpty) return rc;
    final prefs = getSharedPrefs();
    return prefs.getString('whatsapp_api_key') ?? '';
  }

  final http.Client _httpClient = http.Client();

  /// تحرير موارد HTTP client
  void dispose() {
    _httpClient.close();
  }

  /// تحرير الموارد الثابتة للـ singleton
  static void disposeInstance() {
    _instance?._httpClient.close();
    _instance = null;
  }

  /// إرسال التقرير اليومي عبر WhatsApp (CallMeBot)
  Future<bool> sendDailyReport() async {
    try {
      if (!await TelegramConfig.isEnabled()) {
        return false;
      }
      if (!await TelegramConfig.isDailyReportEnabled()) {
        return false;
      }

      // منع الإرسال المتكرر
      final hotelDayKey = HotelTimeEngine.getHotelDayKey();
      final lastSent = await TelegramConfig.getLastReportSent();
      if (lastSent == hotelDayKey) {
        AppLogger.info('⏭️ WhatsApp: تم إرسال تقرير اليوم بالفعل', tag: 'APP');
        return true;
      }

      final data = await _gatherReportData();
      if (data == null) {
        return false;
      }

      // إرسال عبر WhatsApp (CallMeBot)
      final message = _buildReportMessage(data);
      final phone = await _getPhone();
      final apiKey = await _getApiKey();
      var success = await _sendViaCallMeBot(message, phone: phone, apiKey: apiKey);

      // Retry مرة واحدة
      if (!success) {
        AppLogger.info('🔄 WhatsApp: إعادة محاولة إرسال التقرير...', tag: 'APP');
        await Future<void>.delayed(const Duration(seconds: 2));
        success = await _sendViaCallMeBot(message, phone: phone, apiKey: apiKey);
      }

      if (success) {
        await TelegramConfig.setLastReportSent(hotelDayKey);
        AppLogger.info('✅ WhatsApp: تم إرسال التقرير اليومي بنجاح', tag: 'APP');
      }

      return success;
    } catch (e) {
      AppLogger.warning('❌ WhatsApp: خطأ في التقرير اليومي: $e', tag: 'APP');
      return false;
    }
  }

  /// إرسال التقرير فوراً (تجريبي) عبر WhatsApp
  Future<bool> sendReportNow() async {
    try {
      if (!await TelegramConfig.isEnabled()) {
        return false;
      }

      final data = await _gatherReportData();
      if (data == null) {
        return false;
      }

      // إرسال عبر WhatsApp (CallMeBot)
      final message = _buildReportMessage(data);
      final phone = await _getPhone();
      final apiKey = await _getApiKey();
      var success = await _sendViaCallMeBot(message, phone: phone, apiKey: apiKey);

      // Retry مرة واحدة
      if (!success) {
        AppLogger.info('🔄 WhatsApp: إعادة محاولة إرسال التقرير...', tag: 'APP');
        await Future<void>.delayed(const Duration(seconds: 2));
        success = await _sendViaCallMeBot(message, phone: phone, apiKey: apiKey);
      }

      if (success) {
        final hotelDayKey = HotelTimeEngine.getHotelDayKey();
        await TelegramConfig.setLastReportSent(hotelDayKey);
      }

      return success;
    } catch (e) {
      AppLogger.warning('❌ WhatsApp: خطأ في إرسال التقرير: $e', tag: 'APP');
      return false;
    }
  }

  /// تجميع بيانات التقرير من قاعدة البيانات
  Future<TelegramDailyReportData?> _gatherReportData() async {
    try {
      final db = DatabaseManager.instance;
      final hotelDayKey = HotelTimeEngine.getHotelDayKey();

      // ── حالة الغرف ──
      final roomsQuery = await db.select(db.rooms).get();
      final totalRooms = roomsQuery.length;
      int occupiedRooms = 0;
      int availableRooms = 0;
      int cleaningRooms = 0;
      int maintenanceRooms = 0;

      for (final room in roomsQuery) {
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

      // ── حجوزات اليوم ──
      final bookingsQuery = await db.select(db.bookings).get();
      int newBookingsToday = 0;
      int checkInsToday = 0;
      int checkOutsToday = 0;
      int activeBookings = 0;

      for (final booking in bookingsQuery) {
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
      }

      // ── ملخص مالي ──
      final paymentsQuery = await db.select(db.payments).get();
      double todayRevenue = 0;
      for (final payment in paymentsQuery) {
        if (payment.hotelDayKey == hotelDayKey && !payment.isVoided) {
          todayRevenue += payment.amount;
        }
      }

      final expensesQuery = await db.select(db.expenses).get();
      double todayExpenses = 0;
      for (final expense in expensesQuery) {
        if (expense.hotelDayKey == hotelDayKey) {
          todayExpenses += expense.amount;
        }
      }

      final netProfit = todayRevenue - todayExpenses;

      // ── الديون غير المسددة ──
      final debtsQuery = await db.select(db.debts).get();
      int unsettledDebts = 0;
      for (final debt in debtsQuery) {
        if (debt.isSettled == 0 && debt.deletedAt == null) {
          unsettledDebts++;
        }
      }

      // ── التنبيهات ──
      final alerts = <String>[];

      // تأخير مغادرة
      for (final booking in bookingsQuery) {
        if (booking.deletedAt != null) {
          continue;
        }
        final status = booking.status.toLowerCase();
        if (status == 'نشط' || status == 'محجوزة') {
          if (booking.checkoutDate != null &&
              booking.actualCheckout == null &&
              booking.checkoutDate!.compareTo(hotelDayKey) < 0) {
            final room = roomsQuery
                .where((r) => r.roomNumber == booking.roomNumber)
                .firstOrNull;
            alerts.add(
                '⏰ تأخير مغادرة — غرفة ${room?.roomNumber ?? '?'} (${booking.guestName})',);
          }
        }
      }

      if (unsettledDebts > 0) {
        alerts.add('💳 لديك $unsettledDebts ديون غير مسددة');
      }

      if (maintenanceRooms > 0) {
        alerts.add('🔧 $maintenanceRooms غرف تحت الصيانة');
      }

      return TelegramDailyReportData(
        reportDate: hotelDayKey,
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
        todayRevenue: todayRevenue,
        todayExpenses: todayExpenses,
        netProfit: netProfit,
        unsettledDebts: unsettledDebts,
        alerts: alerts,
      );
    } catch (e) {
      AppLogger.warning('❌ Telegram: خطأ في تجميع بيانات التقرير: $e', tag: 'APP');
      return null;
    }
  }

  /// إرسال رسالة عبر CallMeBot WhatsApp API
  Future<bool> _sendViaCallMeBot(String message, {required String phone, required String apiKey}) async {
    if (phone.isEmpty || apiKey.isEmpty) {
      AppLogger.error('❌ WhatsApp (CallMeBot): رقم الهاتف أو مفتاح API فارغ', tag: 'APP');
      return false;
    }
    try {
      // قص الرسالة إذا تجاوزت الحد الأقصى (CallMeBot ~1000 حرف)
      final maxLength = RemoteConfigService.instance.whatsappMessageMaxLength;
      final trimmedMessage = message.length > maxLength
          ? '${message.substring(0, maxLength - 3)}...'
          : message;

      final url = Uri.parse(
        '$_callMeBotUrl'
        '?phone=$phone'
        '&text=${Uri.encodeComponent(trimmedMessage)}'
        '&apikey=$apiKey',
      );

      // timeout من Remote Config (افتراضي 15 ثانية)
      final timeout = Duration(
        seconds: RemoteConfigService.instance.whatsappApiTimeout,
      );
      final response = await _httpClient.get(url).timeout(timeout);
      final body = response.body;

      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(body) as Map<String, dynamic>;
          if (json['success'] == true || json['sent'] == true) {
            AppLogger.info('✅ WhatsApp (CallMeBot): تم إرسال التقرير', tag: 'APP');
            return true;
          }
        } catch (_) {
          if (body.toLowerCase().contains('sent') ||
              body.toLowerCase().contains('ok') ||
              body.toLowerCase().contains('success')) {
            return true;
          }
        }
        AppLogger.warning('⚠️ WhatsApp (CallMeBot): فشل الإرسال — $body', tag: 'APP');
        return false;
      }
      AppLogger.warning('⚠️ WhatsApp (CallMeBot): HTTP ${response.statusCode} — $body', tag: 'APP');
      return false;
    } catch (e) {
      AppLogger.warning('❌ WhatsApp (CallMeBot): خطأ — $e', tag: 'APP');
      return false;
    }
  }

  /// بناء رسالة التقرير — نص عادي (WhatsApp لا يدعم HTML)
  String _buildReportMessage(TelegramDailyReportData data) {
    final buffer = StringBuffer();

    // العنوان
    buffer.writeln('📊 التقرير اليومي — Marina Hotel');
    buffer.writeln('📅 ${data.reportDate}');
    buffer.writeln('━━━━━━━━━━━━━━━━━');

    // حالة الغرف
    buffer.writeln();
    buffer.writeln('🏨 حالة الغرف');
    buffer.writeln('┌ الإجمالي: ${data.totalRooms}');
    buffer.writeln('├ 🔴 مشغولة: ${data.occupiedRooms}');
    buffer.writeln('├ 🟢 متاحة: ${data.availableRooms}');
    buffer.writeln('├ 🟡 تنظيف: ${data.cleaningRooms}');
    buffer.writeln('└ 🔧 صيانة: ${data.maintenanceRooms}');
    buffer.writeln(
        '📈 نسبة الإشغال: ${data.occupancyRate.toStringAsFixed(1)}%',);

    // حجوزات اليوم
    buffer.writeln();
    buffer.writeln('📋 حجوزات اليوم');
    buffer.writeln('┌ جديدة: ${data.newBookingsToday}');
    buffer.writeln('├ تسجيل دخول: ${data.checkInsToday}');
    buffer.writeln('├ تسجيل خروج: ${data.checkOutsToday}');
    buffer.writeln('└ نشطة حالياً: ${data.activeBookings}');

    // ملخص مالي
    buffer.writeln();
    buffer.writeln('💰 ملخص مالي');
    buffer.writeln(
        '┌ الإيرادات: \$${data.todayRevenue.toStringAsFixed(2)}',);
    buffer.writeln(
        '├ المصروفات: \$${data.todayExpenses.toStringAsFixed(2)}',);
    buffer.writeln(
        '└ صافي الربح: \$${data.netProfit.toStringAsFixed(2)}',);

    // الديون
    buffer.writeln();
    buffer.writeln('💳 الديون غير المسددة: ${data.unsettledDebts}');

    // التنبيهات
    if (data.alerts.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('⚠️ تنبيهات');
      for (final alert in data.alerts) {
        buffer.writeln('• $alert');
      }
    }

    buffer.writeln();
    buffer.writeln('Marina Hotel App 🏨');

    return buffer.toString().trimRight();
  }
}
