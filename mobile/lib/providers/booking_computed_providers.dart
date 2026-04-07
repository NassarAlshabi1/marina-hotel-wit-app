import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'repository_providers.dart';
import '../services/booking_computed_stream_service.dart';
import '../utils/hotel_day_ticker.dart';

// ═══════════════════════════════════════════════════════════════════
// Providers لخدمة الحساب التفاعلي
// ═══════════════════════════════════════════════════════════════════

/// مزود خدمة الحساب التفاعلي للحجوزات.
///
/// ## الاستخدام
/// ```dart
/// // في ConsumerWidget:
/// final computedService = ref.watch(bookingComputedStreamProvider);
///
/// // في StreamBuilder:
/// StreamBuilder<List<BookingWithPayments>>(
///   stream: computedService.watchActiveBookingsWithPayments(),
///   builder: (_, snap) => YourWidget(snap.data),
/// )
/// ```
final bookingComputedStreamProvider = Provider<BookingComputedStreamService>(
  (ref) {
    final db = ref.watch(databaseProvider);
    return BookingComputedStreamService(db);
  },
  dependencies: [databaseProvider],
);

// ═══════════════════════════════════════════════════════════════════
// Providers للتيارات التفاعلية (جاهزة للاستخدام المباشر)
// ═══════════════════════════════════════════════════════════════════

/// تيار تفاعلي لكل الحجوزات النشطة مع البيانات المالية الكاملة.
///
/// يتحدث تلقائياً عند:
/// - تغيير بيانات أي حجز
/// - إضافة/تعديل/إلغاء أي دفعة
/// - عبور الساعة 14:00
///
/// **هذا هو التيار الرئيسي للوحة التحكم وشاشة الحجوزات.**
final activeBookingsWithPaymentsProvider = StreamProvider<
    List<BookingWithPayments>>((ref) {
  final service = ref.watch(bookingComputedStreamProvider);
  return service.watchActiveBookingsWithPayments();
});

/// تيار تفاعلي لحجوزات غرفة معينة مع البيانات المالية.
///
/// [roomNumber] رقم الغرفة.
final bookingsWithPaymentsByRoomProvider =
    StreamProvider.autoDispose.family<List<BookingWithPayments>, String>(
  (ref, roomNumber) {
    final service = ref.watch(bookingComputedStreamProvider);
    return service.watchBookingsWithPaymentsByRoom(roomNumber);
  },
);

/// تيار تفاعلي لحجز واحد مع البيانات المالية الكاملة.
///
/// [bookingId] المعرف المحلي للحجز.
final singleBookingWithPaymentsProvider = StreamProvider.autoDispose
    .family<BookingWithPayments?, int>((ref, bookingId) {
  final service = ref.watch(bookingComputedStreamProvider);
  return service.watchBookingWithPayments(bookingId);
});

// ═══════════════════════════════════════════════════════════════════
// Provider لتيار HotelDayTicker
// ═══════════════════════════════════════════════════════════════════

/// تيار يُصدر حدث عند عبور الساعة 14:00.
///
/// يُستخدم كطبقة خارجية لـ StreamBuilder لتحديث UI ديناميكياً
/// عند بداية اليوم الفندقي الجديد.
///
/// ```dart
/// StreamBuilder(
///   stream: ref.watch(hotelDayTickerProvider),
///   builder: (_, __) {
///     // إعادة بناء Widget عند عبور 14:00
///     return const MyWidget();
///   },
/// )
/// ```
final hotelDayTickerProvider = Provider<Stream<void>>((ref) {
  return HotelDayTicker.instance.stream;
});
