import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_db.dart';
import '../services/telegram/telegram_config.dart';
import '../services/telegram/telegram_report_service.dart';
import '../services/telegram/telegram_service.dart' as tg;
import '../utils/hotel_time_engine.dart';

/// ✅ خدمة إقفال اليوم (Night Audit) — تجمع البيانات المالية لليوم الفندقي،
/// تكتبها في HotelDayLedger، وترسلها عبر WhatsApp و Telegram Bot.
///
/// ## الفرق بين هذا و TelegramReportService
///
/// `TelegramReportService` يجمع البيانات ويرسلها عبر WhatsApp فقط (CallMeBot).
/// `NightAuditService` يفعل ذلك + يكتب في HotelDayLedger + يرسل عبر Telegram Bot
/// أيضاً + يمكن تشغيله يدوياً من لوحة التحكم.
class NightAuditService {
  NightAuditService._();
  static final NightAuditService instance = NightAuditService._();

  final TelegramReportService _whatsappReport = TelegramReportService.instance;

  /// إقفال اليوم الفندقي الحالي + إرسال التقرير عبر WhatsApp و Telegram.
  ///
  /// - إن كان اليوم مُقفلاً مسبقاً في HotelDayLedger → يُرجع false مع رسالة.
  /// - يجمع كل البيانات المالية (إيرادات، مصروفات، حجوزات، غرف).
  /// - يكتب سجل في HotelDayLedger بـ status='closed'.
  /// - يرسل التقرير عبر WhatsApp (CallMeBot) إن كان مُفعّلاً.
  /// - يرسل التقرير عبر Telegram Bot إن كان مُفعّلاً ومُعدّاً.
  ///
  /// [force] — إذا true، يُعيد الإرسال حتى لو اليوم مُقفل مسبقاً.
  Future<NightAuditResult> closeDay({bool force = false}) async {
    try {
      final db = DatabaseManager.instance;
      final hotelDayKey = HotelTimeEngine.getHotelDayKey();

      // 1) تحقق إن كان اليوم مُقفلاً مسبقاً
      if (!force) {
        final existing =
            await (db.select(db.hotelDayLedger)
                  ..where((t) => t.hotelDayKey.equals(hotelDayKey))
                  ..limit(1))
                .getSingleOrNull();
        if (existing != null && existing.status == 'closed') {
          debugPrint('⚠️ [NightAudit] اليوم $hotelDayKey مُقفل مسبقاً');
          return NightAuditResult(
            success: false,
            message:
                'اليوم $hotelDayKey مُقفل مسبقاً. استخدم "إعادة الإرسال" للإرسال مجدداً.',
            hotelDayKey: hotelDayKey,
            alreadyClosed: true,
          );
        }
      }

      // 2) اجمع البيانات المالية
      final data = await _gatherNightAuditData(hotelDayKey);
      if (data == null) {
        return NightAuditResult(
          success: false,
          message: 'فشل في تجميع بيانات اليوم',
          hotelDayKey: hotelDayKey,
        );
      }

      // 3) اكتب/حدّث سجل HotelDayLedger
      await _writeLedgerEntry(db, hotelDayKey, data);

      // 4) ابنِ رسالة التقرير
      final message = _buildReportMessage(data);

      // 5) أرسل عبر WhatsApp (CallMeBot)
      bool whatsappSent = false;
      bool whatsappSkipped = false;
      try {
        final waEnabled = await TelegramConfig.isEnabled();
        final waReportEnabled = await TelegramConfig.isDailyReportEnabled();
        if (waEnabled && waReportEnabled) {
          whatsappSent = await _whatsappReport.sendReportNow();
          debugPrint(
            '📱 [NightAudit] WhatsApp: ${whatsappSent ? "sent ✅" : "failed ❌"}',
          );
        } else {
          whatsappSkipped = true;
          debugPrint('📱 [NightAudit] WhatsApp: skipped (disabled)');
        }
      } catch (e) {
        debugPrint('❌ [NightAudit] WhatsApp error: $e');
      }

      // 6) أرسل عبر Telegram Bot
      bool telegramSent = false;
      bool telegramSkipped = false;
      try {
        final tgConfigured = await TelegramConfig.isConfigured();
        final tgEnabled = await TelegramConfig.isEnabled();
        final tgReportEnabled = await TelegramConfig.isDailyReportEnabled();
        if (tgConfigured && tgEnabled && tgReportEnabled) {
          final tgService = tg.TelegramApiClient.instance;
          telegramSent = await tgService.sendToDefaultChat(text: message);
          debugPrint(
            '✈️ [NightAudit] Telegram: ${telegramSent ? "sent ✅" : "failed ❌"}',
          );
        } else {
          telegramSkipped = true;
          debugPrint(
            '✈️ [NightAudit] Telegram: skipped (not configured or disabled)',
          );
        }
      } catch (e) {
        debugPrint('❌ [NightAudit] Telegram error: $e');
      }

      // 7) حدّث lastReportSent لمنع الإرسال المتكرر التلقائي
      await TelegramConfig.setLastReportSent(hotelDayKey);

      // 8) النتيجة
      final anySent = whatsappSent || telegramSent;
      final allSkipped = whatsappSkipped && telegramSkipped;

      String resultMessage;
      if (anySent) {
        final channels = <String>[];
        if (whatsappSent) channels.add('WhatsApp');
        if (telegramSent) channels.add('Telegram');
        resultMessage =
            '✅ تم إقفال اليوم $hotelDayKey وإرسال التقرير عبر ${channels.join(' + ')}';
      } else if (allSkipped) {
        resultMessage =
            '✅ تم إقفال اليوم $hotelDayKey (التقرير معطّل — لم يُرسل)';
      } else {
        resultMessage =
            '⚠️ تم إقفال اليوم $hotelDayKey لكن فشل الإرسال عبر كل القنوات';
      }

      return NightAuditResult(
        success: true,
        message: resultMessage,
        hotelDayKey: hotelDayKey,
        whatsappSent: whatsappSent,
        telegramSent: telegramSent,
        whatsappSkipped: whatsappSkipped,
        telegramSkipped: telegramSkipped,
        data: data,
      );
    } catch (e) {
      debugPrint('❌ [NightAudit] error: $e');
      return NightAuditResult(
        success: false,
        message: 'خطأ في إقفال اليوم: $e',
        hotelDayKey: HotelTimeEngine.getHotelDayKey(),
      );
    }
  }

  /// تحقق هل اليوم الحالي مُقفل مسبقاً
  Future<bool> isDayClosed(String? hotelDayKey) async {
    final key = hotelDayKey ?? HotelTimeEngine.getHotelDayKey();
    final db = DatabaseManager.instance;
    final entry =
        await (db.select(db.hotelDayLedger)
              ..where((t) => t.hotelDayKey.equals(key))
              ..limit(1))
            .getSingleOrNull();
    return entry != null && entry.status == 'closed';
  }

  /// جمع كل البيانات المالية لليوم الفندقي
  Future<NightAuditData?> _gatherNightAuditData(String hotelDayKey) async {
    try {
      final db = DatabaseManager.instance;

      // ── حالة الغرف ──
      final rooms = await db.select(db.rooms).get();
      final totalRooms = rooms.length;
      int occupied = 0, available = 0, cleaning = 0, maintenance = 0;

      for (final room in rooms) {
        if (room.deletedAt != null) continue;
        final s = room.status.toLowerCase();
        if (s == 'محجوزة' || s == 'مشغولة') {
          occupied++;
        } else if (s == 'شاغرة' || s == 'متاحة') {
          available++;
        } else if (s == 'تنظيف') {
          cleaning++;
        } else if (s == 'صيانة') {
          maintenance++;
        }
      }
      final occupancyRate = totalRooms > 0
          ? (occupied / totalRooms * 100)
          : 0.0;

      // ── حجوزات اليوم ──
      final bookings = await db.select(db.bookings).get();
      int newBookings = 0, checkIns = 0, checkOuts = 0, activeBookings = 0;

      for (final b in bookings) {
        if (b.deletedAt != null) continue;
        final s = b.status.toLowerCase();
        if (s == 'نشط' || s == 'محجوزة') activeBookings++;
        if (b.checkinDate == hotelDayKey ||
            (b.createdAtIso?.substring(0, 10) == hotelDayKey)) {
          newBookings++;
        }
        if (b.hotelDayCheckin == hotelDayKey) checkIns++;
        if (b.hotelDayCheckout == hotelDayKey ||
            (b.actualCheckout?.substring(0, 10) == hotelDayKey)) {
          checkOuts++;
        }
      }

      // ── الإيرادات (مدفوعات اليوم) ──
      final payments = await db.select(db.payments).get();
      double totalIncome = 0;
      int paymentsCount = 0;
      for (final p in payments) {
        if (p.deletedAt != null) continue;
        if (p.hotelDayKey == hotelDayKey && !p.isVoided) {
          totalIncome += p.amount;
          paymentsCount++;
        }
      }

      // ── المصروفات ──
      final expenses = await db.select(db.expenses).get();
      double totalExpenses = 0;
      int expensesCount = 0;
      for (final e in expenses) {
        if (e.deletedAt != null) continue;
        if (e.hotelDayKey == hotelDayKey) {
          totalExpenses += e.amount;
          expensesCount++;
        }
      }

      // ── الديون ──
      final debts = await db.select(db.debts).get();
      double pendingBalances = 0;
      int debtsCount = 0;
      for (final d in debts) {
        if (d.deletedAt != null) continue;
        if (d.isSettled == 0) {
          pendingBalances += d.remainingAmount;
          debtsCount++;
        }
      }

      // ── التنبيهات ──
      final alerts = <String>[];
      for (final b in bookings) {
        if (b.deletedAt != null) continue;
        final s = b.status.toLowerCase();
        if (s == 'نشط' || s == 'محجوزة') {
          if (b.checkoutDate != null &&
              b.actualCheckout == null &&
              b.checkoutDate!.compareTo(hotelDayKey) < 0) {
            alerts.add(
              '⏰ تأخير مغادرة — غرفة ${b.roomNumber} (${b.guestName})',
            );
          }
        }
      }
      if (debtsCount > 0) {
        alerts.add('💳 $debtsCount ديون غير مسددة');
      }
      if (maintenance > 0) {
        alerts.add('🔧 $maintenance غرف تحت الصيانة');
      }

      return NightAuditData(
        hotelDayKey: hotelDayKey,
        totalRooms: totalRooms,
        occupiedRooms: occupied,
        availableRooms: available,
        cleaningRooms: cleaning,
        maintenanceRooms: maintenance,
        occupancyRate: occupancyRate,
        newBookingsToday: newBookings,
        checkInsToday: checkIns,
        checkOutsToday: checkOuts,
        activeBookings: activeBookings,
        totalIncome: totalIncome,
        totalExpenses: totalExpenses,
        netProfit: totalIncome - totalExpenses,
        pendingBalances: pendingBalances,
        paymentsProcessed: paymentsCount,
        expensesProcessed: expensesCount,
        debtsProcessed: debtsCount,
        alerts: alerts,
      );
    } catch (e) {
      debugPrint('❌ [NightAudit] gather error: $e');
      return null;
    }
  }

  /// كتابة/تحديث سجل HotelDayLedger
  Future<void> _writeLedgerEntry(
    AppDatabase db,
    String hotelDayKey,
    NightAuditData data,
  ) async {
    final existing =
        await (db.select(db.hotelDayLedger)
              ..where((t) => t.hotelDayKey.equals(hotelDayKey))
              ..limit(1))
            .getSingleOrNull();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final companion = HotelDayLedgerCompanion(
      hotelDayKey: d.Value(hotelDayKey),
      totalIncome: d.Value(data.totalIncome),
      totalExpenses: d.Value(data.totalExpenses),
      pendingBalances: d.Value(data.pendingBalances),
      occupancyRate: d.Value(data.occupancyRate),
      bookingsProcessed: d.Value(data.activeBookings),
      paymentsProcessed: d.Value(data.paymentsProcessed),
      debtsProcessed: d.Value(data.debtsProcessed),
      expensesProcessed: d.Value(data.expensesProcessed),
      status: const d.Value('closed'),
      updatedAt: d.Value(now),
      lastModified: d.Value(now),
    );

    if (existing != null) {
      await (db.update(
        db.hotelDayLedger,
      )..where((t) => t.id.equals(existing.id))).write(companion);
      debugPrint('📝 [NightAudit] Ledger updated for $hotelDayKey (local only)');
    } else {
      final uuid = _generateUuid();
      await db
          .into(db.hotelDayLedger)
          .insert(
            companion.copyWith(
              createdAt: d.Value(now),
              localUuid: d.Value(uuid),
              origin: const d.Value('local'),
              version: const d.Value(1),
            ),
          );
      debugPrint('📝 [NightAudit] Ledger created for $hotelDayKey (local only)');
    }
    // ⚠️ hotel_day_ledger is a LOCAL-ONLY table — not synced to D1.
    // It's computed from other tables (payments, expenses, bookings)
    // which are already synced individually via their own outbox entries.
  }

  String _generateUuid() {
    return '${DateTime.now().millisecondsSinceEpoch}-$hotelDayKeyHash';
  }

  static String get hotelDayKeyHash =>
      HotelTimeEngine.getHotelDayKey().replaceAll('-', '');

  /// بناء رسالة التقرير — نص عادي متوافق مع WhatsApp و Telegram
  String _buildReportMessage(NightAuditData d) {
    final b = StringBuffer();

    b.writeln('🏨 *إقفال اليوم — Marina Hotel*');
    b.writeln('📅 ${d.hotelDayKey}');
    b.writeln('━━━━━━━━━━━━━━━━━');

    // حالة الغرف
    b.writeln();
    b.writeln('🏨 *حالة الغرف*');
    b.writeln('┌ الإجمالي: ${d.totalRooms}');
    b.writeln('├ 🔴 مشغولة: ${d.occupiedRooms}');
    b.writeln('├ 🟢 متاحة: ${d.availableRooms}');
    b.writeln('├ 🟡 تنظيف: ${d.cleaningRooms}');
    b.writeln('└ 🔧 صيانة: ${d.maintenanceRooms}');
    b.writeln('📈 الإشغال: ${d.occupancyRate.toStringAsFixed(1)}%');

    // الحجوزات
    b.writeln();
    b.writeln('📋 *الحجوزات*');
    b.writeln('┌ جديدة: ${d.newBookingsToday}');
    b.writeln('├ دخول: ${d.checkInsToday}');
    b.writeln('├ خروج: ${d.checkOutsToday}');
    b.writeln('└ نشطة: ${d.activeBookings}');

    // الملخص المالي
    b.writeln();
    b.writeln('💰 *الملخص المالي*');
    b.writeln('┌ الإيرادات: ${d.totalIncome.toStringAsFixed(0)}');
    b.writeln('├ المصروفات: ${d.totalExpenses.toStringAsFixed(0)}');
    b.writeln('├ الصافي: ${d.netProfit.toStringAsFixed(0)}');
    b.writeln('└ الديون المعلقة: ${d.pendingBalances.toStringAsFixed(0)}');

    // المعاملات
    b.writeln();
    b.writeln('📊 *المعاملات*');
    b.writeln('┌ مدفوعات: ${d.paymentsProcessed}');
    b.writeln('├ مصروفات: ${d.expensesProcessed}');
    b.writeln('└ ديون: ${d.debtsProcessed}');

    // التنبيهات
    if (d.alerts.isNotEmpty) {
      b.writeln();
      b.writeln('⚠️ *تنبيهات*');
      for (final a in d.alerts) {
        b.writeln('• $a');
      }
    }

    b.writeln();
    b.writeln('━━━━━━━━━━━━━━━━━');
    b.writeln('✅ تم إقفال اليوم');
    b.writeln('Marina Hotel 🏨');

    return b.toString().trimRight();
  }
}

/// بيانات إقفال اليوم
class NightAuditData {
  const NightAuditData({
    required this.hotelDayKey,
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
    required this.totalIncome,
    required this.totalExpenses,
    required this.netProfit,
    required this.pendingBalances,
    required this.paymentsProcessed,
    required this.expensesProcessed,
    required this.debtsProcessed,
    required this.alerts,
  });

  final String hotelDayKey;
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
  final double totalIncome;
  final double totalExpenses;
  final double netProfit;
  final double pendingBalances;
  final int paymentsProcessed;
  final int expensesProcessed;
  final int debtsProcessed;
  final List<String> alerts;
}

/// نتيجة إقفال اليوم
class NightAuditResult {
  const NightAuditResult({
    required this.success,
    required this.message,
    required this.hotelDayKey,
    this.alreadyClosed = false,
    this.whatsappSent = false,
    this.telegramSent = false,
    this.whatsappSkipped = false,
    this.telegramSkipped = false,
    this.data,
  });

  final bool success;
  final String message;
  final String hotelDayKey;
  final bool alreadyClosed;
  final bool whatsappSent;
  final bool telegramSent;
  final bool whatsappSkipped;
  final bool telegramSkipped;
  final NightAuditData? data;
}

/// Provider لـ NightAuditService
final nightAuditServiceProvider = Provider<NightAuditService>((ref) {
  return NightAuditService.instance;
});

/// Provider لحالة "هل اليوم مُقفل؟"
final isDayClosedProvider = FutureProvider.family<bool, String?>((
  ref,
  hotelDayKey,
) async {
  return NightAuditService.instance.isDayClosed(hotelDayKey);
});
