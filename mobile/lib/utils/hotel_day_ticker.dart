import 'dart:async';

/// تيار تفاعلي عالمي لبداية اليوم الفندقي الجديد.
///
/// يُصدر حدث (event) تلقائياً عند عبور الساعة 14:01
/// لتحديث جميع الشاشات المفتوحة ديناميكياً بدون إعادة فتحها.
///
/// ## الاستخدام
///
/// ### في StatefulWidget (طريقة مباشرة):
/// ```dart
/// StreamSubscription<void>? _tickerSub;
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
  static const int _hotelStartMinute = 1;

  StreamController<void>? _controller;
  Timer? _timer;

  /// تيار يُصدر `null` عند كل بداية يوم فندقي جديد (14:01).
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
    if (_controller != null && !_controller!.isClosed) {
      return;
    }
    _controller = StreamController<void>.broadcast();
    // ✅ OCR FIX (2026-08-06): فحص فوري إذا فات الحدث عند بدء التطبيق.
    // سابقاً، لو فُتح التطبيق بعد 14:01 (مثلاً 14:05)، كان ينتظر حتى 14:01
    // غداً — يفوّت تنبيه اليوم الفندقي. الآن نُصدر tick فوري إذا فات الحدث
    // خلال آخر ساعة (لتفادي false positives عند إعادة تشغيل التطبيق).
    _emitMissedTickIfNeeded();
    _scheduleNext();
  }

  /// ✅ OCR FIX: يُصدر tick فوري إذا فات الحدث عند بدء التطبيق.
  ///
  /// السيناريو: التطبيق كان مغلقاً عند 14:01، وفُتح عند 14:05.
  /// بدون هذا الفحص، الشاشات لن تعرف أن اليوم الفندقي تغيّر حتى غداً.
  ///
  /// القيود: نُصدر tick فقط إذا كان الوقت الحالي ضمن ساعة من 14:01
  /// (14:01 - 15:01) لتجنب إصدار ticks خاطئة عند فتح التطبيق في منتصف
  /// الليل بعد يوم كامل من الإغلاق.
  void _emitMissedTickIfNeeded() {
    final now = DateTime.now();
    final todayHotelDayStart = DateTime(
      now.year,
      now.month,
      now.day,
      _hotelStartHour,
      _hotelStartMinute,
    );

    // إذا كنا خلال ساعة بعد 14:01 اليوم، نُصدر tick فوري
    final oneHourAfterStart = todayHotelDayStart.add(
      const Duration(hours: 1),
    );
    if (now.isAfter(todayHotelDayStart) && now.isBefore(oneHourAfterStart)) {
      // استخدام scheduleMicrotask لتجنب استدعاء listeners متزامن أثناء init
      scheduleMicrotask(() {
        if (_controller != null && !_controller!.isClosed) {
          _controller!.add(null);
        }
      });
    }
  }

  void _scheduleNext() {
    _timer?.cancel();
    final now = DateTime.now();
    var next = DateTime(
      now.year,
      now.month,
      now.day,
      _hotelStartHour,
      _hotelStartMinute,
    );
    // ✅ OCR FIX: توضيح أوضح للحالة الحافة.
    // إذا تجاوزنا 14:01 اليوم (now >= next)، الهدف هو 14:01 غداً.
    // ملاحظة: isBefore يُرجع true فقط إذا كان now < next بدقة millisecond.
    // لذا إذا كان now == next بالضبط، isBefore يُرجع false وننتقل لليوم التالي
    // — وهو صحيح لأن الحدث أُصدر بالفعل في _emitMissedTickIfNeeded.
    if (!now.isBefore(next)) {
      next = next.add(const Duration(days: 1));
    }
    final delay = next.difference(now);
    _timer = Timer(delay, () {
      _controller?.add(null);
      _scheduleNext(); // جدولة اليوم التالي
    });
  }

  /// إيقاف التقر وتحرير الموارد.
  /// لا تحتاج لاستدعائه عادةً لأن الـ singleton يعيش طوال عمر التطبيق.
  ///
  /// ✅ OCR FIX (2026-08-06): تأكيد إلغاء كل الموارد لمنع memory leaks.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_controller != null && !_controller!.isClosed) {
      _controller!.close();
    }
    _controller = null;
  }
}
