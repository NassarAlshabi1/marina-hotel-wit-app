import 'package:drift/drift.dart' as d;
import 'package:intl/intl.dart';
import '../utils/status_utils.dart';
import '../utils/time.dart';
import 'local_db.dart';
import 'enhanced_booking_calculation_service.dart';

/// نموذج تفصيلي لحسابات المدفوعات والأيام للنزيل الواحد
class GuestPaymentCalculation {
  GuestPaymentCalculation({
    required this.booking,
    required this.payments,
    required this.actualDaysSpent,
    required this.plannedDaysRemaining,
    required this.nightlyRate,
    required this.costSoFar,
    required this.totalPlannedCost,
    required this.totalPaid,
    required this.remainingBalance,
    required this.isOverdue,
    required this.overdueDays,
    required this.overdueCost,
    required this.hasCredit,
    required this.creditDays,
  });
  final Booking booking;
  final List<Payment> payments;
  final int actualDaysSpent;
  final int plannedDaysRemaining;
  final double nightlyRate;
  final double costSoFar;
  final double totalPlannedCost;
  final double totalPaid;
  final double remainingBalance;
  final bool isOverdue;
  final int overdueDays;
  final double overdueCost;
  final bool hasCredit;
  final int creditDays;

  /// هل تم دفع كل التكاليف الحالية؟
  bool get isCurrentlyFullyPaid => totalPaid >= costSoFar;

  /// نسبة الدفع من التكاليف الحالية (0-100)
  double get paymentPercentage =>
      costSoFar > 0 ? (totalPaid / costSoFar * 100).clamp(0.0, 100.0) : 100;

  /// الحالة الوصفية للنزيل
  String get statusDescription {
    if (isOverdue && overdueDays > 0) {
      return 'متأخر عن المغادرة بـ $overdueDays يوم';
    }
    if (hasCredit) {
      return 'له رصيد: ${remainingBalance.abs()} ريال';
    }
    if (remainingBalance > 0) {
      return 'عليه: $remainingBalance ريال';
    }
    return 'مسدد';
  }

  /// ملخص نصي للحساب
  String getSummary() {
    final df = DateFormat('yyyy/MM/dd');
    final checkinDate = DateTime.tryParse(booking.checkinDate);
    final checkoutDate = DateTime.tryParse(booking.checkoutDate ?? '');

    final buffer = StringBuffer();
    buffer.writeln('=== كشف حساب النزيل ===');
    buffer.writeln('النزيل: ${booking.guestName}');
    buffer.writeln('الغرفة: ${booking.roomNumber}');
    buffer.writeln(
      'الدخول: ${checkinDate != null ? df.format(checkinDate) : "---"}',
    );
    buffer.writeln(
      'المغادرة المتوقعة: ${checkoutDate != null ? df.format(checkoutDate) : "---"}',
    );
    buffer.writeln();
    buffer.writeln('--- الأيام والتكاليف ---');
    buffer.writeln('الأيام المقضية: $actualDaysSpent يوم');
    buffer.writeln('الأيام المتبقية: $plannedDaysRemaining يوم');
    buffer.writeln('سعر الليلة: $nightlyRate ريال');
    buffer.writeln('التكلفة حتى الآن: $costSoFar ريال');
    buffer.writeln();
    buffer.writeln('--- المدفوعات ---');
    buffer.writeln('إجمالي المدفوع: $totalPaid ريال');
    buffer.writeln('الرصيد المتبقي: $remainingBalance ريال');
    buffer.writeln('نسبة الدفع: ${paymentPercentage.toStringAsFixed(1)}%');

    if (isOverdue && overdueDays > 0) {
      buffer.writeln();
      buffer.writeln('⚠️ التأخير: $overdueDays يوم');
      buffer.writeln('تكلفة التأخير: $overdueCost ريال');
    }

    return buffer.toString();
  }
}

/// خدمة حساب مدفوعات النزلاء المتقدمة
class GuestPaymentCalculationService {
  GuestPaymentCalculationService(this.db);

  final AppDatabase db;

  /// حساب تفصيلي كامل لمدفوعات نزيل واحد
  Future<GuestPaymentCalculation> calculateForBooking(
    Booking booking, {
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();

    // جلب الغرفة لمعرفة السعر الأساسي
    final room =
        await (db.select(db.rooms)
              ..where((r) => r.roomNumber.equals(booking.roomNumber))
              ..where((r) => r.deletedAt.isNull()))
            .getSingleOrNull();

    final compactUuid = booking.localUuid.replaceAll('-', '');
    final uuidVariants = <String>{
      booking.localUuid,
      if (compactUuid.isNotEmpty) compactUuid,
    }.toList(growable: false);

    // جلب المدفوعات الفعلية للحجز (استبعاد الملغاة والمعلّقة فقط)
    final payments =
        await (db.select(db.payments)
              // ✅ هوية UUID أولاً (بصيغتيه) ولا يُستخدَم bookingLocalId إلا عند غياب UUID
              ..where(
                (p) =>
                    p.bookingUuidCache.isIn(uuidVariants) |
                    (p.bookingLocalId.equals(booking.id) &
                        (p.bookingUuidCache.isNull() |
                            p.bookingUuidCache.equals(''))),
              )
              ..where((p) => p.deletedAt.isNull())
              ..where((p) => p.isVoided.equals(false))
              ..where((p) => p.isPendingBalance.equals(false))
              // الرصيد الفعلي: كل الدفعات المرتبطة بالحجز تُحتسب (deposit/
              // service/other أموال حقيقية) — الفلترة على الحالة لا النوع.
              ..orderBy([(p) => d.OrderingTerm(expression: p.paymentDate)]))
            .get();

    // حساب الأيام المقضية بناءً على قاعدة الساعة 14:00 مع سقف زمن المغادرة الفعلي ومراعاة الحجوزات المغلقة
    final checkin = DateTime.tryParse(booking.checkinDate) ?? moment;
    final actualCheckout =
        booking.actualCheckout != null && booking.actualCheckout!.isNotEmpty
        ? DateTime.tryParse(booking.actualCheckout!)
        : null;
    final plannedCheckout = DateTime.tryParse(booking.checkoutDate ?? '');
    final DateTime effectiveStayEnd;
    if (actualCheckout != null) {
      effectiveStayEnd = actualCheckout.isAfter(moment)
          ? moment
          : actualCheckout;
    } else if (!StatusUtils.isActiveBooking(booking.status)) {
      effectiveStayEnd = plannedCheckout ?? moment;
    } else {
      effectiveStayEnd = moment;
    }

    final actualDaysSpent = Time.nightsWithCutoff(
      checkin,
      checkout: effectiveStayEnd,
    );

    // حساب الأيام المتبقية حتى موعد المغادرة المخطط
    int plannedDaysRemaining = 0;
    if (plannedCheckout != null && !plannedCheckout.isBefore(moment)) {
      plannedDaysRemaining = Time.nightsWithCutoff(
        moment,
        checkout: plannedCheckout,
      );
    }

    // حساب سعر الليلة الواحدة بناءً على السعر المخزن في الغرفة
    final nightlyRate = room?.price ?? 0;

    // استخدم نفس محرك التسعير المعتمد في شاشة المدفوعات والتقارير؛
    // فهو يطبق تعديلات الأسعار والخصومات القديمة والخصم الإجمالي مرة واحدة.
    final enhanced = EnhancedBookingCalculationService(db);
    final financials = await enhanced.calculateFinancials(booking, now: moment);
    final totalPlannedDays = financials.totalNights > 0
        ? financials.totalNights
        : (booking.calculatedNights > 0
              ? booking.calculatedNights
              : actualDaysSpent);
    final totalPlannedCost = financials.totalDue.toDouble();

    // تكلفة الليالي المستهلكة: الأفضلية لسجلات الليالي الفعلية التي تحمل
    // finalRate (وتتضمن الخصومات/الزيادات لكل ليلة). لا نستخدم سعر الغرفة
    // الحالي لإعادة تسعير ليالٍ تاريخية إذا كانت السجلات متوفرة.
    final storedNights =
        await (db.select(db.bookingNights)
              ..where(
                (n) =>
                    n.bookingUuidCache.isIn(uuidVariants) |
                    (n.bookingLocalId.equals(booking.id) &
                        (n.bookingUuidCache.isNull() |
                            n.bookingUuidCache.equals(''))),
              )
              ..where((n) => n.deletedAt.isNull())
              ..orderBy([(n) => d.OrderingTerm.asc(n.hotelDayKey)]))
            .get();

    double costSoFar;
    if (storedNights.length >= actualDaysSpent && actualDaysSpent > 0) {
      final consumedNights = storedNights.take(actualDaysSpent).toList();
      costSoFar = consumedNights.fold<double>(0, (sum, night) {
        final rate = night.finalRate > 0
            ? night.finalRate
            : (night.nightlyRate > 0 ? night.nightlyRate : nightlyRate);
        return sum + rate;
      });
      // الخصم الإجمالي لا يُخزّن على مستوى الليلة؛ نوزعه نسبياً على
      // الفترة المستهلكة حتى لا يظهر في هذا التقرير رصيد أعلى من المحرك.
      if (booking.discountType == 'total' &&
          booking.discount > 0 &&
          totalPlannedDays > 0) {
        final allocatedDiscount =
            booking.discount *
            (actualDaysSpent / totalPlannedDays).clamp(0.0, 1.0);
        costSoFar = (costSoFar - allocatedDiscount).clamp(0.0, costSoFar);
      }
    } else {
      // توافق مع الحجوزات القديمة التي لا تحتوي على سجلات ليالي.
      costSoFar = actualDaysSpent * nightlyRate;
      if (booking.discountType == 'per_night' && booking.discount > 0) {
        costSoFar = (costSoFar - booking.discount * actualDaysSpent).clamp(
          0.0,
          costSoFar,
        );
      } else if (booking.discountType == 'total' &&
          booking.discount > 0 &&
          totalPlannedDays > 0) {
        final allocatedDiscount =
            booking.discount *
            (actualDaysSpent / totalPlannedDays).clamp(0.0, 1.0);
        costSoFar = (costSoFar - allocatedDiscount).clamp(0.0, costSoFar);
      }
    }

    // حساب إجمالي المدفوع
    final totalPaid = payments.fold<double>(0, (sum, p) => sum + p.amount);

    // حساب الرصيد المتبقي (سالب = رصيد للنزيل، موجب = عليه)
    final remainingBalance = costSoFar - totalPaid;

    // حساب التأخير
    final isOverdue =
        plannedCheckout != null &&
        moment.isAfter(plannedCheckout) &&
        actualCheckout == null;
    int overdueDays = 0;
    if (isOverdue) {
      overdueDays = Time.nightsWithCutoff(plannedCheckout, checkout: moment);
    }
    final overdueCost = overdueDays * nightlyRate;

    // حساب الأيام المغطاة بالرصيد (إذا كان هناك رصيد)
    final hasCredit = remainingBalance < 0;
    int creditDays = 0;
    if (hasCredit) {
      final credit = -remainingBalance;
      // ✅ حماية من القسمة على صفر
      creditDays = nightlyRate > 0 ? (credit / nightlyRate).floor() : 0;
    }

    return GuestPaymentCalculation(
      booking: booking,
      payments: payments,
      actualDaysSpent: actualDaysSpent,
      plannedDaysRemaining: plannedDaysRemaining,
      nightlyRate: nightlyRate,
      costSoFar: costSoFar,
      totalPlannedCost: totalPlannedCost,
      totalPaid: totalPaid,
      remainingBalance: remainingBalance,
      isOverdue: isOverdue,
      overdueDays: overdueDays,
      overdueCost: overdueCost,
      hasCredit: hasCredit,
      creditDays: creditDays,
    );
  }

  /// حساب تفصيلي لمجموعة من الحجوزات
  Future<List<GuestPaymentCalculation>> calculateForMultipleBookings(
    List<Booking> bookings, {
    DateTime? now,
  }) async {
    final results = <GuestPaymentCalculation>[];
    for (final booking in bookings) {
      final calc = await calculateForBooking(booking, now: now);
      results.add(calc);
    }
    return results;
  }

  /// إنشاء تقرير ملخص لمجموعة من الحجوزات
  Future<PaymentsSummaryReport> generateSummaryReport(
    List<Booking> bookings, {
    DateTime? now,
  }) async {
    final calculations = await calculateForMultipleBookings(bookings, now: now);

    final totalGuests = calculations.length;
    final totalPaid = calculations.fold<double>(
      0,
      (sum, c) => sum + c.totalPaid,
    );
    final totalRemaining = calculations.fold<double>(
      0,
      (sum, c) => sum + (c.remainingBalance > 0 ? c.remainingBalance : 0),
    );
    final totalCredit = calculations.fold<double>(
      0,
      (sum, c) => sum + (c.remainingBalance < 0 ? -c.remainingBalance : 0),
    );
    final overdueCount = calculations.where((c) => c.isOverdue).length;
    final fullyPaidCount = calculations
        .where((c) => c.remainingBalance <= 0 && !c.hasCredit)
        .length;

    return PaymentsSummaryReport(
      generatedAt: now ?? DateTime.now(),
      totalGuests: totalGuests,
      totalPaid: totalPaid,
      totalRemaining: totalRemaining,
      totalCredit: totalCredit,
      overdueCount: overdueCount,
      fullyPaidCount: fullyPaidCount,
      calculations: calculations,
    );
  }
}

/// نموذج تقرير ملخص المدفوعات
class PaymentsSummaryReport {
  PaymentsSummaryReport({
    required this.generatedAt,
    required this.totalGuests,
    required this.totalPaid,
    required this.totalRemaining,
    required this.totalCredit,
    required this.overdueCount,
    required this.fullyPaidCount,
    required this.calculations,
  });
  final DateTime generatedAt;
  final int totalGuests;
  final double totalPaid;
  final double totalRemaining;
  final double totalCredit;
  final int overdueCount;
  final int fullyPaidCount;
  final List<GuestPaymentCalculation> calculations;

  /// نسبة الحجوزات المسددة بالكامل
  double get fullyPaidPercentage =>
      totalGuests > 0 ? (fullyPaidCount / totalGuests * 100) : 0;

  /// نسبة الحجوزات المتأخرة
  double get overduePercentage =>
      totalGuests > 0 ? (overdueCount / totalGuests * 100) : 0;

  /// ملخص نصي للتقرير
  String getSummary() {
    final df = DateFormat('yyyy/MM/dd HH:mm');
    final buffer = StringBuffer();

    buffer.writeln('=== تقرير ملخص المدفوعات ===');
    buffer.writeln('تم الإنشاء: ${df.format(generatedAt)}');
    buffer.writeln();
    buffer.writeln('--- الإحصائيات العامة ---');
    buffer.writeln('عدد النزلاء: $totalGuests');
    buffer.writeln('إجمالي المحصل: $totalPaid ريال');
    buffer.writeln('إجمالي المتبقي: $totalRemaining ريال');
    buffer.writeln('إجمالي الأرصدة (للنزلاء): $totalCredit ريال');
    buffer.writeln();
    buffer.writeln('--- الحالات ---');
    buffer.writeln(
      'المسددة بالكامل: $fullyPaidCount (${fullyPaidPercentage.toStringAsFixed(1)}%)',
    );
    buffer.writeln(
      'المتأخرة: $overdueCount (${overduePercentage.toStringAsFixed(1)}%)',
    );

    return buffer.toString();
  }
}
