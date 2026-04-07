import 'dart:async';

/// تيار تفاعلي عالمي لبداية اليوم الفندقي الجديد.
///
/// يُصدر حدث (event) تلقائياً عند عبور الساعة 14:00
/// لتحديث جميع الشاشات المفتوحة ديناميكياً بدون إعادة فتحها.
///
/// ## الاستخدام
///
/// ### في StatefulWidget (طريقة مباشرة):
/// ```dart
/// StreamSubscription? _tickerSub;
///
/// @override
/// void initState() {
///   super.initState();
///   _tickerSub = HotelDayTicker.instance.stream.listen((_) {
///     if (mounted) setState(() {});
///   });
/// }
///
/// @override
/// void dispose() {
///   _tickerSub?.cancel();
///   super.dispose();
/// }
/// ```
///
/// ### في StreamBuilder (طريقة تفاعلية):
/// ```dart
/// StreamBuilder(
///   stream: HotelDayTicker.instance.stream,
///   builder: (_, __) {
///     return StreamBuilder<List<Booking>>(
///       stream: bookingsRepo.watchAll(),
///       builder: (context, snapshot) => YourWidget(snapshot.data),
///     );
///   },
/// )
/// ```
///
/// ### لدمج تيارين معاً:
/// ```dart
/// import 'package:async/async.dart' show StreamGroup;
///
/// final merged = StreamGroup.merge([
///   db.watchBookings(),
///   HotelDayTicker.instance.stream,
/// ]);
/// ```
class HotelDayTicker {
  HotelDayTicker._();
  static final HotelDayTicker instance = HotelDayTicker._();

  static const int _hotelStartHour = 14;

  StreamController<void>? _controller;
  Timer? _timer;

  /// تيار يُصدر `null` عند كل بداية يوم فندقي جديد (14:00).
  /// لا يُصدر قيمة عند الاشتراك — فقط عند الحدث.
  Stream<void> get stream {
    _ensureStarted();
    return _controller!.stream;
  }

  /// إصدار حدث يدوي (للاختبار أو للاستخدام الخارجي).
  void manualTick() {
    _ensureStarted();
    _controller?.add(null);
  }

  void _ensureStarted() {
    if (_controller != null && !_controller!.isClosed) return;
    _controller = StreamController<void>.broadcast();
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, _hotelStartHour);
    // إذا تجاوزنا 14:00 اليوم، الهدف هو 14:00 غداً
    if (!now.isBefore(next)) {
      next = next.add(const Duration(days: 1));
    }
    final delay = next.difference(now) + const Duration(seconds: 1);
    _timer = Timer(delay, () {
      _controller?.add(null);
      _scheduleNext(); // جدولة اليوم التالي
    });
  }

  /// إيقاف التقر وتحرير الموارد.
  /// لا تحتاج لاستدعائه عادةً لأن الـ singleton يعيش طوال عمر التطبيق.
  void dispose() {
    _timer?.cancel();
    _controller?.close();
    _timer = null;
    _controller = null;
  }
}
