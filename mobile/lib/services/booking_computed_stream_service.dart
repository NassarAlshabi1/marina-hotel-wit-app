import 'dart:async';
import '../../utils/hotel_time_engine.dart';
import '../../utils/hotel_day_ticker.dart';
import 'local_db.dart';

// ═══════════════════════════════════════════════════════════════════
// النماذج المحسوبة (لا تُخزن في قاعدة البيانات)
// ═══════════════════════════════════════════════════════════════════

/// بيانات حجز مع تجميع المدفوعات وكل الحقول المالية المحسوبة.
///
/// **مبدأ التصميم:**
/// - لا يُخزن أي قيمة محسوبة — كل شيء يُحسب في الوقت الحقيقي
/// - المصدر الوحيد للحقيقة: Booking + Payments + Rooms.price
/// - HotelTimeEngine هو المحرك الوحيد للحسابات
/// - يتحدث تلقائياً عند: تغيير بيانات، عبور 14:00، مزامنة
///
/// **لا يستخدم أبداً:** booking.hotelDayKey، booking.totalDueCached، إلخ
class BookingWithPayments {
  /// بيانات الحجز الخام من قاعدة البيانات
  final Booking booking;

  /// عدد الليالي المحسوب ديناميكياً (HotelTimeEngine.calculateDays)
  final int days;

  /// المبلغ الإجمالي = days × roomPrice (مع الخصم إن وُجد)
  final double total;

  /// مجموع المدفوعات الفعلي (بدون الملغاة)
  final double paid;

  /// الرصيد المتبقي = total - paid
  final double remaining;

  /// هل دُفع المبلغ كاملاً؟
  final bool isFullyPaid;

  /// هل الحجز متأخر عن الخروج؟
  final bool isOverdue;

  /// هل يحتاج مراجعة الخروج؟
  final bool needsCheckoutReview;

  /// سعر الغرفة (من جدول rooms.price)
  final double roomPrice;

  /// يوم الدخول الفندقي YYYY-MM-DD
  final String hotelDayCheckin;

  /// يوم الخروج الفندقي YYYY-MM-DD (أو null)
  final String? hotelDayCheckout;

  /// اليوم الفندقي الحالي YYYY-MM-DD
  final String currentHotelDay;

  /// هل الوقت الحالي بعد 14:00؟
  final bool isAfterCutoff;

  /// قائمة المدفوعات الفعلية (غير الملغاة)
  final List<Payment> payments;

  BookingWithPayments({
    required this.booking,
    required this.days,
    required this.total,
    required this.paid,
    required this.remaining,
    required this.isFullyPaid,
    required this.isOverdue,
    required this.needsCheckoutReview,
    required this.roomPrice,
    required this.hotelDayCheckin,
    this.hotelDayCheckout,
    required this.currentHotelDay,
    required this.isAfterCutoff,
    this.payments = const [],
  });

  /// حساب سريع لليلة الواحدة (متوسط)
  double get averageNightlyRate => days > 0 ? total / days : 0;

  /// نسبة الدفع (0.0 إلى 1.0)
  double get paymentProgress => total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;
}

/// نموذج خفيف لحجز مع حقول محسوبة أساسية (بدون مدفوعات).
///
/// يُستخدم للقوائم السريعة التي لا تحتاج تفاصيل المدفوعات.
class BookingWithComputed {
  final Booking booking;
  final int dynamicNights;
  final double dynamicTotal;
  final bool isAfterCutoff;
  final String currentHotelDay;

  BookingWithComputed({
    required this.booking,
    required this.dynamicNights,
    required this.dynamicTotal,
    required this.isAfterCutoff,
    required this.currentHotelDay,
  });
}

// ═══════════════════════════════════════════════════════════════════
// خدمة التيارات التفاعلية
// ═══════════════════════════════════════════════════════════════════

/// خدمة التيارات التفاعلية للحجوزات مع حقول محسوبة ديناميكياً.
///
/// **مبدأ التصميم:**
/// - مصدر الحقيقة: checkinDate + actualCheckout + rooms.price + payments
/// - كل القيم تُحسب ديناميكياً في الوقت الحقيقي عبر [HotelTimeEngine]
/// - UI يتحدث تلقائياً عند 3 أحداث:
///   1. تغيير بيانات الحجز في DB
///   2. عبور الساعة 14:00 (HotelDayTicker)
///   3. إضافة/تعديل/إلغاء دفعة
///
/// **لا يعتمد على أي حقل محسوب في قاعدة البيانات.**
///
/// ## الاستخدام في UI
/// ```dart
/// final service = ref.read(bookingComputedStreamProvider(db));
///
/// // عرض كل حجوزات غرفة مع الحقول المالية
/// StreamBuilder<List<BookingWithPayments>>(
///   stream: service.watchBookingsWithPaymentsByRoom('101'),
///   builder: (_, snap) {
///     final data = snap.data ?? [];
///     return ListView.builder(
///       itemCount: data.length,
///       itemBuilder: (_, i) {
///         final b = data[i];
///         return ListTile(
///           title: Text('أيام: ${b.days} | الإجمالي: ${b.total}'),
///           subtitle: Text(
///             'المدفوع: ${b.paid} | المتبقي: ${b.remaining}',
///           ),
///         );
///       },
///     );
///   },
/// )
/// ```
class BookingComputedStreamService {
  final AppDatabase db;

  BookingComputedStreamService(this.db);

  // ─── تجميع المدفوعات ───────────────────────────────────────

  /// جلب سعر الغرفة من جدول rooms.
  ///
  /// يبحث عن طريق roomNumber. إذا لم يجد الغرفة يُرجع 0.
  Future<double> _getRoomPrice(String roomNumber) async {
    try {
      final room = await (db.select(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))
            ..where((r) => r.deletedAt.isNull()))
          .getSingleOrNull();
      return (room?.price ?? 0).toDouble();
    } catch (_) {
      return 0;
    }
  }

  /// جلب مدفوعات حجز معينة (الفعالة فقط).
  ///
  /// يبحث بـ bookingLocalId. يُستثنى المدفوعات الملغاة (isVoided)
  /// والمدفوعات المعلقة (isPendingBalance).
  Future<List<Payment>> _getPaymentsForBooking(int bookingId) async {
    return (db.select(db.payments)
          ..where((p) => p.bookingLocalId.equals(bookingId))
          ..where((p) => p.deletedAt.isNull())
          ..where((p) => p.isVoided.equals(false)))
        .get();
  }

  /// تجميع المدفوعات الفعالية = مجموع المبالغ غير الملغاة.
  double _sumPayments(List<Payment> payments) {
    return payments
        .where((p) => !p.isVoided)
        .fold<double>(0, (sum, p) => sum + p.amount);
  }

  // ─── حساب BookingWithPayments كامل ────────────────────────

  /// حساب كل الحقول المحسوبة لحجز واحد (مع المدفوعات).
  ///
  /// هذا هو المحرك المركزي — كل القراءات تمر من هنا.
  /// يستخدم [HotelTimeEngine] حصرياً.
  Future<BookingWithPayments> _computeWithPayments(Booking booking) async {
    final checkin = DateTime.tryParse(booking.checkinDate);
    final checkoutDate = booking.actualCheckout ?? booking.checkoutDate;
    final checkout = checkoutDate != null && checkoutDate.isNotEmpty
        ? DateTime.tryParse(checkoutDate)
        : null;

    // 1. حساب الليالي (HotelTimeEngine)
    final days = checkin != null
        ? HotelTimeEngine.calculateDays(
            checkin,
            checkOut: checkout,
          )
        : 1;

    // 2. سعر الغرفة (من جدول rooms)
    final roomPrice = await _getRoomPrice(booking.roomNumber);

    // 3. المدفوعات (من جدول payments)
    final payments = await _getPaymentsForBooking(booking.id);
    final paid = _sumPayments(payments);

    // 4. حساب الإجمالي مع الخصم
    final total = HotelTimeEngine.calculateTotal(
      days: days,
      roomPrice: roomPrice,
      discount: booking.discount,
      discountType: booking.discountType,
    );

    // 5. الرصيد المتبقي
    final remaining = total - paid;

    // 6. حالة الدفع
    final isFullyPaid = remaining <= 0;

    // 7. حالة التأخير
    final isOverdue = HotelTimeEngine.isOverdue(
      status: booking.status,
      checkoutDate: booking.checkoutDate,
    );

    // 8. مراجعة الخروج
    final needsCheckoutReview = HotelTimeEngine.needsCheckoutReview(
      isOverdue: isOverdue,
      remainingBalance: remaining,
    );

    // 9. أيام فندقية
    final hotelDayCheckin = checkin != null
        ? HotelTimeEngine.getHotelDayKey(dateTime: checkin)
        : '';
    final hotelDayCheckout = checkout != null
        ? HotelTimeEngine.getHotelDayKey(dateTime: checkout)
        : null;

    return BookingWithPayments(
      booking: booking,
      days: days,
      total: total,
      paid: paid,
      remaining: remaining,
      isFullyPaid: isFullyPaid,
      isOverdue: isOverdue,
      needsCheckoutReview: needsCheckoutReview,
      roomPrice: roomPrice,
      hotelDayCheckin: hotelDayCheckin,
      hotelDayCheckout: hotelDayCheckout,
      currentHotelDay: HotelTimeEngine.getHotelDayKey(),
      isAfterCutoff: HotelTimeEngine.isNowAfterCutoff(),
      payments: payments,
    );
  }

  /// حساب خفيف بدون مدفوعات.
  BookingWithComputed _computeLight(Booking booking, double roomRate) {
    final checkin = DateTime.tryParse(booking.checkinDate);
    final actualCheckout = booking.actualCheckout != null
        ? DateTime.tryParse(booking.actualCheckout!)
        : null;

    final effectiveCheckout = actualCheckout ?? DateTime.now();
    final dynamicNights = checkin != null
        ? HotelTimeEngine.calculateDays(
            checkin,
            checkOut: effectiveCheckout,
          )
        : 1;

    return BookingWithComputed(
      booking: booking,
      dynamicNights: dynamicNights,
      dynamicTotal: dynamicNights * roomRate,
      isAfterCutoff: HotelTimeEngine.isNowAfterCutoff(),
      currentHotelDay: HotelTimeEngine.getHotelDayKey(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // تيارات BookingWithPayments (مع المدفوعات)
  // ═══════════════════════════════════════════════════════════════

  /// تيار تفاعلي لحجز واحد مع كل البيانات المالية.
  ///
  /// يتحدث تلقائياً عند:
  /// - تغيير بيانات الحجز
  /// - إضافة/تعديل/إلغاء دفعة
  /// - عبور الساعة 14:00
  Stream<BookingWithPayments?> watchBookingWithPayments(int bookingId) {
    final controller = StreamController<BookingWithPayments?>.broadcast();
    StreamSubscription<Booking?>? bookingSub;
    StreamSubscription<List<Payment>>? paymentSub;
    StreamSubscription<void>? tickerSub;

    void emit() async {
      final booking = await (db.select(db.bookings)
            ..where((b) => b.id.equals(bookingId)))
          .getSingleOrNull();
      if (booking != null && !controller.isClosed) {
        final result = await _computeWithPayments(booking);
        if (!controller.isClosed) {
          controller.add(result);
        }
      }
    }

    // الاستماع لتغييرات الحجز
    bookingSub = (db.select(db.bookings)
          ..where((b) => b.id.equals(bookingId)))
        .watchSingleOrNull()
        .listen(
      (_) => emit(),
      onError: controller.addError,
    );

    // الاستماع لتغييرات المدفوعات
    paymentSub = (db.select(db.payments)
          ..where((p) => p.bookingLocalId.equals(bookingId))
          ..where((p) => p.deletedAt.isNull()))
        .watch()
        .listen(
      (_) => emit(),
      onError: controller.addError,
    );

    // الاستماع لعبور 14:00
    tickerSub = HotelDayTicker.instance.stream.listen((_) => emit());

    controller.onCancel = () {
      bookingSub?.cancel();
      paymentSub?.cancel();
      tickerSub?.cancel();
    };

    return controller.stream;
  }

  /// تيار تفاعلي لجميع الحجوزات النشطة مع المدفوعات.
  ///
  /// هذا هو التيار الرئيسي للوحة التحكم.
  Stream<List<BookingWithPayments>> watchActiveBookingsWithPayments() {
    final bookingsStream = (db.select(db.bookings)
          ..where((b) => b.status.equals('نشط'))
          ..where((b) => b.deletedAt.isNull()))
        .watch();

    return _mergeListWithPayments(bookingsStream);
  }

  /// تيار تفاعلي لحجوزات غرفة معينة مع المدفوعات.
  Stream<List<BookingWithPayments>> watchBookingsWithPaymentsByRoom(
    String roomNumber,
  ) {
    final bookingsStream = (db.select(db.bookings)
          ..where((b) => b.roomNumber.equals(roomNumber))
          ..where((b) => b.deletedAt.isNull()))
        .watch();

    return _mergeListWithPayments(bookingsStream);
  }

  /// تيار تفاعلي لحجوزات بحالة معينة مع المدفوعات.
  Stream<List<BookingWithPayments>> watchBookingsWithPaymentsByStatus(
    String status,
  ) {
    final bookingsStream = (db.select(db.bookings)
          ..where((b) => b.status.equals(status))
          ..where((b) => b.deletedAt.isNull()))
        .watch();

    return _mergeListWithPayments(bookingsStream);
  }

  /// تيار تفاعلي لكل الحجوزات (بكل الحالات) مع المدفوعات.
  Stream<List<BookingWithPayments>> watchAllBookingsWithPayments() {
    final bookingsStream = (db.select(db.bookings)
          ..where((b) => b.deletedAt.isNull()))
        .watch();

    return _mergeListWithPayments(bookingsStream);
  }

  // ═══════════════════════════════════════════════════════════════
  // تيارات BookingWithComputed (بدون مدفوعات — خفيف)
  // ═══════════════════════════════════════════════════════════════

  /// تيار تفاعلي لحجز واحد مع حساب الليالي فقط.
  Stream<BookingWithComputed?> watchBookingWithComputed(
    int bookingId, {
    double roomRate = 0,
  }) {
    final controller = StreamController<BookingWithComputed?>.broadcast();
    Booking? lastBooking;
    StreamSubscription<Booking?>? dbSub;
    StreamSubscription<void>? tickerSub;

    void emit() {
      if (lastBooking != null && !controller.isClosed) {
        controller.add(_computeLight(lastBooking!, roomRate));
      }
    }

    dbSub = (db.select(db.bookings)
          ..where((b) => b.id.equals(bookingId)))
        .watchSingleOrNull()
        .listen(
      (booking) {
        lastBooking = booking;
        emit();
      },
      onError: controller.addError,
    );

    tickerSub = HotelDayTicker.instance.stream.listen((_) => emit());

    controller.onCancel = () {
      dbSub?.cancel();
      tickerSub?.cancel();
    };

    return controller.stream;
  }

  /// تيار تفاعلي لجميع الحجوزات النشطة (خفيف).
  Stream<List<BookingWithComputed>> watchActiveBookings({
    double defaultRoomRate = 0,
  }) {
    final dbStream = (db.select(db.bookings)
          ..where((b) => b.status.equals('نشط'))
          ..where((b) => b.deletedAt.isNull()))
        .watch();

    return _mergeListLight(dbStream, defaultRoomRate: defaultRoomRate);
  }

  /// تيار تفاعلي لحجوزات غرفة معينة (خفيف).
  Stream<List<BookingWithComputed>> watchBookingsByRoom(
    String roomNumber, {
    double defaultRoomRate = 0,
  }) {
    final dbStream = (db.select(db.bookings)
          ..where((b) => b.roomNumber.equals(roomNumber))
          ..where((b) => b.deletedAt.isNull()))
        .watch();

    return _mergeListLight(dbStream, defaultRoomRate: defaultRoomRate);
  }

  /// تيار تفاعلي لحجوزات بحالة معينة (خفيف).
  Stream<List<BookingWithComputed>> watchBookingsByStatus(
    String status, {
    double defaultRoomRate = 0,
  }) {
    final dbStream = (db.select(db.bookings)
          ..where((b) => b.status.equals(status))
          ..where((b) => b.deletedAt.isNull()))
        .watch();

    return _mergeListLight(dbStream, defaultRoomRate: defaultRoomRate);
  }

  // ─── دمج مع HotelDayTicker ──────────────────────────────────

  /// دمج تيار قائمة حجوزات مع المدفوعات وتيار 14:00.
  Stream<List<BookingWithPayments>> _mergeListWithPayments(
    Stream<List<Booking>> dbStream,
  ) {
    final controller =
        StreamController<List<BookingWithPayments>>.broadcast();
    List<Booking>? lastData;
    StreamSubscription<List<Booking>>? dbSub;
    StreamSubscription<void>? tickerSub;

    void emit() async {
      if (lastData != null && !controller.isClosed) {
        final results = await Future.wait(
          lastData!.map((b) => _computeWithPayments(b)),
        );
        if (!controller.isClosed) {
          controller.add(results);
        }
      }
    }

    dbSub = dbStream.listen(
      (data) {
        lastData = data;
        emit();
      },
      onError: controller.addError,
    );

    tickerSub = HotelDayTicker.instance.stream.listen((_) => emit());

    controller.onCancel = () {
      dbSub?.cancel();
      tickerSub?.cancel();
    };

    return controller.stream;
  }

  /// دمج تيار قائمة حجوزات (خفيف — بدون مدفوعات).
  Stream<List<BookingWithComputed>> _mergeListLight(
    Stream<List<Booking>> dbStream, {
    required double defaultRoomRate,
  }) {
    final controller =
        StreamController<List<BookingWithComputed>>.broadcast();
    List<Booking>? lastData;
    StreamSubscription<List<Booking>>? dbSub;
    StreamSubscription<void>? tickerSub;

    void emit() {
      if (lastData != null && !controller.isClosed) {
        final computed =
            lastData!.map((b) => _computeLight(b, defaultRoomRate)).toList();
        controller.add(computed);
      }
    }

    dbSub = dbStream.listen(
      (data) {
        lastData = data;
        emit();
      },
      onError: controller.addError,
    );

    tickerSub = HotelDayTicker.instance.stream.listen((_) => emit());

    controller.onCancel = () {
      dbSub?.cancel();
      tickerSub?.cancel();
    };

    return controller.stream;
  }
}
