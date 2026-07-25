import 'dart:async';

<<<<<<< HEAD
=======
import 'package:drift/drift.dart' show Value;
>>>>>>> origin/refactor/clean-v2
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/repository_providers.dart';
import '../../services/booking_derived_fields_service.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_parser.dart';
import '../../utils/hotel_date_helper.dart';
import '../../utils/hotel_day_ticker.dart';
import '../../utils/time.dart';

class BookingCheckoutScreen extends ConsumerStatefulWidget {
<<<<<<< HEAD
  const BookingCheckoutScreen({required this.booking, super.key});
=======
  const BookingCheckoutScreen({super.key, required this.booking});
>>>>>>> origin/refactor/clean-v2
  final Booking booking;

  @override
  ConsumerState<BookingCheckoutScreen> createState() => _BookingCheckoutScreenState();
}

class _BookingCheckoutScreenState extends ConsumerState<BookingCheckoutScreen> with SyncOnExitMixin {
  @override
  String get screenId => 'booking_checkout';
<<<<<<< HEAD
=======
  final ValueNotifier<bool> _isProcessing = ValueNotifier<bool>(false);
  StreamSubscription<void>? _hotelDayTickerSub;
>>>>>>> origin/refactor/clean-v2

  /// ✅ تحسين أداء: ValueNotifier بدلاً من bool + setState —
  /// يمنع إعادة بناء الشاشة كاملة عند تبديل حالة المعالجة (processing).
  /// فقط الـ widgets التي تقرأ القيمة تُعاد بناؤها عبر ValueListenableBuilder.
  final ValueNotifier<bool> _isProcessingNotifier = ValueNotifier<bool>(false);
  bool get _isProcessing => _isProcessingNotifier.value;
  set _isProcessing(bool value) => _isProcessingNotifier.value = value;

  StreamSubscription<void>? _hotelDayTickerSub;

  @override
  void initState() {
    super.initState();
    _refreshBookingNights();
    _startHotelDayAutoRefresh();
  }

  /// بدء الاستماع للتيار العالمي لبداية اليوم الفندقي الجديد
  void _startHotelDayAutoRefresh() {
    _hotelDayTickerSub = HotelDayTicker.instance.stream.listen((_) {
      if (mounted) {
        setState(() {});
        _refreshBookingNights();
      }
    });
  }

  Future<void> _refreshBookingNights() async {
    final db = ref.read(databaseProvider);
    final derivedService = BookingDerivedFieldsService(db);
    await derivedService.refreshForBookingId(widget.booking.id);
  }

  DateTime? _parseDateTime(String? value) => DateParser.parse(value);

<<<<<<< HEAD
  @override
  void dispose() {
    _hotelDayTickerSub?.cancel();
    _isProcessingNotifier.dispose(); // ✅ تنظيف ValueNotifier لمنع memory leak
=======
  /// ═══════════════════════════════════════════════════════════════════
  /// كشف الليالي المشبوهة — ليالٍ أُضيفت تلقائياً بعد موعد المغادرة المتوقع
  /// ═══════════════════════════════════════════════════════════════════
  ///
  /// المنطق:
  /// 1. نحسب "آخر يوم إقامة متوقع" = checkoutDate أو (checkinDate + expectedNights)
  /// 2. أي ليلة بـ hotelDayKey يقع تاريخ بدايتها بعد هذا اليوم = مشبوهة
  /// 3. سبب الاشتباه: النزيل غادر فعلياً لكن الموظف نسي تسجيل الخروج
  ///    فأضاف النظام ليلة تلقائية بعد تجاوز الساعة 14:00
  List<BookingNight> _detectSuspiciousNights(List<BookingNight> nights, Booking booking) {
    // لا يوجد اشتباه إذا سُجل الخروج فعلياً
    if (booking.actualCheckout != null) return [];
    // لا يوجد اشتباه إذا لم تكن هناك ليالٍ مسجلة
    if (nights.isEmpty) return [];

    // تحديد آخر يوم إقامة متوقع
    final plannedCheckout = _parseDateTime(booking.checkoutDate);
    final checkin = _parseDateTime(booking.checkinDate);

    DateTime? lastExpectedDay;
    if (plannedCheckout != null) {
      // آخر يوم متوقع = يوم قبل موعد المغادرة المخطط
      lastExpectedDay = DateTime(plannedCheckout.year, plannedCheckout.month, plannedCheckout.day);
    } else if (checkin != null && booking.expectedNights > 0) {
      // حساب من تاريخ الدخول + عدد الليالي المتوقعة
      lastExpectedDay = DateTime(
        checkin.year,
        checkin.month,
        checkin.day,
      ).add(Duration(days: booking.expectedNights - 1));
    }

    if (lastExpectedDay == null) return [];

    // فحص كل ليلة: هل hotelDayKey يقع بعد آخر يوم متوقع؟
    final suspicious = <BookingNight>[];
    for (final night in nights) {
      if (_cancelledSuspiciousNightIds.contains(night.id)) continue;
      final nightDayKey = night.hotelDayKey; // صيغة: "YYYY-MM-DD"
      final nightDate = DateTime.tryParse(nightDayKey);
      if (nightDate != null && nightDate.isAfter(lastExpectedDay)) {
        suspicious.add(night);
      }
    }
    return suspicious;
  }

  /// نافذة تأكيد احترافية لمعالجة الليالي المشبوهة
  /// تعرض تفاصيل كل ليلة مشبوهة مع خيار احتسابها أو إلغائها
  ///
  /// ✅ إصلاح (2026-06-28 P2-9): تغيير القيمة المعادة من bool (دائماً true)
  /// إلى void لأن القيمة لم تكن تُستخدم بشكل مفيد.
  Future<void> _showSuspiciousNightsDialog(List<BookingNight> suspiciousNights) async {
    final totalSuspiciousAmount = suspiciousNights.fold<double>(
      0,
      (sum, n) => sum + (n.finalRate > 0 ? n.finalRate : n.nightlyRate),
    );

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
              const SizedBox(width: 10),
              const Expanded(child: Text('تنبيه: ليالٍ مضافة بعد موعد المغادرة', style: TextStyle(fontSize: 16))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تمت إضافة ${suspiciousNights.length} ${suspiciousNights.length == 1 ? "ليلة" : "ليالٍ"} تلقائياً بعد موعد المغادرة المتوقع، '
                        'يُحتمل أنها ناتجة عن نسيان تسجيل الخروج في الوقت المحدد.',
                        style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'تفاصيل الليالي المضافة:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 8),
                ...suspiciousNights.map(
                  (night) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.nightlight, size: 16, color: Colors.red.shade400),
                            const SizedBox(width: 6),
                            Text(night.hotelDayKey, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text(
                          CurrencyFormatter.formatAmount(night.finalRate > 0 ? night.finalRate : night.nightlyRate),
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'إجمالي الليالي المشبوهة:',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700),
                    ),
                    Text(
                      CurrencyFormatter.formatAmount(totalSuspiciousAmount),
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red.shade700),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'ماذا تريد فعلاً بهذه الليالي؟',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  '• "احتساب": تُضاف للمبلغ المستحق (النزيل يدفعها)\n'
                  '• "إلغاء": تُحذف من الفاتورة (خطأ إداري)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          actions: [
            // ✅ إصلاح: لف الأزرار في Row بدل Expanded مباشر في actions.
            // AlertDialog.actions يُعرَض داخل OverflowBar داخلياً الذي لا
            // يقبل Flexible/Expanded → يسبب Fatal Exception:
            //   type '_OverflowBarParentData' is not a subtype of type 'FlexParentData'
            // Row يلتف حول Expanded بشكل صحيح ويحل المشكلة.
            Row(
              children: [
                // زر إلغاء الليالي المشبوهة
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(ctx).pop('cancel_nights'),
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(
                      'إلغاء الليالي\n(${CurrencyFormatter.formatAmount(totalSuspiciousAmount)})',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // زر احتساب الليالي
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(ctx).pop('keep_nights'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      'احتساب الليالي\n(${CurrencyFormatter.formatAmount(totalSuspiciousAmount)})',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (result == 'cancel_nights') {
      // حفظ معرّفات الليالي الملغاة لاستبعادها من الحساب
      if (!mounted) return;
      setState(() {
        _cancelledSuspiciousNightIds.addAll(suspiciousNights.map((n) => n.id));
      });
      return; // تم الإلغاء
    }
    // keep_nights أو إغلاق → نحتسب الليالي (لا حاجة لفعل شيء)
    return;
  }

  /// حذف الليالي الملغاة من قاعدة البيانات عند تسجيل الخروج
  ///
  /// ✅ إصلاح (2026-06-28 P0-2): استدعاء markDataChanged() فوراً بعد الحذف
  /// لضمان رفع الحذف للسحابة. بدون هذا، الليالي المحذوفة محلياً تعود بعد المزامنة.
  Future<void> _deleteCancelledNights() async {
    if (_cancelledSuspiciousNightIds.isEmpty) return;
    final db = ref.read(databaseProvider);
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final nightId in _cancelledSuspiciousNightIds) {
      // ✅ استخدام soft-delete (deletedAt) بدلاً من hard-delete
      // حتى يتتبعها outbox ويرفع الحذف للسحابة
      await (db.update(db.bookingNights)..where((n) => n.id.equals(nightId))).write(
        BookingNightsCompanion(deletedAt: Value(nowEpoch), updatedAt: Value(nowEpoch)),
      );
    }
    // ✅ تسجيل التغيير فوراً ليُرفع للسحابة في الـ sync القادم
    markDataChanged();
  }

  @override
  void dispose() {
    _hotelDayTickerSub?.cancel();
    _isProcessing.dispose();
>>>>>>> origin/refactor/clean-v2
    super.dispose();
  }

  int _countNightsWithDiscount(DateTime checkin, DateTime checkout, DateTime? discountStartDate) {
    if (discountStartDate == null) {
      return Time.nightsWithCutoff(checkin, checkout: checkout);
    }
    final discountDayStart = DateTime(
      discountStartDate.year,
      discountStartDate.month,
      discountStartDate.day,
      14,
    );
    final effectiveStart = discountDayStart.isAfter(checkin) ? discountDayStart : checkin;
    if (!checkout.isAfter(effectiveStart)) {
      return 0;
    }
    return Time.nightsWithCutoff(effectiveStart, checkout: checkout);
  }

  @override
  Widget build(BuildContext context) {
    // ✅ إعادة هيكلة: استبدال 4 StreamBuilders متداخلة بـ Riverpod providers مسطحة.
    final roomAsync = ref.watch(liveRoomByNumberProvider(widget.booking.roomNumber));
    final nightsAsync = ref.watch(bookingNightsProvider(widget.booking.id));
    final paymentsAsync = ref.watch(bookingPaymentsDirectProvider(widget.booking.id));

    // ✅ إصلاح Gemini: التحقق من loading state لمنع حسابات خاطئة
    if (roomAsync.isLoading || nightsAsync.isLoading || paymentsAsync.isLoading) {
      return wrapWithSyncOnExit(
        child: const AppScaffold(
          title: 'دفع الحجز',
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final roomPrice = roomAsync.valueOrNull?.price ?? 0.0;
    final nights = nightsAsync.valueOrNull ?? const <BookingNight>[];
    final payments = paymentsAsync.valueOrNull ?? const <Payment>[];

    final checkin = DateTime.tryParse(widget.booking.checkinDate);
    final plannedCheckout = widget.booking.checkoutDate != null
        ? DateTime.tryParse(widget.booking.checkoutDate!)
        : null;
    final actualCheckout = widget.booking.actualCheckout != null
        ? DateTime.tryParse(widget.booking.actualCheckout!)
        : null;
    final expectedNights = widget.booking.expectedNights > 0
        ? widget.booking.expectedNights
        : (checkin != null ? Time.nightsWithCutoff(checkin, checkout: plannedCheckout) : 1);
    final effectiveCheckout = actualCheckout ?? DateTime.now();
    final hasNotCheckedOut = actualCheckout == null;
    final nowIsAfterCutoff = HotelDateHelper.isNowAfterCutoff();
    final actualNights = checkin != null ? Time.nightsWithCutoff(checkin, checkout: effectiveCheckout) : expectedNights;

    final discount = widget.booking.discount;
    final discountType = widget.booking.discountType;
    final discountStartDate = _parseDateTime(widget.booking.discountStartDate);

    final nightsCount = nights.isNotEmpty ? nights.length : actualNights;
    final nightTotal = nights.isNotEmpty
        ? nights.fold<double>(0, (sum, n) => sum + (n.finalRate > 0 ? n.finalRate : n.nightlyRate))
        : (() {
            final checkout = actualCheckout ?? DateTime.now();
            if (discount > 0 && discountType == 'per_night' && checkin != null) {
              final discountedNights = _countNightsWithDiscount(checkin, checkout, discountStartDate);
              final fullNights = (actualNights - discountedNights).clamp(0, actualNights);
              final discountedRate = (roomPrice - discount).clamp(0.0, roomPrice);
              return (fullNights * roomPrice) + (discountedNights * discountedRate);
            }
            return actualNights * roomPrice;
          })();

    final totalDue = discount > 0 && discountType == 'total'
        ? (nightTotal - discount).clamp(0.0, nightTotal)
        : nightTotal;

    // ✅ استبعاد المدفوعات الملغاة — حساب مرة واحدة (بدلاً من StreamBuilder مكرر)
    final totalPaid = payments.where((p) => !p.isVoided).fold<double>(0, (sum, p) => sum + p.amount);
    final remainingAmount = (totalDue - totalPaid).clamp(0, totalDue).toDouble();

    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'دفع الحجز',
<<<<<<< HEAD
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
=======
        body: StreamBuilder<Room?>(
          stream: roomsRepo.watchByNumber(widget.booking.roomNumber),
          builder: (context, roomSnap) {
            final roomPrice = roomSnap.data?.price ?? 0.0;
            final checkin = DateTime.tryParse(widget.booking.checkinDate);
            final plannedCheckout = widget.booking.checkoutDate != null
                ? DateTime.tryParse(widget.booking.checkoutDate!)
                : null;
            final actualCheckout = widget.booking.actualCheckout != null
                ? DateTime.tryParse(widget.booking.actualCheckout!)
                : null;
            final expectedNights = widget.booking.expectedNights > 0
                ? widget.booking.expectedNights
                : (checkin != null ? Time.nightsWithCutoff(checkin, checkout: plannedCheckout) : 1);
            // إذا لم يسجل النزيل خروج، نستخدم الوقت الحالي لحساب الليالي
            // حتى يتم تطبيق قاعدة الساعة 14:00 (إضافة ليلة إذا تجاوزت الساعة 14)
            final effectiveCheckout = actualCheckout ?? DateTime.now();
            final hasNotCheckedOut = actualCheckout == null;
            final nowIsAfterCutoff = HotelDateHelper.isNowAfterCutoff();
            final actualNights = checkin != null
                ? Time.nightsWithCutoff(checkin, checkout: effectiveCheckout)
                : expectedNights;

            final dbInstance = ref.watch(databaseProvider);
            final discount = widget.booking.discount;
            final discountType = widget.booking.discountType;
            final discountStartDate = _parseDateTime(widget.booking.discountStartDate);

            return StreamBuilder<List<BookingNight>>(
              stream:
                  (dbInstance.select(dbInstance.bookingNights)
                        ..where((n) => n.bookingLocalId.equals(widget.booking.id))
                        ..where((n) => n.deletedAt.isNull()))
                      .watch(),
              builder: (context, nightsSnap) {
                final allNights = nightsSnap.data ?? const <BookingNight>[];
                // استبعاد الليالي المشبوهة الملغاة من الحساب
                final nights = allNights.where((n) => !_cancelledSuspiciousNightIds.contains(n.id)).toList();
                // كشف الليالي المشبوهة (لعرض المؤشر)
                final suspiciousNights = _detectSuspiciousNights(allNights, widget.booking);
                final nightsCount = nights.isNotEmpty ? nights.length : actualNights;
                final nightTotal = nights.isNotEmpty
                    // ✅ إصلاح حرج: استخدام finalRate بدلاً من nightlyRate
                    // finalRate يتضمن تعديلات الأسعار (خصومات/إضافات)
                    // nightlyRate هو السعر الأساسي بدون تعديلات → يُسبب مبلغ خاطئ عند الخروج
                    ? nights.fold<double>(0, (sum, n) => sum + (n.finalRate > 0 ? n.finalRate : n.nightlyRate))
                    : (() {
                        final checkout = actualCheckout ?? DateTime.now();
                        if (discount > 0 && discountType == 'per_night' && checkin != null) {
                          final discountedNights = _countNightsWithDiscount(checkin, checkout, discountStartDate);
                          final fullNights = (actualNights - discountedNights).clamp(0, actualNights);
                          final discountedRate = (roomPrice - discount).clamp(0.0, roomPrice);
                          return (fullNights * roomPrice) + (discountedNights * discountedRate);
                        }
                        return actualNights * roomPrice;
                      })();

                final totalDue = discount > 0 && discountType == 'total'
                    ? (nightTotal - discount).clamp(0.0, nightTotal)
                    : nightTotal;

                return Padding(
>>>>>>> origin/refactor/clean-v2
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('معلومات الحجز', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text('النزيل: ${widget.booking.guestName}'),
                      Text(
                        'الهاتف: ${widget.booking.guestPhone.isEmpty ? 'غير متوفر' : widget.booking.guestPhone}',
                      ),
                      Text('رقم الغرفة: ${widget.booking.roomNumber}'),
                      Text('نوع الهوية: ${widget.booking.guestIdType}'),
                      if (widget.booking.guestIdNumber.isNotEmpty)
                        Text(
                          'رقم الهوية: ${widget.booking.guestIdNumber}',
                        ),
                      Text(
                        'الجنسية: ${widget.booking.guestNationality}',
                      ),
                      Text(
                        'تاريخ الدخول: ${widget.booking.checkinDate}',
                      ),
                      if (widget.booking.checkoutDate != null)
                        Text(
                          'تاريخ المغادرة المخطط: ${widget.booking.checkoutDate}',
                        ),
                      if (widget.booking.actualCheckout != null)
                        Text(
                          'تاريخ المغادرة الفعلي: ${widget.booking.actualCheckout}',
                        ),
                      Text('الليالي المتوقعة: $expectedNights'),
                      if (actualCheckout != null) Text('الليالي الفعلية: $nightsCount'),
                      // مؤشر إضافة ليالي بعد الساعة 14:00 للنزلاء الذين لم يسجلوا خروج
                      if (hasNotCheckedOut && nowIsAfterCutoff && actualNights > expectedNights)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade400),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
<<<<<<< HEAD
                              Icon(Icons.schedule, size: 16, color: Colors.orange.shade700),
                              const SizedBox(width: 6),
                              Text(
                                'تمت إضافة ${actualNights - expectedNights} ليلة بعد الساعة 14:00 (لم يسجل النزيل خروج)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.bold,
=======
                              Text('معلومات الحجز', style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 8),
                              DefaultTextStyle(
                                style: const TextStyle(fontSize: 13),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('النزيل: ${widget.booking.guestName}'),
                                    Text(
                                      'الهاتف: ${widget.booking.guestPhone.isEmpty ? 'غير متوفر' : widget.booking.guestPhone}',
                                    ),
                                    Text('رقم الغرفة: ${widget.booking.roomNumber}'),
                                    Text('نوع الهوية: ${widget.booking.guestIdType}'),
                                    if (widget.booking.guestIdNumber.isNotEmpty)
                                      Text('رقم الهوية: ${widget.booking.guestIdNumber}'),
                                    Text('الجنسية: ${widget.booking.guestNationality}'),
                                    Text('تاريخ الدخول: ${widget.booking.checkinDate}'),
                                    if (widget.booking.checkoutDate != null)
                                      Text('تاريخ المغادرة المخطط: ${widget.booking.checkoutDate}'),
                                    if (widget.booking.actualCheckout != null)
                                      Text('تاريخ المغادرة الفعلي: ${widget.booking.actualCheckout}'),
                                    Text('الليالي المتوقعة: $expectedNights'),
                                    if (actualCheckout != null) Text('الليالي الفعلية: $nightsCount'),
                                    // مؤشر إضافة ليالي بعد الساعة 14:00 للنزلاء الذين لم يسجلوا خروج
                                    if (hasNotCheckedOut && nowIsAfterCutoff && actualNights > expectedNights)
                                      Container(
                                        margin: const EdgeInsets.only(top: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.orange.shade400),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.schedule, size: 16, color: Colors.orange.shade700),
                                            const SizedBox(width: 6),
                                            Text(
                                              'تمت إضافة ${actualNights - expectedNights} ليلة بعد الساعة 14:00 (لم يسجل النزيل خروج)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.orange.shade700,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Text('سعر الليلة: ${CurrencyFormatter.formatAmount(roomPrice)}'),
                                    if (discount > 0)
                                      Text(
                                        'التخفيض: ${CurrencyFormatter.formatAmount(discount)}',
                                        style: const TextStyle(fontSize: 13, color: Colors.purple),
                                      ),
                                    Text(
                                      'المبلغ المستحق: ${CurrencyFormatter.formatAmount(totalDue)}',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    Text('الحالة: ${widget.booking.status}'),
                                    // ═══ مؤشر احترافي: ليالٍ مشبوهة بعد موعد المغادرة ═══
                                    if (suspiciousNights.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.red.shade300),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red.shade700),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    '${suspiciousNights.length} ${suspiciousNights.length == 1 ? "ليلة مشبوهة" : "ليالٍ مشبوهة"} بعد موعد المغادرة',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.red.shade700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'سيُطلب منك تأكيد احتسابها أو إلغائها عند تسجيل الخروج',
                                              style: TextStyle(fontSize: 11, color: Colors.red.shade600),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
>>>>>>> origin/refactor/clean-v2
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text(
                        'سعر الليلة: ${CurrencyFormatter.formatAmount(roomPrice)}',
                      ),
<<<<<<< HEAD
                      if (discount > 0)
                        Text(
                          'التخفيض: ${CurrencyFormatter.formatAmount(discount)}',
                          style: const TextStyle(color: Colors.purple),
                        ),
                      Text(
                        'المبلغ المستحق: ${CurrencyFormatter.formatAmount(totalDue)}',
=======
                      const SizedBox(height: 16),
                      StreamBuilder<List<Payment>>(
                        stream: paymentsRepo.paymentsByBooking(widget.booking.id),
                        builder: (context, snapshot) {
                          final payments = snapshot.data ?? const <Payment>[];
                          final totalPaid = payments
                              .where((p) => !p.isVoided)
                              .fold<double>(0, (sum, payment) => sum + payment.amount);
                          final remainingAmount = (totalDue - totalPaid).clamp(0, totalDue).toDouble();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('المدفوعات السابقة', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              Expanded(
                                flex: 2,
                                child: _CheckoutPaymentsList(
                                  payments: payments,
                                  totalDue: totalDue,
                                  onRefresh: _refreshBookingNights,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _isProcessing.value ? null : () => _addPayment(context),
                                      icon: const Icon(Icons.add_circle),
                                      label: const Text('إضافة دفعة جديدة'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  if (remainingAmount <= 0) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _isProcessing.value ? null : () => _completeCheckout(context),
                                        icon: const Icon(Icons.check_circle),
                                        label: const Text('إتمام الحجز'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ] else ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _isProcessing.value
                                            ? null
                                            : () =>
                                                  _handleCheckout(context, remainingAmount, totalDue, suspiciousNights),
                                        icon: const Icon(Icons.logout),
                                        label: const Text('تسجيل خروج'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          );
                        },
>>>>>>> origin/refactor/clean-v2
                      ),
                      Text('الحالة: ${widget.booking.status}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
<<<<<<< HEAD
                'المدفوعات السابقة',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 2,
                child: payments.isEmpty
                    ? const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('لا توجد مدفوعات سابقة', textAlign: TextAlign.center),
                        ),
                      )
                    : Column(
                        children: [
                          Card(
                            color: Colors.blue.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildSummaryRow('المبلغ المستحق', totalDue, Colors.blue),
                                  const SizedBox(height: 6),
                                  _buildSummaryRow('إجمالي المدفوع', totalPaid, Colors.green),
                                  const SizedBox(height: 6),
                                  _buildSummaryRow(
                                    'المتبقي',
                                    remainingAmount,
                                    remainingAmount <= 0 ? Colors.green : Colors.red,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _refreshBookingNights,
                              child: ListView.builder(
                                itemCount: payments.length,
                                itemBuilder: (context, index) {
                                  final payment = payments[index];
                                  return Card(
                                    child: ListTile(
                                      leading: Icon(
                                        payment.paymentMethod == 'تحويل' ? Icons.account_balance : Icons.money,
                                        color: payment.paymentMethod == 'تحويل' ? Colors.blue : Colors.green,
                                      ),
                                      title: Text(
                                        CurrencyFormatter.formatAmount(payment.amount),
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('طريقة الدفع: ${payment.paymentMethod}'),
                                          Text('النوع: ${payment.revenueType}'),
                                          Text('التاريخ: ${payment.paymentDate}'),
                                          if (payment.notes != null && payment.notes!.isNotEmpty)
                                            Text('ملاحظات: ${payment.notes}'),
                                        ],
                                      ),
                                      trailing: payment.roomNumber != null
                                          ? Chip(label: Text(payment.roomNumber!), backgroundColor: Colors.blue.shade50)
                                          : null,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () => _addPayment(context),
                      icon: const Icon(Icons.add_circle),
                      label: const Text('إضافة دفعة جديدة'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing || remainingAmount > 0 ? null : () => _completeCheckout(context),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('إتمام الحجز'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
=======
                'المبلغ المتبقي: ${CurrencyFormatter.formatAmount(remainingAmount)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop('none'), child: const Text('إلغاء')),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // يسار: تسجيل خروج بدون دين
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(ctx).pop('without_debt'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('تسجيل خروج'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                // يمين: خروج بدين
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(ctx).pop('with_debt'),
                    icon: const Icon(Icons.logout),
                    label: const Text('خروج بدين'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ],
>>>>>>> origin/refactor/clean-v2
        ),
      ),
    );
  }

<<<<<<< HEAD
  Widget _buildSummaryRow(String label, double amount, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        Text(
          CurrencyFormatter.formatAmount(amount),
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
=======
  /// تسجيل خروج النزيل مع خيار إنشاء دين
  Future<void> _completeCheckoutNow(
    BuildContext context,
    double remainingAmount,
    double totalDue, {
    required bool createDebt,
  }) async {
    _isProcessing.value = true;

    try {
      final bookingsRepo = ref.read(bookingsRepoProvider);
      final roomsRepo = ref.read(roomsRepoProvider);
      final db = ref.read(databaseProvider);

      final nowIso = Time.nowIso();
      final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
      final nowDate = DateTime.parse(nowIso);
      final actualNights = Time.nightsWithCutoff(checkin, checkout: nowDate);

      // ✅ إصلاح (2026-06-28 P0-1): تغليف كل عمليات DB في transaction موحد
      // لضمان atomicity — إما تنجح كلها أو تفشل كلها (لا تضارب بيانات).
      // العمليات: حذف الليالي + تحديث الحجز + تحديث الغرفة + إنشاء الدين
      final debtId = await db.transaction(() async {
        // 0. حذف الليالي المشبوهة الملغاة
        await _deleteCancelledNights();

        // 1. تحديث الحجز: مكتمل + تسجيل خروج
        await bookingsRepo.update(
          widget.booking.id,
          status: 'مكتمل',
          actualCheckout: nowIso,
          calculatedNights: actualNights,
        );

        // 2. تحديث حالة الغرفة
        await roomsRepo.refreshAllRoomOccupancy();

        // 3. إنشاء دين للمبلغ المتبقي (أو الإطلاق بدون دين)
        int? createdDebtId;
        if (createDebt) {
          final debtsRepo = ref.read(debtsRepoProvider);
          final checkoutDateStr = widget.booking.checkoutDate ?? nowIso;
          // ✅ إصلاح (2026-06-28 P0-3): totalAmount = remainingAmount (المتبقي فقط)
          // بدلاً من totalDue (المبلغ الكامل). الدين الجديد يمثل المبلغ غير المدفوع.
          createdDebtId = await debtsRepo.create(
            bookingLocalId: widget.booking.id,
            guestName: widget.booking.guestName,
            checkinDate: widget.booking.checkinDate,
            checkoutDate: checkoutDateStr,
            debtReason: 'مبلغ متبقي بعد تسجيل الخروج',
            totalAmount: remainingAmount, // ✅ المتبقي فقط
            paidAmount: 0, // ✅ لم يُدفع بعد
            paymentDate: nowIso,
            isSettled: false,
          );
        }
        return createdDebtId;
      });

      // ✅ إصلاح (2026-06-28 P1-4, P1-5): زيادة VC بعد الكتابة الناجحة
      // هذا يحمي التعديلات المحلية من التعارضات المتزامنة حتى قبل الـ push.
      // نستخدم widget.booking.localUuid لأنه الـ UUID المخزن في DB.
      await VectorClockHelper.bump(db, 'bookings', widget.booking.localUuid);
      if (debtId != null && debtId > 0) {
        // للدين الجديد، نحتاج لمعرفة localUuid — نقرأه من DB
        try {
          final debtRow = await (db.select(db.debts)..where((d) => d.id.equals(debtId))).getSingleOrNull();
          if (debtRow != null) {
            await VectorClockHelper.bump(db, 'debts', debtRow.localUuid);
          }
        } catch (_) {
          // فشل زيادة VC للدين ليس حرجاً — الـ push سيزيده لاحقاً
        }
      }

      markDataChanged();

      if (mounted) {
        final message = createDebt
            ? 'تم تسجيل الخروج وإضافة دين بقيمة ${CurrencyFormatter.formatAmount(remainingAmount)} إلى قائمة الديون'
            : 'تم تسجيل الخروج بدون إنشاء دين';
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: createDebt ? Colors.orange : Colors.grey,
            duration: const Duration(seconds: 3),
          ),
        );
        // ignore: use_build_context_synchronously
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        _isProcessing.value = false;
      }
    }
>>>>>>> origin/refactor/clean-v2
  }

  Future<void> _addPayment(BuildContext context) async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    String selectedMethod = 'نقدي';
    String selectedType = 'room';

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('إضافة دفعة جديدة'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
<<<<<<< HEAD
                    decoration: const InputDecoration(
                      labelText: 'المبلغ *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMethod,
                    style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyMedium?.color),
                    decoration: const InputDecoration(
                      labelText: 'طريقة الدفع',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'نقدي',
                        child: Text(
                          'نقدي',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'تحويل',
                        child: Text(
                          'تحويل بنكي',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => selectedMethod = value!,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyMedium?.color),
                    decoration: const InputDecoration(
                      labelText: 'نوع الإيراد',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'room',
                        child: Text(
                          'إيراد غرفة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'service',
                        child: Text(
                          'خدمات إضافية',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'deposit',
                        child: Text(
                          'عربون',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: Text(
                          'أخرى',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => selectedType = value!,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
=======
                    decoration: const InputDecoration(labelText: 'المبلغ *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMethod,
                    style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyMedium?.color),
                    decoration: const InputDecoration(labelText: 'طريقة الدفع', border: OutlineInputBorder()),
                    items: [
                      DropdownMenuItem(
                        value: 'نقدي',
                        child: Text(
                          'نقدي',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'تحويل',
                        child: Text(
                          'تحويل بنكي',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => selectedMethod = value!,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyMedium?.color),
                    decoration: const InputDecoration(labelText: 'نوع الإيراد', border: OutlineInputBorder()),
                    items: [
                      DropdownMenuItem(
                        value: 'room',
                        child: Text(
                          'إيراد غرفة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'service',
                        child: Text(
                          'خدمات إضافية',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'deposit',
                        child: Text(
                          'عربون',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: Text(
                          'أخرى',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => selectedType = value!,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)', border: OutlineInputBorder()),
                  ),
>>>>>>> origin/refactor/clean-v2
                ],
              ),
            ),
            actions: [
<<<<<<< HEAD
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('حفظ'),
              ),
=======
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('حفظ')),
>>>>>>> origin/refactor/clean-v2
            ],
          ),
        ),
      );

      if (result ?? false) {
        final parsedAmount = CurrencyFormatter.parseAmount(amountController.text);
        if (parsedAmount == null || parsedAmount <= 0) {
          // ignore: use_build_context_synchronously
<<<<<<< HEAD
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('يرجى إدخال مبلغ صحيح'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        if (parsedAmount % 1 != 0) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('المبلغ يجب أن يكون بدون كسور'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        final double amount = parsedAmount;

        setState(() => _isProcessing = true);

        try {
          final paymentsRepo = ref.read(paymentsRepoProvider);
          await paymentsRepo.create(
            bookingLocalId: widget.booking.id,
            roomNumber: widget.booking.roomNumber,
            amount: amount,
            paymentDate: Time.nowIso(),
            notes: notesController.text.isEmpty ? null : notesController.text,
            paymentMethod: selectedMethod,
            revenueType: selectedType,
          );
          markDataChanged();
          // ✅ مزامنة فورية بعد الحفظ
          unawaited(syncNow());

          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تم إضافة الدفعة بنجاح'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'إغلاق',
                textColor: Colors.white,
                onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              ),
            ),
          );
        } catch (e) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
          );
        } finally {
          if (mounted) setState(() => _isProcessing = false);
=======
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('يرجى إدخال مبلغ صحيح'), backgroundColor: Colors.red));
          return;
        }
        // ✅ إصلاح (2026-06-28 P2-7): إزالة فحص الكسور المكرر
        // inputFormatters: [FilteringTextInputFormatter.digitsOnly] يمنع
        // إدخال الكسور أصلاً، لذا فحص parsedAmount % 1 != 0 كان كوداً ميتاً.
        final double amount = parsedAmount;

        _isProcessing.value = true;

        try {
          final paymentsRepo = ref.read(paymentsRepoProvider);
          final paymentId = await paymentsRepo.create(
            bookingLocalId: widget.booking.id,
            roomNumber: widget.booking.roomNumber,
            amount: amount,
            paymentDate: Time.nowIso(),
            notes: notesController.text.isEmpty ? null : notesController.text,
            paymentMethod: selectedMethod,
            revenueType: selectedType,
          );

          // ✅ إصلاح (2026-06-28 P1-5): زيادة VC للدفعة الجديدة
          final db = ref.read(databaseProvider);
          if (paymentId > 0) {
            try {
              final paymentRow = await (db.select(db.payments)..where((p) => p.id.equals(paymentId))).getSingleOrNull();
              if (paymentRow != null) {
                await VectorClockHelper.bump(db, 'payments', paymentRow.localUuid);
              }
            } catch (_) {
              // فشل زيادة VC ليس حرجاً
            }
          }

          markDataChanged();

          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إضافة الدفعة بنجاح'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } catch (e) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red));
        } finally {
          if (mounted) _isProcessing.value = false;
>>>>>>> origin/refactor/clean-v2
        }
      }
    } finally {
      amountController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _completeCheckout(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد إتمام الحجز'),
          content: const Text(
            'هل أنت متأكد من إتمام هذا الحجز؟ سيتم تحديث حالة الحجز إلى "مكتمل" وحالة الغرفة إلى "شاغرة".',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('إتمام'),
            ),
          ],
        ),
      ),
    );

    if ((result ?? false) && mounted) {
      _isProcessing.value = true;

      try {
        final bookingsRepo = ref.read(bookingsRepoProvider);
        final roomsRepo = ref.read(roomsRepoProvider);

        // ✅ تحديث حالة الحجز + حالة الغرفة في معاملة واحدة
        final nowIso = Time.nowIso();
        final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
        final nowDate = DateTime.parse(nowIso);
        final actualNights = Time.nightsWithCutoff(checkin, checkout: nowDate);

        // استخدام refreshAllRoomOccupancy بدلاً من تحديث يدوي جزئي
        // هذا يضمن تناسق جميع حالات الغرف
        await bookingsRepo.update(
          widget.booking.id,
          status: 'مكتمل',
          actualCheckout: nowIso,
          calculatedNights: actualNights,
        );
        // تحديث حالة الغرفة إلى شاغرة عبر المستودع الموحد
        await roomsRepo.refreshAllRoomOccupancy();
        markDataChanged();
        // ✅ مزامنة فورية بعد الحفظ
        unawaited(syncNow());

        if (mounted) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إتمام الحجز بنجاح'),
              backgroundColor: Colors.green,
<<<<<<< HEAD
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'إغلاق',
                textColor: Colors.white,
                onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              ),
=======
              duration: Duration(seconds: 3),
>>>>>>> origin/refactor/clean-v2
            ),
          );
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red));
        }
      } finally {
        if (mounted) {
          _isProcessing.value = false;
        }
      }
    }
  }
}
<<<<<<< HEAD
=======

/// ═══════════════════════════════════════════════════════════════════
/// بطاقة ملخص الدفعات: تعرض المبلغ المستحق، إجمالي المدفوع، والمتبقي
/// ═══════════════════════════════════════════════════════════════════
///
/// Widget مستقل لتحسين الأداء — أي تغيير في totalPaid/remainingAmount
/// يُعيد بناء هذه البطاقة فقط بدون إعادة بناء القائمة بالكامل.
/// accepts القيم المحسوبة كمعاملات بُنائية (const constructor).
class _CheckoutSummaryCard extends StatelessWidget {
  const _CheckoutSummaryCard({required this.totalDue, required this.totalPaid, required this.remainingAmount});

  final double totalDue;
  final double totalPaid;
  final double remainingAmount;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSummaryRow('المبلغ المستحق', totalDue, Colors.blue),
            const SizedBox(height: 6),
            _buildSummaryRow('إجمالي المدفوع', totalPaid, Colors.green),
            const SizedBox(height: 6),
            _buildSummaryRow('المتبقي', remainingAmount, remainingAmount <= 0 ? Colors.green : Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
        ),
        Text(
          CurrencyFormatter.formatAmount(amount),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════
/// قائمة الدفعات السابقة + بطاقة الملخص
/// ═══════════════════════════════════════════════════════════════════
///
/// ConsumerWidget مستقل لتحسين الأداء — أي تغيير في تدفق الدفعات
/// يُعيد بناء هذا الـ widget فقط بدلاً من إعادة بناء الـ StreamBuilders
/// الأربعة المتداخلة في الشاشة الرئيسية.
///
/// يستخدم ref.watch(paymentsRepoProvider.select((repo) => repo)) للحصول
/// على مستودع الدفعات وعرض قائمة المدفوعات.
class _CheckoutPaymentsList extends ConsumerWidget {
  const _CheckoutPaymentsList({required this.payments, required this.totalDue, required this.onRefresh});

  final List<Payment> payments;
  final double totalDue;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (payments.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('لا توجد مدفوعات سابقة', textAlign: TextAlign.center),
        ),
      );
    }

    // ✅ استبعاد المدفوعات الملغاة
    final totalPaid = payments.where((p) => !p.isVoided).fold<double>(0, (sum, payment) => sum + payment.amount);
    final remainingAmount = (totalDue - totalPaid).clamp(0, totalDue).toDouble();

    return Column(
      children: [
        _CheckoutSummaryCard(totalDue: totalDue, totalPaid: totalPaid, remainingAmount: remainingAmount),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView.builder(
              itemCount: payments.length,
              itemBuilder: (context, index) {
                final payment = payments[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      payment.paymentMethod == 'تحويل' ? Icons.account_balance : Icons.money,
                      color: payment.paymentMethod == 'تحويل' ? Colors.blue : Colors.green,
                    ),
                    title: Text(
                      CurrencyFormatter.formatAmount(payment.amount),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    subtitle: DefaultTextStyle(
                      style: const TextStyle(fontSize: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('طريقة الدفع: ${payment.paymentMethod}'),
                          Text('النوع: ${payment.revenueType}'),
                          Text('التاريخ: ${payment.paymentDate}'),
                          if (payment.notes != null && payment.notes!.isNotEmpty) Text('ملاحظات: ${payment.notes}'),
                        ],
                      ),
                    ),
                    trailing: payment.roomNumber != null
                        ? Chip(label: Text(payment.roomNumber!), backgroundColor: Colors.blue.shade50)
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
>>>>>>> origin/refactor/clean-v2
