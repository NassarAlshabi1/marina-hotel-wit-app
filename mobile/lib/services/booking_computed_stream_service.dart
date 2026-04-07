import 'dart:async';
import '../../utils/hotel_date_helper.dart';
import '../../utils/hotel_day_ticker.dart';
import '../local_db.dart';

/// بيانات حجز مع حقول محسوبة ديناميكياً.
///
/// لا تُخزن القيم المحسوبة — تُحسب في الوقت الحقيقي
/// من البيانات الأساسية (checkinDate, actualCheckout, roomRate).
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

/// خدمة التيارات التفاعلية للحجوزات مع حقول محسوبة ديناميكياً.
///
/// **مبدأ التصميم:**
/// - مصدر الحقيقة: checkinDate + actualCheckout فقط
/// - الأيام والمبالغ تُحسب ديناميكياً في الوقت الحقيقي
/// - UI يتحدث تلقائياً عند: تغيير البيانات، عبور 14:00، مزامنة
///
/// ## الاستخدام
/// ```dart
/// final service = BookingComputedStreamService(db);
///
/// // تيار تفاعلي لحجز واحد
/// StreamBuilder<BookingWithComputed?>(
///   stream: service.watchBookingWithComputed(booking.id, roomRate: 150),
///   builder: (_, snap) => Text('أيام: ${snap.data?.dynamicNights}'),
/// )
/// ```
class BookingComputedStreamService {
  final AppDatabase _db;

  BookingComputedStreamService(this._db);

  /// تيار تفاعلي لحجز واحد مع حساب الليالي ديناميكياً.
  ///
  /// يدمج مصدرين:
  /// 1. تغييرات الحجز في DB
  /// 2. عبور الساعة 14:00 (HotelDayTicker)
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
        controller.add(_compute(lastBooking!, roomRate));
      }
    }

    // الاستماع لتغييرات DB
    dbSub = (_db.select(_db.bookings)
          ..where((b) => b.id.equals(bookingId)))
        .watchSingleOrNull()
        .listen(
      (booking) {
        lastBooking = booking;
        emit();
      },
      onError: controller.addError,
    );

    // الاستماع لعبور 14:00
    tickerSub = HotelDayTicker.instance.stream.listen((_) => emit());

    controller.onCancel = () {
      dbSub?.cancel();
      tickerSub?.cancel();
    };

    return controller.stream;
  }

  /// تيار تفاعلي لجميع الحجوزات النشطة مع حساب الليالي ديناميكياً.
  Stream<List<BookingWithComputed>> watchActiveBookings({
    double defaultRoomRate = 0,
  }) {
    final dbStream = (_db.select(_db.bookings)
          ..where((b) => b.status.equals('نشط'))
          ..where((b) => b.deletedAt.isNull()))
        .watch();

    return _mergeListWithTicker(dbStream, defaultRoomRate: defaultRoomRate);
  }

  /// تيار تفاعلي لحجوزات غرفة معينة.
  Stream<List<BookingWithComputed>> watchBookingsByRoom(
    String roomNumber, {
    double defaultRoomRate = 0,
  }) {
    final dbStream = (_db.select(_db.bookings)
          ..where((b) => b.roomNumber.equals(roomNumber))
          ..where((b) => b.deletedAt.isNull()))
        .watch();

    return _mergeListWithTicker(dbStream, defaultRoomRate: defaultRoomRate);
  }

  /// تيار تفاعلي لحجوزات بحالة معينة.
  Stream<List<BookingWithComputed>> watchBookingsByStatus(
    String status, {
    double defaultRoomRate = 0,
  }) {
    final dbStream = (_db.select(_db.bookings)
          ..where((b) => b.status.equals(status))
          ..where((b) => b.deletedAt.isNull()))
        .watch();

    return _mergeListWithTicker(dbStream, defaultRoomRate: defaultRoomRate);
  }

  // ─── دمج مع HotelDayTicker ──────────────────────────────────

  /// دمج تيار قائمة DB مع تيار 14:00.
  Stream<List<BookingWithComputed>> _mergeListWithTicker(
    Stream<List<Booking>> dbStream, {
    required double defaultRoomRate,
  }) {
    final controller = StreamController<List<BookingWithComputed>>.broadcast();
    List<Booking>? lastData;
    StreamSubscription<List<Booking>>? dbSub;
    StreamSubscription<void>? tickerSub;

    void emit() {
      if (lastData != null && !controller.isClosed) {
        final computed =
            lastData!.map((b) => _compute(b, defaultRoomRate)).toList();
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

  // ─── الحساب الديناميكي ────────────────────────────────────

  /// حساب الحقول المشتقة لحجز واحد.
  ///
  /// يستخدم [HotelDateHelper.calculateNights] لحساب الليالي ديناميكياً
  /// بناءً على تاريخ الدخول ووقت الخروج (أو الوقت الحالي إذا لم يخرج).
  BookingWithComputed _compute(Booking booking, double roomRate) {
    final checkin = DateTime.tryParse(booking.checkinDate);
    final actualCheckout = booking.actualCheckout != null
        ? DateTime.tryParse(booking.actualCheckout!)
        : null;

    // إذا لم يسجل النزيل خروج، نستخدم الوقت الحالي
    final effectiveCheckout = actualCheckout ?? DateTime.now();
    final dynamicNights = checkin != null
        ? HotelDateHelper.calculateNights(
            checkIn: checkin,
            checkOut: effectiveCheckout,
          )
        : booking.calculatedNights;

    return BookingWithComputed(
      booking: booking,
      dynamicNights: dynamicNights,
      dynamicTotal: dynamicNights * roomRate,
      isAfterCutoff: HotelDateHelper.isNowAfterCutoff(),
      currentHotelDay: HotelDateHelper.getHotelDayKey(),
    );
  }
}
