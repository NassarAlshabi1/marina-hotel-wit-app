/// محلل ملف التحصيل — يستخرج من سجل المدفوعات الفعلي:
/// - توزيع وسائل الدفع (نسبة كل وسيلة من المبالغ).
/// - متوسط أيام التأخر بين بداية الإقامة ودخول النقد لكل وسيلة.
/// - الإشغال التاريخي و ADR (آخر 30 يوماً) لتغذية التدفق التقديري.
///
/// المصدر: صفوف drift المحلية المتزامنة حياً من Appwrite — نفس مصدر
/// بيانات باقي شاشات التطبيق.
library;

import '../../services/local_db.dart' as db;
import 'finance_date_utils.dart';
import 'finance_models.dart';

class PaymentProfileAnalyzer {
  const PaymentProfileAnalyzer();

  /// يبني ملف التحصيل من المدفوعات والحجوزات والغرف.
  ///
  /// [payments] يجب أن تكون المدفوعات النشطة فقط (غير الملغاة/المحذوفة).
  /// [lookbackDays] فترة تحليل وسائل الدفع (افتراضي 90 يوماً).
  /// [occupancyDays] فترة حساب الإشغال التاريخي (افتراضي 30 يوماً).
  PaymentProfile analyze({
    required List<db.Payment> payments,
    required List<db.Booking> bookings,
    required int totalRooms,
    int lookbackDays = 90,
    int occupancyDays = 30,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final lookbackStart = dayStart(ref).subtract(Duration(days: lookbackDays));
    final occStart = dayStart(ref).subtract(Duration(days: occupancyDays));

    // ── 1) توزيع وسائل الدفع + أيام التأخر ──────────────────────────
    // مفتاح الوسيلة → (مجموع المبالغ، عدد الدفعات، مجموع أيام التأخر
    // للدفعات المرتبطة بحجز يمكن معرفة دخوله).
    final amountByMethod = <String, double>{};
    final countByMethod = <String, int>{};
    final lagSumByMethod = <String, double>{};
    final lagCountByMethod = <String, int>{};

    // فهرس الحجوزات للتأخر: localId → checkinDate
    final checkinByBookingId = <int, DateTime>{};
    for (final b in bookings) {
      final ci = tryParseDate(b.checkinDate);
      if (ci != null) {
        checkinByBookingId[b.id] = ci;
      }
    }

    for (final p in payments) {
      final pd = tryParseDate(p.paymentDate);
      if (pd == null || pd.isBefore(lookbackStart)) continue;
      final method = p.paymentMethod.trim().isEmpty
          ? 'غير محدد'
          : p.paymentMethod.trim();
      amountByMethod[method] = (amountByMethod[method] ?? 0) + p.amount;
      countByMethod[method] = (countByMethod[method] ?? 0) + 1;

      final bookingId = p.bookingLocalId;
      if (bookingId != null) {
        final ci = checkinByBookingId[bookingId];
        if (ci != null) {
          // دفعات ما قبل الإقامة تعني نقداً وصل مبكراً → تأخر 0.
          final lag = daysBetween(ci, pd);
          lagSumByMethod[method] =
              (lagSumByMethod[method] ?? 0) + (lag < 0 ? 0 : lag);
          lagCountByMethod[method] = (lagCountByMethod[method] ?? 0) + 1;
        }
      }
    }

    var grandTotal = 0.0;
    amountByMethod.forEach((_, v) => grandTotal += v);

    final methods = <PaymentMethodProfile>[];
    if (grandTotal > 0) {
      amountByMethod.forEach((method, amount) {
        final lagCount = lagCountByMethod[method] ?? 0;
        final lagAvg = lagCount > 0
            ? ((lagSumByMethod[method] ?? 0) / lagCount).round()
            : 0;
        methods.add(
          PaymentMethodProfile(
            method: method,
            share: amount / grandTotal,
            // النقد فوري دائماً — باقي الوسائل وفق التأخر المُقاس.
            lagDays: method == 'نقدي' ? 0 : lagAvg,
            sampleCount: countByMethod[method] ?? 0,
          ),
        );
      });
      methods.sort((a, b) => b.share.compareTo(a.share));
    }

    // ── 2) الإشغال التاريخي و ADR ────────────────────────────────────
    var soldNights = 0;
    final days = List.generate(
      occupancyDays,
      (i) => dayStart(ref).subtract(Duration(days: occupancyDays - 1 - i)),
    );
    final activeBookings = bookings
        .where((b) => b.deletedAt == null && !_isCancelled(b.status))
        .toList();
    for (final day in days) {
      for (final b in activeBookings) {
        if (occupiesOnDay(b, day)) soldNights++;
      }
    }
    final availableNights = (totalRooms <= 0 ? 1 : totalRooms) * occupancyDays;
    final occupancy = (soldNights / availableNights).clamp(0.0, 1.0);

    var roomRevenue = 0.0;
    for (final p in payments) {
      final pd = tryParseDate(p.paymentDate);
      if (pd == null || pd.isBefore(occStart)) continue;
      if (p.isVoided) continue;
      if (p.revenueType == 'room') roomRevenue += p.amount;
    }
    final adr = soldNights > 0 ? roomRevenue / soldNights : 0.0;

    if (methods.isEmpty) {
      return PaymentProfile.fallback.copyWith2(
        occupancy: occupancy,
        adr: adr,
        sampleDays: occupancyDays,
      );
    }

    return PaymentProfile(
      methods: methods,
      historicalOccupancy: occupancy,
      historicalAdr: adr,
      sampleDays: occupancyDays,
    );
  }

  // ── مساعدات ───────────────────────────────────────────────────────

  static bool _isCancelled(String status) {
    final s = status.trim().toLowerCase();
    return s == 'ملغي' || s == 'cancelled' || s == 'canceled';
  }

  /// هل يشغل هذا الحجز ليلة اليوم [day]؟ (دخول ≤ اليوم ولم يغادر بعده)
  static bool occupiesOnDay(db.Booking b, DateTime day) {
    final checkin = tryParseDate(b.checkinDate);
    if (checkin == null) return false;
    if (day.isBefore(dayStart(checkin))) return false;

    DateTime? out;
    if (b.actualCheckout != null && b.actualCheckout!.trim().isNotEmpty) {
      out = tryParseDate(b.actualCheckout);
    }
    out ??= tryParseDate(b.checkoutDate);
    out ??= checkin.add(Duration(days: b.calculatedNights));

    // ليلة اليوم تحتسب إذا كان المغادرة بعد اليوم (أو لم يغادر بعد).
    final outDay = dayStart(out);
    return !day.isBefore(dayStart(checkin)) && outDay.isAfter(day);
  }
}

extension on PaymentProfile {
  /// نسخة معدلة تُستخدم عند غياب وسائل دفع كافية مع إبقاء الإشغال المحسوب.
  PaymentProfile copyWith2({
    required double occupancy,
    required double adr,
    required int sampleDays,
  }) {
    return PaymentProfile(
      methods: methods,
      historicalOccupancy: occupancy,
      historicalAdr: adr,
      sampleDays: sampleDays,
    );
  }
}
