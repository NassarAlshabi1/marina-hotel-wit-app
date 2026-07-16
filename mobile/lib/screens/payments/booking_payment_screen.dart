// ignore_for_file: unused_element

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/app_scaffold.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../models/payment_models.dart';
import '../../providers/appwrite_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/repository_providers.dart';
import '../../services/booking_derived_fields_service.dart';
import '../../services/local_db.dart' as db;
import '../../services/providers.dart';
import '../../services/stay_balance_calculator.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_parser.dart';
import '../../utils/hotel_date_helper.dart';
import '../../utils/hotel_day_ticker.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/loading_snackbar.dart';
import '../../utils/time.dart';
import 'payment_history_screen.dart';

class BookingPaymentScreen extends ConsumerStatefulWidget {
  const BookingPaymentScreen({super.key, required this.booking});
  final db.Booking booking;

  @override
  ConsumerState<BookingPaymentScreen> createState() => _BookingPaymentScreenState();
}

class _BookingPaymentScreenState extends ConsumerState<BookingPaymentScreen>
    with SingleTickerProviderStateMixin, SyncOnExitMixin {
  @override
  String get screenId => 'booking_payment';
  late TabController _tabController;
  late TextEditingController _phoneController;
  final _currencyFmt = NumberFormat('#,##0', 'en_US');
  double _remainingAmount = 0;
  late String _currentGuestPhone;
  // ✅ أداء: ValueNotifier بدلاً من bool + setState — يمنع إعادة بناء الشاشة كاملة
  final _isSavingPaymentNotifier = ValueNotifier<bool>(false);
  bool get _isSavingPayment => _isSavingPaymentNotifier.value;
  set _isSavingPayment(bool v) => _isSavingPaymentNotifier.value = v;
  double _debtAmount = 0;
  // ✅ قائمة الديون غير المسددة لهذا الحجز (تُستخدم لزر خصم مبلغ من الدين)
  List<db.Debt> _unsettledDebts = [];
  StreamSubscription<void>? _hotelDayTickerSub;

  /// معرّفات الليالي المشبوهة (المضافة بعد موعد المغادرة المتوقع بسبب نسيان الموظف)
  /// عند الإلغاء تُحذف من قاعدة البيانات وتُستبعد من حساب المبلغ
  final Set<int> _cancelledSuspiciousNightIds = {};

  Payment _mapDbPaymentToUi(db.Payment p) {
    return Payment(
      id: p.localUuid,
      bookingId: widget.booking.localUuid,
      amount: p.amount,
      method: _mapDbMethodToUi(p.paymentMethod),
      status: PaymentStatus.completed,
      paymentDate: DateTime.tryParse(p.paymentDate) ?? DateTime.now(),
      notes: p.notes,
      receivedBy: 'admin',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  PaymentMethod _mapDbMethodToUi(String m) {
    switch (m) {
      case 'نقدي':
      case 'نقداً':
        return PaymentMethod.cash;
      case 'بطاقة':
      case 'بطاقة ائتمان':
        return PaymentMethod.card;
      case 'تحويل':
      case 'تحويل بنكي':
        return PaymentMethod.transfer;
      case 'شيك':
        return PaymentMethod.check;
      case 'تقسيط':
        return PaymentMethod.installment;
      default:
        return PaymentMethod.cash;
    }
  }

  String _mapUiMethodToDb(PaymentMethod m) {
    switch (m) {
      case PaymentMethod.cash:
        return 'نقدي';
      case PaymentMethod.card:
        return 'بطاقة';
      case PaymentMethod.transfer:
        return 'تحويل';
      case PaymentMethod.check:
        return 'شيك';
      case PaymentMethod.installment:
        return 'تقسيط';
    }
  }

  /// تنظيف وتنسيق رقم الهاتف — البادئة الافتراضية 967 (اليمن)
  String _cleanAndFormatPhone(String phone) {
    var digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) {
      return '';
    }
    // إزالة 00 الدولية
    if (digitsOnly.startsWith('00')) {
      digitsOnly = digitsOnly.substring(2);
    }
    // سبق بإضافة +967
    if (digitsOnly.startsWith('967')) {
      return digitsOnly;
    }
    // 07xx → 967xx (محلي يمني)
    if (digitsOnly.startsWith('07')) {
      digitsOnly = '967${digitsOnly.substring(1)}';
    }
    // 7xx و 9 أرقام → 967xx (محلي يمني بدون صفر)
    else if (digitsOnly.startsWith('7') && digitsOnly.length == 9) {
      digitsOnly = '967$digitsOnly';
    }
    // سعودي: 5xx و 9 أرقام → 966xx
    else if (digitsOnly.startsWith('5') && digitsOnly.length == 9) {
      digitsOnly = '966$digitsOnly';
    }
    // سبق بإضافة +966
    else if (digitsOnly.startsWith('966')) {
      return digitsOnly;
    }
    // البادئة الافتراضية: أي رقم لا يبدأ بمعرف دولة → 967
    else if (digitsOnly.length <= 10 && !digitsOnly.startsWith('+')) {
      digitsOnly = '967$digitsOnly';
    }
    return digitsOnly;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _phoneController = TextEditingController(text: widget.booking.guestPhone);
    _currentGuestPhone = widget.booking.guestPhone;
    _checkForDebts();
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

  Future<void> _checkForDebts() async {
    final debtsRepo = ref.read(debtsRepoProvider);
    final debts = await debtsRepo.listByBookingLocalId(widget.booking.id);
    if (mounted) {
      double totalDebt = 0;
      // ✅ حفظ الديون غير المسددة لاستخدامها في زر خصم مبلغ من الدين
      final unsettled = <db.Debt>[];
      for (final d in debts) {
        if (d.isSettled == 0 && d.remainingAmount > 0) {
          totalDebt += d.remainingAmount;
          unsettled.add(d);
        }
      }
      setState(() {
        _debtAmount = totalDebt;
        _unsettledDebts = unsettled;
      });
    }
  }

  Future<void> _refreshBookingNights() async {
    final db = ref.read(databaseProvider);
    final derivedService = BookingDerivedFieldsService(db);
    await derivedService.refreshForBookingId(widget.booking.id);
  }

  DateTime? _parseDateTime(String? value) => DateParser.parse(value);

  /// ═══════════════════════════════════════════════════════════════════
  /// كشف الليالي المشبوهة — ليالٍ أُضيفت تلقائياً بعد موعد المغادرة المتوقع
  /// ═══════════════════════════════════════════════════════════════════
  ///
  /// المنطق:
  /// 1. نحسب "آخر يوم إقامة متوقع" = checkoutDate أو (checkinDate + expectedNights)
  /// 2. أي ليلة بـ hotelDayKey يقع تاريخ بدايتها بعد هذا اليوم = مشبوهة
  /// 3. سبب الاشتباه: النزيل غادر فعلياً لكن الموظف نسي تسجيل الخروج
  ///    فأضاف النظام ليلة تلقائية بعد تجاوز الساعة 14:00
  List<db.BookingNight> _detectSuspiciousNights(List<db.BookingNight> nights, db.Booking booking) {
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
    final suspicious = <db.BookingNight>[];
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
  Future<bool> _showSuspiciousNightsDialog(List<db.BookingNight> suspiciousNights) async {
    final totalSuspiciousAmount = suspiciousNights.fold<double>(
      0,
      (sum, n) => sum + (n.finalRate > 0 ? n.finalRate : n.nightlyRate),
    );

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
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
      if (!mounted) return true;
      setState(() {
        _cancelledSuspiciousNightIds.addAll(suspiciousNights.map((n) => n.id));
      });
      return true; // تم المعالجة
    }
    // keep_nights أو إغلاق → نحتسب الليالي
    return true;
  }

  /// حذف الليالي الملغاة من قاعدة البيانات عند تسجيل الخروج
  Future<void> _deleteCancelledNights() async {
    if (_cancelledSuspiciousNightIds.isEmpty) return;
    final dbInstance = ref.read(databaseProvider);
    for (final nightId in _cancelledSuspiciousNightIds) {
      await (dbInstance.delete(dbInstance.bookingNights)..where((n) => n.id.equals(nightId))).go();
    }
  }

  int _countNightsWithDiscount(DateTime checkin, DateTime checkout, DateTime? discountStartDate) {
    if (discountStartDate == null) {
      return Time.nightsWithCutoff(checkin, checkout: checkout);
    }
    final discountDayStart = DateTime(discountStartDate.year, discountStartDate.month, discountStartDate.day, 14);
    final effectiveStart = discountDayStart.isAfter(checkin) ? discountDayStart : checkin;
    if (!checkout.isAfter(effectiveStart)) {
      return 0;
    }
    return Time.nightsWithCutoff(effectiveStart, checkout: checkout);
  }

  @override
  void dispose() {
    _hotelDayTickerSub?.cancel();
    _tabController.dispose();
    _phoneController.dispose();
    _isSavingPaymentNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roomsRepo = ref.watch(roomsRepoProvider);
    final paymentsRepo = ref.watch(paymentsRepoProvider);

    return PopScope(
      canPop: !_isSavingPayment,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const PopScope(
            canPop: false,
            child: AlertDialog(
              title: Row(
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('جاري الحفظ'),
                ],
              ),
              content: Text('يرجى الانتظار حتى يتم حفظ الدفعة...'),
            ),
          ),
        );
      },
      child: AppScaffold(
        title: 'معالجة المدفوعات',
        actions: [
          IconButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (context) => PaymentHistoryScreen(bookingId: widget.booking.localUuid)),
            ),
            icon: const Icon(Icons.history),
            tooltip: 'سجل المدفوعات',
          ),
        ],
        body: RepaintBoundary(
          child: StreamBuilder<db.Booking?>(
            stream: ref.watch(bookingsRepoProvider).watchOne(widget.booking.id),
            builder: (context, bookingSnap) {
              final booking = bookingSnap.data ?? widget.booking;
              return StreamBuilder<db.Room?>(
                stream: roomsRepo.watchByNumber(booking.roomNumber),
                builder: (context, roomSnap) {
                  final double roomRate = roomSnap.data?.price ?? 0;
                  final checkin = DateTime.tryParse(booking.checkinDate);
                  if (checkin == null) {
                    return const Center(child: Text('خطأ: تاريخ الوصول للحجز غير صالح.'));
                  }
                  final plannedCheckout = booking.checkoutDate != null
                      ? DateTime.tryParse(booking.checkoutDate!)
                      : null;
                  final actualCheckout = booking.actualCheckout != null
                      ? DateTime.tryParse(booking.actualCheckout!)
                      : null;
                  // Use the pre-calculated expectedNights from the database, which is now dynamic
                  // for active bookings via BookingDerivedFieldsService.
                  final expectedNights = booking.expectedNights;

                  // actualNights represents the current stay duration including the 14:00 cutoff logic
                  final actualNights = booking.calculatedNights;
                  final hasNotCheckedOut = actualCheckout == null;
                  final nowIsAfterCutoff = HotelDateHelper.isNowAfterCutoff();

                  final dbInstance = ref.watch(databaseProvider);
                  final discount = booking.discount;
                  final discountType = booking.discountType;
                  final discountStartDate = _parseDateTime(booking.discountStartDate);

                  // ─── StreamBuilder لتعديلات الأسعار (booking_price_adjustments) ───
                  return StreamBuilder<List<db.BookingPriceAdjustment>>(
                    stream:
                        (dbInstance.select(dbInstance.bookingPriceAdjustments)
                              ..where(
                                (a) =>
                                    (a.bookingLocalId.equals(booking.id) |
                                    a.bookingLocalUuid.equals(booking.localUuid)),
                              )
                              ..where((a) => a.isActive.equals(true))
                              ..where((a) => a.deletedAt.isNull()))
                            .watch(),
                    builder: (context, adjSnap) {
                      final rawAdjustments = adjSnap.data ?? const <db.BookingPriceAdjustment>[];
                      final filteredAdjustments = StayBalanceCalculator.filterActiveAdjustments(
                        booking,
                        rawAdjustments,
                      );

                      return StreamBuilder<List<db.BookingNight>>(
                        stream:
                            (dbInstance.select(dbInstance.bookingNights)
                                  ..where((n) => n.bookingLocalId.equals(booking.id))
                                  ..where((n) => n.deletedAt.isNull()))
                                .watch(),
                        builder: (context, nightsSnap) {
                          final nights = (nightsSnap.data ?? const <db.BookingNight>[])
                              // استبعاد الليالي المشبوهة الملغاة من الحساب
                              .where((n) => !_cancelledSuspiciousNightIds.contains(n.id))
                              .toList();
                          final nightsCount = nights.isNotEmpty ? nights.length : actualNights;
                          final double nightTotal = nights.isNotEmpty
                              ? nights.fold<double>(
                                  0,
                                  (sum, n) => sum + (n.finalRate > 0 ? n.finalRate : n.nightlyRate),
                                )
                              : (() {
                                  final checkout = actualCheckout ?? DateTime.now();
                                  if (discount > 0 && discountType == 'per_night') {
                                    final discountedNights = _countNightsWithDiscount(
                                      checkin,
                                      checkout,
                                      discountStartDate,
                                    );
                                    final fullNightsRaw = actualNights - discountedNights;
                                    final fullNights = fullNightsRaw < 0 ? 0 : fullNightsRaw;
                                    final discountedRate = (roomRate - discount).clamp(0, roomRate).toDouble();
                                    return (fullNights * roomRate) + (discountedNights * discountedRate);
                                  }
                                  return actualNights * roomRate;
                                })();

                          final double totalAmount = discount > 0 && discountType == 'total'
                              ? (nightTotal - discount).clamp(0, nightTotal).toDouble()
                              : nightTotal;

                          int discountedNights = 0;
                          int surchargeNights = 0;
                          int normalNights = nightsCount;
                          double totalDiscount = 0;
                          double totalSurcharge = 0;

                          if (nights.isNotEmpty) {
                            // حماية: التخفيض/المزادة يُحسب فقط إذا كانت adjustment != 0
                            // لتجنب عرض تخفيض وهمي من بيانات booking_nights قديمة/فاسدة
                            discountedNights = nights.where((n) => n.adjustment < 0).length;
                            surchargeNights = nights.where((n) => n.adjustment > 0).length;
                            normalNights = nightsCount - discountedNights - surchargeNights;
                            if (normalNights < 0) {
                              normalNights = 0;
                            }
                            totalDiscount = nights.fold<double>(
                              0,
                              (sum, n) => sum + (n.adjustment < 0 ? -n.adjustment : 0),
                            );
                            totalSurcharge = nights.fold<double>(
                              0,
                              (sum, n) => sum + (n.adjustment > 0 ? n.adjustment : 0),
                            );
                            // ─── حماية متعددة الطبقات ضد التخفيض الوهمي ───
                            if (discount <= 0 && totalDiscount > 0) {
                              // ① إذا كانت جميع baseRate == 0 → بيانات غير مكتملة
                              final hasValidBaseRates = nights.any((n) => n.baseRate > 0);
                              if (!hasValidBaseRates) {
                                totalDiscount = 0;
                                discountedNights = 0;
                                normalNights = nightsCount;
                              } else {
                                // ② البيانات مكتملة لكن discount = 0 → التخفيض في booking_nights
                                //    قادم من سجلات booking_price_adjustments يتيمة.
                                //    تحقق أن finalRate == baseRate (بدون تعديل فعلي):
                                final allRatesMatchBase = nights.every((n) => (n.finalRate - n.baseRate).abs() < 0.01);
                                if (allRatesMatchBase) {
                                  // finalRate يطابق baseRate → لا يوجد تخفيض حقيقي
                                  // booking_nights.adjustment قديم/فاسد
                                  totalDiscount = 0;
                                  discountedNights = 0;
                                  normalNights = nightsCount;
                                }
                              }
                            }
                          } else if (discount > 0 && discountType == 'per_night') {
                            final checkout = actualCheckout ?? DateTime.now();
                            discountedNights = _countNightsWithDiscount(checkin, checkout, discountStartDate);
                            normalNights = nightsCount - discountedNights;
                            if (normalNights < 0) {
                              normalNights = 0;
                            }
                            totalDiscount = discountedNights * discount;
                          } else if (discount > 0 && discountType == 'total') {
                            totalDiscount = discount;
                          }

                          return StreamBuilder<List<db.Payment>>(
                            stream: paymentsRepo.paymentsByBooking(booking.id),
                            builder: (context, paySnap) {
                              final dbPayments = paySnap.data ?? const <db.Payment>[];
                              // ✅ استبعاد المدفوعات الملغاة من حساب الإجمالي المدفوع
                              final paidAmount = dbPayments
                                  .where((p) => !p.isVoided)
                                  .fold<double>(0, (s, p) => s + p.amount);
                              // حساب المدفوعات في اليوم الفندقي الحالي لهذا الحجز
                              final hotelDay = HotelTimeEngine.getHotelDayKey();
                              final todayPaidAmount = dbPayments
                                  .where(
                                    (p) =>
                                        !p.isVoided &&
                                        (p.hotelDayKey == hotelDay ||
                                            (p.hotelDayKey == null && p.paymentDate.startsWith(hotelDay))),
                                  )
                                  .fold<double>(0, (s, p) => s + p.amount);
                              double remainingAmount = totalAmount - paidAmount;
                              if (remainingAmount < 0) {
                                remainingAmount = 0;
                              }
                              _remainingAmount = remainingAmount;
                              final uiPayments = dbPayments.map(_mapDbPaymentToUi).toList();
                              final summary = BookingPaymentSummary(
                                bookingId: booking.localUuid,
                                totalAmount: totalAmount,
                                paidAmount: paidAmount,
                                remainingAmount: remainingAmount,
                                payments: uiPayments,
                                overallStatus: remainingAmount <= 0 ? PaymentStatus.completed : PaymentStatus.pending,
                              );

                              return Column(
                                children: [
                                  _buildPaymentSummaryCard(
                                    summary,
                                    liveBooking: booking,
                                    roomRate: roomRate,
                                    priceAdjustments: filteredAdjustments,
                                    expectedNights: expectedNights,
                                    actualNights: nightsCount,
                                    checkin: checkin,
                                    plannedCheckout: plannedCheckout,
                                    actualCheckout: actualCheckout,
                                    discount: discount,
                                    normalNights: normalNights,
                                    discountedNights: discountedNights,
                                    surchargeNights: surchargeNights,
                                    totalDiscount: totalDiscount,
                                    totalSurcharge: totalSurcharge,
                                    hasNotCheckedOut: hasNotCheckedOut,
                                    nowIsAfterCutoff: nowIsAfterCutoff,
                                    actualNightsDynamic: actualNights,
                                    todayPaidAmount: todayPaidAmount,
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    child: TabBar(
                                      controller: _tabController,
                                      indicator: BoxDecoration(
                                        borderRadius: BorderRadius.circular(25),
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      indicatorSize: TabBarIndicatorSize.tab,
                                      labelColor: Theme.of(context).colorScheme.onPrimary,
                                      unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                                      labelStyle: const TextStyle(fontSize: 13),
                                      unselectedLabelStyle: const TextStyle(fontSize: 13),
                                      dividerColor: Colors.transparent,
                                      tabs: const [
                                        Tab(text: 'دفعة جديدة'),
                                        Tab(text: 'الإجراءات'),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: TabBarView(
                                      controller: _tabController,
                                      children: [
                                        _buildNewPaymentTab(
                                          summary,
                                          nights: nights,
                                          remainingAmount: remainingAmount,
                                          roomRate: roomRate,
                                        ),
                                        _buildActionsTab(summary, booking: booking, nights: nights),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    }, // نهاية StreamBuilder لتعديلات الأسعار
                  );
                },
              );
            },
          ),
        ), // RepaintBoundary
      ),
    );
  }

  Widget _buildPaymentSummaryCard(
    BookingPaymentSummary summary, {
    db.Booking? liveBooking,
    double? roomRate,
    List<db.BookingPriceAdjustment>? priceAdjustments,
    required int expectedNights,
    required int actualNights,
    required DateTime checkin,
    DateTime? plannedCheckout,
    DateTime? actualCheckout,
    double discount = 0,
    int normalNights = 0,
    int discountedNights = 0,
    int surchargeNights = 0,
    double totalDiscount = 0,
    double totalSurcharge = 0,
    bool hasNotCheckedOut = false,
    bool nowIsAfterCutoff = false,
    int actualNightsDynamic = 0,
    double todayPaidAmount = 0,
  }) {
    final progressPercentage = summary.paidPercentage / 100;
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'en');
    final checkinText = dateFmt.format(checkin);
    final plannedText = plannedCheckout != null ? dateFmt.format(plannedCheckout) : null;
    final actualText = actualCheckout != null ? dateFmt.format(actualCheckout) : null;
    final hasPhone = _currentGuestPhone.isNotEmpty;
    final identityLine = widget.booking.guestIdNumber.isEmpty
        ? widget.booking.guestIdType
        : '${widget.booking.guestIdType} • ${widget.booking.guestIdNumber}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            if (summary.isFullyPaid) Colors.green.shade50 else Colors.blue.shade50,
            if (summary.isFullyPaid) Colors.green.shade100 else Colors.blue.shade100,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: summary.isFullyPaid ? Colors.green.shade200 : Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.blue,
                child: Text(
                  widget.booking.roomNumber,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.booking.guestName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(
                      'غرفة ${widget.booking.roomNumber}${hasPhone ? ' • $_currentGuestPhone' : ''}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    Text(identityLine, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      'الجنسية: ${widget.booking.guestNationality}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text('الوصول: $checkinText', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    if (plannedText != null)
                      Text('المغادرة المخطط: $plannedText', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    // ─── تاريخ المغادرة التلقائي (محسوب من المدفوعات التراكمية) ───
                    Builder(
                      builder: (context) {
                        final balanceResult = StayBalanceCalculator.calculate(
                          liveBooking ?? widget.booking,
                          roomRate: roomRate,
                          priceAdjustments: priceAdjustments,
                        );
                        if (!balanceResult.hasPayments) {
                          return const SizedBox.shrink();
                        }
                        final autoFmt = DateFormat('dd/MM/yyyy', 'en');
                        final autoStr = autoFmt.format(balanceResult.autoCheckoutDate);
                        final extra = balanceResult.isAutoExtended
                            ? ' (+${balanceResult.extraNightsBeyondManual})'
                            : '';
                        return Text(
                          'المغادرة التلقائية: $autoStr (${balanceResult.totalPaidNights} ليلة مدفوعة)$extra',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        );
                      },
                    ),
                    if (actualText != null)
                      Text('المغادرة الفعلي: $actualText', style: const TextStyle(fontSize: 11, color: Colors.green)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: summary.isFullyPaid
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: summary.isFullyPaid ? Colors.green : Colors.orange),
                ),
                child: Text(
                  summary.isFullyPaid ? 'مكتمل الدفع' : 'دفع جزئي',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: summary.isFullyPaid ? Colors.green : Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildDetailChip(
                context,
                icon: Icons.attach_money,
                label: 'سعر الليلة',
                value: _currencyFmt.format(roomRate),
              ),
              // _buildDetailChip(
              //   context,
              //   icon: Icons.nightlight_round,
              //   label: 'الليالي المتوقعة',
              //   value: expectedNights.toString(),
              // ),
              _buildDetailChip(
                context,
                icon: Icons.task_alt,
                label: 'الليالي الفعلية',
                value: actualNights.toString(),
                color: actualNights > expectedNights ? Colors.orange : Colors.green,
              ),
              // مؤشر إضافة ليلة بعد الساعة 14:00 للنزلاء الذين لم يسجلوا خروج
              if (hasNotCheckedOut && nowIsAfterCutoff && actualNightsDynamic > expectedNights)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade400),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule, size: 12, color: Colors.orange.shade700),
                      const SizedBox(width: 3),
                      Text(
                        '+${actualNightsDynamic - expectedNights} ليلة بعد 14:00',
                        style: TextStyle(fontSize: 9, color: Colors.orange.shade700, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              if (_debtAmount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning, size: 12, color: Colors.red.shade700),
                      const SizedBox(width: 3),
                      Text(
                        'يوجد دين ${_currencyFmt.format(_debtAmount)}',
                        style: TextStyle(fontSize: 9, color: Colors.red.shade700, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              if (discount > 0)
                _buildDetailChip(
                  context,
                  icon: Icons.discount,
                  label: 'التخفيض',
                  value: _currencyFmt.format(discount),
                  color: Colors.purple,
                ),
              if (normalNights > 0)
                _buildDetailChip(
                  context,
                  icon: Icons.nights_stay,
                  label: 'ليالي عادية',
                  value: normalNights.toString(),
                  color: Colors.blueGrey,
                ),
              if (discountedNights > 0)
                _buildDetailChip(
                  context,
                  icon: Icons.trending_down,
                  label: 'ليالي مخفضة',
                  value: '$discountedNights (-${_currencyFmt.format(totalDiscount)})',
                  color: Colors.purple,
                ),
              if (surchargeNights > 0)
                _buildDetailChip(
                  context,
                  icon: Icons.trending_up,
                  label: 'ليالي مزادة',
                  value: '$surchargeNights (+${_currencyFmt.format(totalSurcharge)})',
                  color: Colors.teal,
                ),
            ],
          ),
          const SizedBox(height: 1),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('تقدم الدفع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9)),
                  Text(
                    '${summary.paidPercentage.toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressPercentage,
                  minHeight: 2,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(summary.isFullyPaid ? Colors.green : Colors.blue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Row(
            children: [
              Expanded(child: _buildAmountChip('الإجمالي', summary.totalAmount, Colors.blue)),
              const SizedBox(width: 3),
              Expanded(child: _buildAmountChip('المدفوع', summary.paidAmount, Colors.green)),
              const SizedBox(width: 3),
              Expanded(child: _buildAmountChip('المتبقي', summary.remainingAmount, Colors.red)),
              const SizedBox(width: 3),
              Expanded(child: _buildAmountChip('مدفوع اليوم', todayPaidAmount, Colors.indigo)),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showPaymentDialog(PaymentMethod.cash, null, 'رصيد تراكمي للنزيل', true),
              icon: const Icon(Icons.account_balance_wallet, size: 12),
              label: const Text('إضافة دفعة رصيد تراكمي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountChip(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            _currencyFmt.format(amount),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    final chipColor = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: chipColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: chipColor, fontWeight: FontWeight.bold, fontSize: 10),
          ),
          const SizedBox(width: 2),
          Text(value, style: TextStyle(color: chipColor, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildNewPaymentTab(
    BookingPaymentSummary summary, {
    List<db.BookingNight> nights = const [],
    double remainingAmount = 0,
    double roomRate = 0,
  }) {
    if (summary.isFullyPaid) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 80, color: Colors.green),
            SizedBox(height: 16),
            Text('تم سداد المبلغ كاملاً', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('يمكنك الآن تسجيل مغادرة العميل', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshBookingNights,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('إضافة دفعة جديدة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            // نموذج إضافة الدفعة
            _buildPaymentForm(summary, nights: nights, remainingAmount: remainingAmount, roomRate: roomRate),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentForm(
    BookingPaymentSummary summary, {
    List<db.BookingNight> nights = const [],
    double remainingAmount = 0,
    double roomRate = 0,
  }) {
    final remaining = summary.remainingAmount.round().abs();
    return Column(
      children: [
        // حقل رقم الهاتف مخفي - للاستخدام الداخلي فقط
        Visibility(
          visible: false,
          maintainState: true,
          child: TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'رقم هاتف النزيل', border: OutlineInputBorder()),
            textDirection: ui.TextDirection.ltr,
          ),
        ),
        Builder(
          builder: (context) {
            final width = MediaQuery.sizeOf(context).width;
            final crossAxisCount = width < 320 ? 1 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 3.2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: 2,
              itemBuilder: (context, index) {
                final methods = [PaymentMethod.cash, PaymentMethod.transfer];
                final method = methods[index];
                return _buildPaymentMethodCard(method);
              },
            );
          },
        ),
        const SizedBox(height: 10),
        const Align(
          alignment: Alignment.centerRight,
          child: Text('دفعات سريعة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildQuickPaymentButton('25%', (remaining * 25 / 100).round(), summary)),
            const SizedBox(width: 6),
            Expanded(child: _buildQuickPaymentButton('50%', (remaining * 50 / 100).round(), summary)),
            const SizedBox(width: 6),
            Expanded(child: _buildQuickPaymentButton('75%', (remaining * 75 / 100).round(), summary)),
            const SizedBox(width: 6),
            Expanded(child: _buildQuickPaymentButton('100%', remaining, summary)),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentMethodCard(PaymentMethod method) {
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: () => _showPaymentDialog(method),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: method.color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(method.icon, color: method.color, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  method.displayName,
                  style: TextStyle(fontWeight: FontWeight.bold, color: method.color, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickPaymentButton(String label, int amount, BookingPaymentSummary summary) {
    return ElevatedButton(
      onPressed: amount > 0 ? () => _showPaymentDialog(PaymentMethod.cash, amount) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
          Text(_currencyFmt.format(amount), style: const TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildActionsTab(
    BookingPaymentSummary summary, {
    required db.Booking booking,
    required List<db.BookingNight> nights,
  }) {
    // كشف الليالي المشبوهة (لعرض مؤشر على زر تسجيل المغادرة)
    final suspiciousNights = _detectSuspiciousNights(nights, booking);
    final hasSuspicious = suspiciousNights.isNotEmpty;
    final actions = <Widget>[
      _buildActionCard(
        'عرض الفاتورة الشاملة',
        'عرض وطباعة الفاتورة التفصيلية',
        Icons.receipt_long,
        Colors.teal,
        () => _generateInvoice(summary),
      ),
      _buildActionCard(
        'سجل المدفوعات',
        'عرض تاريخ جميع المدفوعات',
        Icons.history,
        Colors.purple,
        () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (context) => PaymentHistoryScreen(bookingId: widget.booking.localUuid)),
        ),
      ),
      _buildActionCard(
        'تسجيل المغادرة',
        hasSuspicious
            ? 'تنبيه: ${suspiciousNights.length} ${suspiciousNights.length == 1 ? "ليلة مشبوهة" : "ليالٍ مشبوهة"} بعد المغادرة!'
            : summary.isFullyPaid
            ? 'تسجيل مغادرة العميل'
            : 'تحذير: يوجد مبلغ متبقي!',
        Icons.logout,
        hasSuspicious ? Colors.orange : (summary.isFullyPaid ? Colors.green : Colors.red),
        () => _showCheckoutConfirmation(summary, booking: booking, nights: nights),
      ),
      _buildActionCard(
        'مغادرة مبكرة / مردود',
        'حساب المردود عند مغادرة قبل الموعد',
        Icons.currency_exchange,
        Colors.amber.shade700,
        () => _showEarlyCheckoutDialog(summary),
      ),
      _buildActionCard(
        'إلغاء يوم إضافي',
        'إلغاء دفعة اليوم الفندقي المحتسبة بالخطأ',
        Icons.remove_circle_outline,
        Colors.red.shade700,
        () => _showCancelTodayPaymentDialog(summary),
      ),
      _buildActionCard(
        'إرسال كشف حساب',
        'إرسال ملخص المدفوعات للعميل',
        Icons.send,
        Colors.orange,
        () => _sendAccountStatement(summary),
      ),
    ];

    // ✅ رسالة تحذير المبلغ المتبقي + زر إنشاء دين + زر خصم من الليالي
    final hasRemainingBalance = summary.remainingAmount > 0;
    // ✅ يوجد دين سابق غير مسدّد → نعرضه في التنبيه
    final hasUnsettledDebt = _debtAmount > 0 && _unsettledDebts.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ تنبيه مدمج (compact): النزيل عليه مبلغ متبقي + أزرار إجراءات
          if (hasRemainingBalance || hasUnsettledDebt) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: hasUnsettledDebt ? Colors.red.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: hasUnsettledDebt ? Colors.red.shade300 : Colors.orange.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    hasUnsettledDebt ? Icons.error_outline : Icons.warning_amber_rounded,
                    color: hasUnsettledDebt ? Colors.red.shade700 : Colors.orange.shade700,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hasUnsettledDebt
                          ? 'دين سابق: ${_currencyFmt.format(_debtAmount)} • متبقي: ${_currencyFmt.format(summary.remainingAmount)}'
                          : 'متبقي: ${_currencyFmt.format(summary.remainingAmount)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: hasUnsettledDebt ? Colors.red.shade900 : Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ✅ أزرار الإجراءات في صف واحد (compact)
            Row(
              children: [
                // زر إنشاء دين بالمبلغ المتبقي (برتقالي)
                if (hasRemainingBalance)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ElevatedButton.icon(
                        onPressed: () => _createDebtFromRemainingBalance(summary, booking),
                        icon: const Icon(Icons.add_circle, size: 14),
                        label: const Text('إنشاء دين', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ),
                // ✅ زر خصم مبلغ من الليالي الفعلية (أخضر) — للمدير فقط
                // صلاحية الخصم محصورة على admin أو من يملك 'payments.discount'
                if (ref.watch(authProvider).currentUser?.isAdmin ?? false) ...[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: ElevatedButton.icon(
                        onPressed: () => _showDiscountAmountDialog(summary, booking),
                        icon: const Icon(Icons.discount, size: 14),
                        label: const Text('خصم مبلغ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // ✅ زر معطّل للمستخدمين العاديين (يُظهر رسالة عند الضغط)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('⚠️ صلاحية الخصم متاحة للمدير فقط'),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.lock_outline, size: 14),
                        label: const Text('خصم (مقيد)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade400,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
          ],
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: actions,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('معلومات الحجز', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildInfoRow('رقم الحجز', widget.booking.localUuid),
                  _buildInfoRow('تاريخ الوصول', widget.booking.checkinDate.split(' ')[0]),
                  if (widget.booking.checkoutDate != null)
                    _buildInfoRow('تاريخ المغادرة', widget.booking.checkoutDate!.split(' ')[0]),
                  _buildInfoRow('الحالة', widget.booking.status),
                  if (widget.booking.notes != null && widget.booking.notes!.isNotEmpty)
                    _buildInfoRow('ملاحظات', widget.booking.notes!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color, size: 15),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(fontSize: 8, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog(
    PaymentMethod method, [
    int? presetAmount,
    String? presetNotes,
    bool isPendingBalance = false,
  ]) {
    final amountController = TextEditingController(text: presetAmount != null ? presetAmount.toString() : '');
    final notesController = TextEditingController(text: presetNotes ?? '');
    final referenceController = TextEditingController();
    final cardDigitsController = TextEditingController();
    final bankController = TextEditingController();

    // ✅ إصلاح تسرب ذاكرة: استخدام then للتأكد من dispose بعد إغلاق الحوار
    showDialog<void>(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(method.icon, color: method.color),
              const SizedBox(width: 8),
              Text('دفع ${method.displayName}'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(labelText: 'المبلغ*', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+'))],
                  ),

                  const SizedBox(height: 12),

                  // حقول إضافية حسب طريقة الدفع
                  if (method == PaymentMethod.card) ...[
                    TextField(
                      controller: cardDigitsController,
                      decoration: const InputDecoration(
                        labelText: 'آخر 4 أرقام من البطاقة',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (method == PaymentMethod.transfer) ...[
                    TextField(
                      controller: bankController,
                      decoration: const InputDecoration(labelText: 'اسم البنك', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (method == PaymentMethod.transfer || method == PaymentMethod.check) ...[
                    TextField(
                      controller: referenceController,
                      decoration: const InputDecoration(labelText: 'رقم المرجع/الشيك', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)', border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: _isSavingPayment
                  ? null
                  : () => _processPayment(
                      method,
                      amountController.text,
                      notesController.text,
                      referenceController.text,
                      cardDigitsController.text,
                      bankController.text,
                      isPendingBalance: isPendingBalance,
                    ),
              child: _isSavingPayment
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('تسجيل الدفعة'),
            ),
          ],
        ),
      ),
    ).then((_) {
      // ✅ إصلاح تسرب ذاكرة: dispose المتحكمات بعد إغلاق الحوار
      amountController.dispose();
      notesController.dispose();
      referenceController.dispose();
      cardDigitsController.dispose();
      bankController.dispose();
    });
  }

  Future<void> _sendPaymentConfirmation(double amountPaidNow, double remaining, String cleanedPhone) async {
    if (cleanedPhone.isEmpty) {
      return;
    }

    final whatsappService = ref.read(whatsappServiceProvider);

    final message = StringBuffer()
      ..writeln('عزيزي ${widget.booking.guestName}')
      ..writeln('تم استلام دفعتك بقيمة ${_formatAmountForMessage(amountPaidNow)} ريال')
      ..writeln('رقم الغرفة: ${widget.booking.roomNumber}')
      ..writeln('المبلغ المتبقي: ${_formatAmountForMessage(remaining)} ريال')
      ..writeln('شكراً لاختيارك فندق مارينا')
      ..write('للاستفسار: 9677734587456');

    try {
      final result = await whatsappService.sendMessage(phoneE164: cleanedPhone, message: message.toString());
      if (result.quotaMessage != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.quotaMessage!), backgroundColor: Colors.orange));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر إرسال رسالة واتساب')));
      }
    }
  }

  /// التحقق من وجود ليالي إضافية
  bool _shouldShowExtendedStayOptions(BookingPaymentSummary summary) {
    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final now = DateTime.now();
    final currentStay = Time.nightsWithCutoff(checkin, checkout: now);
    final expectedNights = widget.booking.expectedNights;

    // عرض خيارات الليالي الإضافية إذا:
    // 1. الليالي الحالية أكثر من المتوقعة
    // 2. أو إذا كان اليوم الحالي بعد تاريخ المغادرة المخطط
    final plannedCheckout = widget.booking.checkoutDate != null
        ? DateTime.tryParse(widget.booking.checkoutDate!)
        : null;
    final isPastCheckoutDate = plannedCheckout != null && now.isAfter(plannedCheckout);

    return currentStay > expectedNights || isPastCheckoutDate;
  }

  /// عرض خيارات دفع الليالي الإضافية
  Widget _buildExtendedStayPaymentOptions(BookingPaymentSummary summary) {
    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final now = DateTime.now();
    final currentStay = Time.nightsWithCutoff(checkin, checkout: now);
    final expectedNights = widget.booking.expectedNights;
    final extraNights = currentStay - expectedNights;

    if (extraNights <= 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(
          children: [
            const Icon(Icons.access_time, color: Colors.blue, size: 32),
            const SizedBox(height: 8),
            Text(
              'خيارات تمديد الإقامة ستظهر عند تجاوز الليالي المخططة',
              style: TextStyle(color: Colors.blue.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'إقامة ممددة - $extraNights ليلة إضافية',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // دفع سريع للليالي الإضافية
          Row(
            children: [
              Expanded(child: _buildDailyPaymentButton('دفع ليلة واحدة', summary, 1)),
              const SizedBox(width: 8),
              if (extraNights >= 2) ...[
                Expanded(child: _buildDailyPaymentButton('دفع ليلتين', summary, 2)),
                const SizedBox(width: 8),
              ],
              Expanded(child: _buildDailyPaymentButton('دفع كل الإضافي ($extraNights)', summary, extraNights)),
            ],
          ),
        ],
      ),
    );
  }

  /// زر دفع سريع للليالي الإضافية
  Widget _buildDailyPaymentButton(String label, BookingPaymentSummary summary, int nights) {
    final roomsRepo = ref.watch(roomsRepoProvider);

    return StreamBuilder<db.Room?>(
      stream: roomsRepo.watchByNumber(widget.booking.roomNumber),
      builder: (context, roomSnap) {
        final double roomRate = roomSnap.data?.price ?? 0;
        final amount = nights * roomRate;

        return ElevatedButton(
          onPressed: amount > 0 ? () => _showDailyPaymentDialog(nights, amount) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              Text(_currencyFmt.format(amount), style: const TextStyle(fontSize: 11)),
            ],
          ),
        );
      },
    );
  }

  /// نافذة دفع الليالي اليومية
  void _showDailyPaymentDialog(int nights, double amount) {
    final notesController = TextEditingController(
      text: nights == 1 ? 'دفع ليلة إضافية واحدة' : 'دفع $nights ليالي إضافية',
    );
    final perNight = nights > 0 ? (amount / nights).round() : 0;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.hotel, color: Colors.orange),
            const SizedBox(width: 8),
            Text('دفع $nights ${nights == 1 ? 'ليلة' : 'ليالي'} إضافية'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  Text('المبلغ: ${_currencyFmt.format(amount)}'),
                  Text('عدد الليالي: $nights'),
                  Text('سعر الليلة: ${_currencyFmt.format(perNight)}'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'ملاحظات', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => _processDailyPayment(amount, notesController.text, nights),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('تسجيل الدفعة'),
          ),
        ],
      ),
    ).then((_) {
      // ✅ إصلاح تسرب ذاكرة: dispose المتحكم بعد إغلاق الحوار
      notesController.dispose();
    });
  }

  /// معالجة دفع الليالي الإضافية
  Future<void> _processDailyPayment(double amount, String notes, int nights) async {
    final paymentsRepo = ref.read(paymentsRepoProvider);

    await paymentsRepo.create(
      bookingLocalId: widget.booking.id,
      serverBookingId: widget.booking.serverBookingId,
      roomNumber: widget.booking.roomNumber,
      amount: amount,
      paymentDate: Time.nowIso(),
      notes: notes.isEmpty ? 'دفع $nights ${nights == 1 ? 'ليلة' : 'ليالي'} إضافية' : notes,
      paymentMethod: 'نقدي', // افتراضي، يمكن تحسينه لاحقاً
      revenueType: 'room', // رسوم غرفة للليالي الإضافية
    );

    // ignore: use_build_context_synchronously
    Navigator.pop(context);

    // حساب المتبقي الجديد
    final roomsRepo = ref.read(roomsRepoProvider);
    final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
    final double roomRate = room?.price ?? 0;
    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final now = DateTime.now();
    final currentNights = Time.nightsWithCutoff(checkin, checkout: now);
    final currentTotal = currentNights * roomRate;
    final allPayments = await paymentsRepo.paymentsByBooking(widget.booking.id).first;
    final totalPaid = allPayments.fold<double>(0, (s, p) => s + p.amount);
    double newRemaining = currentTotal - totalPaid;
    if (newRemaining < 0) {
      newRemaining = 0;
    }

    // إرسال رسالة واتساب
    final cleanedPhone = _cleanAndFormatPhone(_currentGuestPhone);
    if (cleanedPhone.isNotEmpty) {
      await _sendExtendedStayPaymentConfirmation(amount, newRemaining, cleanedPhone, nights);
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تسجيل دفع $nights ${nights == 1 ? 'ليلة' : 'ليالي'} إضافية - ${_currencyFmt.format(amount)}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// رسالة واتساب للدفع اليومي/الليالي الإضافية
  Future<void> _sendExtendedStayPaymentConfirmation(
    double amountPaidNow,
    double remaining,
    String cleanedPhone,
    int nightsPaid,
  ) async {
    if (cleanedPhone.isEmpty) {
      return;
    }

    final whatsappService = ref.read(whatsappServiceProvider);

    String message =
        'عزيزي ${widget.booking.guestName}، تم استلام دفعة بقيمة: ${_formatAmountForMessage(amountPaidNow)} ريال\n';
    message += 'رقم الغرفة: ${widget.booking.roomNumber}\n';
    message += 'دفع $nightsPaid ${nightsPaid == 1 ? 'ليلة إضافية' : 'ليالي إضافية'}\n';
    message += 'المبلغ المتبقي: ${_formatAmountForMessage(remaining)} ريال\n';
    message += 'شكراً لاختيارك فندق مارينا\n';
    message += 'للاستفسار: 9677734587456';

    try {
      final result = await whatsappService.sendMessage(phoneE164: cleanedPhone, message: message);
      if (result.quotaMessage != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.quotaMessage!), backgroundColor: Colors.orange));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر إرسال رسالة واتساب')));
      }
    }
  }

  Future<_PaymentTotals> _calculateCurrentTotals() async {
    final roomsRepo = ref.read(roomsRepoProvider);
    final paymentsRepo = ref.read(paymentsRepoProvider);
    final dbInstance = ref.read(databaseProvider);
    final derivedService = BookingDerivedFieldsService(dbInstance);

    await derivedService.refreshForBookingId(widget.booking.id);

    final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
    final double roomRate = room?.price ?? 0;

    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final plannedCheckout = widget.booking.checkoutDate != null
        ? DateTime.tryParse(widget.booking.checkoutDate!)
        : null;
    final actualCheckout = widget.booking.actualCheckout != null
        ? DateTime.tryParse(widget.booking.actualCheckout!)
        : null;
    final actualNights = Time.nightsWithCutoff(checkin, checkout: actualCheckout ?? plannedCheckout);

    final nights =
        await (dbInstance.select(dbInstance.bookingNights)
              ..where((n) => n.bookingLocalId.equals(widget.booking.id))
              ..where((n) => n.deletedAt.isNull()))
            .get();
    final discount = widget.booking.discount;
    final discountType = widget.booking.discountType;
    final discountStartDate = _parseDateTime(widget.booking.discountStartDate);

    final double nightTotal = nights.isNotEmpty
        ? nights.fold<double>(0, (sum, n) => sum + (n.finalRate > 0 ? n.finalRate : n.nightlyRate))
        : (() {
            final checkout = actualCheckout ?? plannedCheckout;
            if (checkout == null) {
              return actualNights * roomRate;
            }
            if (discount > 0 && discountType == 'per_night') {
              final discountedNights = _countNightsWithDiscount(checkin, checkout, discountStartDate);
              final fullNightsRaw = actualNights - discountedNights;
              final fullNights = fullNightsRaw < 0 ? 0 : fullNightsRaw;
              final discountedRate = (roomRate - discount).clamp(0, roomRate).toDouble();
              return (fullNights * roomRate) + (discountedNights * discountedRate);
            }
            return actualNights * roomRate;
          })();

    final double totalAmount = discount > 0 && discountType == 'total'
        ? (nightTotal - discount).clamp(0, nightTotal).toDouble()
        : nightTotal;
    final payments = await paymentsRepo.paymentsByBooking(widget.booking.id).first;
    final paidAmount = payments.fold<double>(0, (s, p) => s + p.amount);
    double remainingAmount = totalAmount - paidAmount;
    if (remainingAmount < 0) {
      remainingAmount = 0;
    }

    return _PaymentTotals(totalAmount, remainingAmount);
  }

  Future<void> _processPayment(
    PaymentMethod method,
    String amountText,
    String notes,
    String reference,
    String cardDigits,
    String bank, {
    bool isPendingBalance = false,
  }) async {
    if (_isSavingPayment) {
      return;
    }

    final parsedAmount = CurrencyFormatter.parseAmount(amountText);
    if (parsedAmount == null || parsedAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')));
      return;
    }
    if (parsedAmount % 1 != 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المبلغ يجب أن يكون بدون كسور')));
      return;
    }
    final double amount = parsedAmount;

    _isSavingPayment = true;

    final paymentsRepo = ref.read(paymentsRepoProvider);
    final bookingsRepo = ref.read(bookingsRepoProvider);

    try {
      final totals = await _calculateCurrentTotals();

      // ═══════════════════════════════════════════════════════
      // حساب التمديد (قراءة + حوار تأكيد) — قبل الـ transaction
      // ═══════════════════════════════════════════════════════
      bool needsExtension = false;
      DateTime? newCheckout;
      int? newExpectedNights;
      int? extraNights;

      if (!isPendingBalance && amount > totals.remaining) {
        // المبلغ يتجاوز المتبقي — نحسب الليالي الإضافية و نمدد الحجز
        final surplus = amount - totals.remaining;
        final roomsRepo = ref.read(roomsRepoProvider);
        final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
        final double rmRate = room?.price ?? 0;

        if (rmRate <= 0) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يمكن حساب الليالي الإضافية — سعر الغرفة غير محدد'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        extraNights = (surplus / rmRate).ceil();
        if (extraNights <= 0) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يمكن حساب الليالي الإضافية')));
          return;
        }

        // تأكيد التمديد من المستخدم
        final confirmed = await showDialog<bool>(
          // ignore: use_build_context_synchronously
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.update, color: Colors.indigo),
                SizedBox(width: 8),
                Text('تسجيل دفعة مع تمديد'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('المبلغ يتجاوز المتبقي. سيتم تمديد الحجز تلقائياً:'),
                const SizedBox(height: 12),
                Text('المبلغ المتبقي الحالي: ${_currencyFmt.format(totals.remaining)}'),
                Text('المبلغ الفائض: ${_currencyFmt.format(surplus)}'),
                Text(
                  'سيتم إضافة: $extraNights ${extraNights == 1 ? 'ليلة' : 'ليالي'} قادمة',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
                const SizedBox(height: 8),
                const Text(
                  'سيتم تحديث تاريخ المغادرة وإضافة الليالي الجديدة',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                child: const Text('تأكيد التمديد والدفع'),
              ),
            ],
          ),
        );

        if (confirmed != true) {
          return;
        }

        // حساب بيانات التمديد
        final currentCheckout = widget.booking.checkoutDate != null
            ? DateTime.tryParse(widget.booking.checkoutDate!)
            : DateTime.now().add(const Duration(days: 1));
        newCheckout = (currentCheckout ?? DateTime.now()).add(Duration(days: extraNights));
        newExpectedNights = widget.booking.expectedNights + extraNights;
        needsExtension = true;
      }

      // ═══════════════════════════════════════════════════════
      // Transaction واحد يحمي من كارثة مالية:
      // تمديد الحجز + تحديث الهاتف + إنشاء الدفعة
      // لو التطبيق انهار في المنتصف → كل العمليات تتراجع معاً
      // ═══════════════════════════════════════════════════════
      final cleanedPhone = _cleanAndFormatPhone(_phoneController.text);
      final database = ref.read(databaseProvider);
      await database.transaction(() async {
        // 1) تمديد الحجز (إذا لزم)
        if (needsExtension) {
          await bookingsRepo.update(
            widget.booking.id,
            checkoutDate: _formatDateTime(newCheckout!),
            expectedNights: newExpectedNights,
            notes: widget.booking.notes != null
                ? '${widget.booking.notes}\nتمديد تلقائي: $extraNights ${extraNights == 1 ? 'ليلة' : 'ليالي'}'
                : 'تمديد تلقائي: $extraNights ${extraNights == 1 ? 'ليلة' : 'ليالي'}',
          );
          // إعادة حساب المبالغ بعد التمديد (قراءة داخل الـ tx)
          await _calculateCurrentTotals();
        }

        // 2) تحديث رقم الهاتف الضيف
        await bookingsRepo.update(widget.booking.id, guestPhone: cleanedPhone);
        if (mounted) {
          setState(() {
            _currentGuestPhone = cleanedPhone;
            if (_phoneController.text != cleanedPhone) {
              _phoneController.value = TextEditingValue(
                text: cleanedPhone,
                selection: TextSelection.collapsed(offset: cleanedPhone.length),
              );
            }
          });
        } else {
          _currentGuestPhone = cleanedPhone;
        }

        // 3) إنشاء الدفعة
        await paymentsRepo.create(
          bookingLocalId: widget.booking.id,
          serverBookingId: widget.booking.serverBookingId,
          roomNumber: widget.booking.roomNumber,
          amount: amount,
          paymentDate: Time.nowIso(),
          notes: notes.isEmpty ? null : notes,
          paymentMethod: _mapUiMethodToDb(method),
          revenueType: 'room',
        );
      });
      // ═══════════════════════════════════════════════════════
      // نهاية الـ Transaction — كل العمليات ناجحة أو لا شيء
      // ═══════════════════════════════════════════════════════

      double newRemaining = totals.remaining - amount;
      if (newRemaining < 0) {
        newRemaining = 0;
      }

      if (cleanedPhone.isNotEmpty) {
        // إرسال رسالة الواتساب قبل إغلاق الشاشة لضمان وجود السياق (Context)
        // واستخدام رقم الهاتف الذي تم تنظيفه وتحديثه
        await _sendPaymentConfirmation(amount, newRemaining, cleanedPhone);
      }

      // ignore: use_build_context_synchronously
      Navigator.pop(context);

      if (mounted) {
        setState(() {
          _remainingAmount = newRemaining;
        });
      } else {
        _remainingAmount = newRemaining;
      }

      final receipt = Payment(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        bookingId: widget.booking.localUuid,
        amount: amount,
        method: method,
        status: PaymentStatus.completed,
        paymentDate: DateTime.now(),
        notes: notes.isNotEmpty ? notes : null,
        referenceNumber: reference.isNotEmpty ? reference : null,
        cardLastFourDigits: cardDigits.isNotEmpty ? cardDigits : null,
        bankName: bank.isNotEmpty ? bank : null,
        receivedBy: 'admin',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      _showReceiptDialog(receipt);

      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('تم تسجيل دفعة بقيمة ${_currencyFmt.format(amount)}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذّر تسجيل الدفعة: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        _isSavingPayment = false;
      } else {
        _isSavingPayment = false;
      }
    }
  }

  void _showReceiptDialog(Payment payment) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تم تسجيل الدفعة بنجاح'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text('المبلغ: ${_currencyFmt.format(payment.amount)}'),
            Text('طريقة الدفع: ${payment.method.displayName}'),
            Text('المتبقي: ${_currencyFmt.format(_remainingAmount)}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _generateReceipt(payment);
            },
            child: const Text('طباعة إيصال'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateReceipt(Payment payment) async {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    try {
      final receipt = Receipt(
        receiptNumber: 'REC${DateTime.now().millisecondsSinceEpoch}',
        payment: payment,
        guestName: widget.booking.guestName,
        guestPhone: _currentGuestPhone,
        roomNumber: widget.booking.roomNumber,
        generatedAt: DateTime.now(),
      );
      await receipt.generatePDF();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('خطأ في إنشاء الإيصال: $e')));
      }
    }
  }

  Future<void> _generateInvoice(BookingPaymentSummary summary) async {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
      final plannedCheckout = widget.booking.checkoutDate != null
          ? DateTime.tryParse(widget.booking.checkoutDate!)
          : null;
      final actualCheckout = widget.booking.actualCheckout != null
          ? DateTime.tryParse(widget.booking.actualCheckout!)
          : null;
      final checkout = actualCheckout ?? plannedCheckout ?? checkin;
      final roomsRepo = ref.read(roomsRepoProvider);
      final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
      final invoice = Invoice(
        invoiceNumber: 'INV${DateTime.now().millisecondsSinceEpoch}',
        bookingId: widget.booking.localUuid,
        guestName: widget.booking.guestName,
        guestPhone: _currentGuestPhone,
        roomNumber: widget.booking.roomNumber,
        checkinDate: checkin,
        checkoutDate: checkout,
        nights: Time.nightsWithCutoff(checkin, checkout: checkout),
        roomRate: room?.price ?? 0,
        totalAmount: summary.totalAmount,
        payments: summary.payments,
        remainingAmount: summary.remainingAmount,
        generatedAt: DateTime.now(),
      );
      await invoice.generatePDF();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('خطأ في إنشاء الفاتورة: $e')));
      }
    }
  }

  /// نافذة تأكيد المغادرة العادية
  /// عند وجود ليالٍ مشبوهة (مضافة بعد موعد المغادرة المتوقع) تظهر نافذة
  /// احترافية أولاً لاتخاذ قرار احتسابها أو إلغائها قبل المتابعة.
  Future<void> _showCheckoutConfirmation(
    BookingPaymentSummary summary, {
    required db.Booking booking,
    required List<db.BookingNight> nights,
  }) async {
    // 1. كشف الليالي المشبوهة أولاً — إذا وُجدت، اعرض نافذة القرار
    final suspiciousNights = _detectSuspiciousNights(nights, booking);
    if (suspiciousNights.isNotEmpty) {
      await _showSuspiciousNightsDialog(suspiciousNights);
      // بعد المعالجة، نتابع لنافذة التأكيد العادية
      // (الليالي الملغاة ستُستبعد من الحساب تلقائياً عبر _cancelledSuspiciousNightIds)
    }

    if (!mounted) return;

    // 2. إعادة حساب المبلغ المستحق بعد استبعاد الليالي الملغاة (إن وُجدت)
    final effectiveNights = nights.where((n) => !_cancelledSuspiciousNightIds.contains(n.id)).toList();
    final double effectiveNightTotal = effectiveNights.isNotEmpty
        ? effectiveNights.fold<double>(0, (sum, n) => sum + (n.finalRate > 0 ? n.finalRate : n.nightlyRate))
        : summary.totalAmount;
    final effectiveRemaining = (effectiveNightTotal - summary.paidAmount).clamp(0.0, effectiveNightTotal);
    final hasRemaining = effectiveRemaining > 0;

    // 3. عرض نافذة التأكيد العادية
    // ignore: use_build_context_synchronously
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(hasRemaining ? Icons.warning : Icons.check_circle, color: hasRemaining ? Colors.red : Colors.green),
              const SizedBox(width: 8),
              Text(
                hasRemaining ? 'تحذير!' : 'تأكيد المغادرة',
                style: TextStyle(color: hasRemaining ? Colors.red : null),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // مؤشر استبعاد الليالي المشبوهة (إن وُجدت)
              if (_cancelledSuspiciousNightIds.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تم استبعاد ${_cancelledSuspiciousNightIds.length} ${_cancelledSuspiciousNightIds.length == 1 ? "ليلة مشبوهة" : "ليالٍ مشبوهة"} من الفاتورة',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (hasRemaining) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.money_off, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            'المبلغ المتبقي: ${_currencyFmt.format(effectiveRemaining)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '⚠️ سيتم خصم المبلغ من راتبكم',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text('هل تريد تسجيل مغادرة العميل وتحرير الغرفة؟'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _processCheckout();
              },
              style: ElevatedButton.styleFrom(backgroundColor: hasRemaining ? Colors.red : Colors.green),
              child: Text(hasRemaining ? 'متابعة رغم ذلك' : 'تأكيد المغادرة'),
            ),
          ],
        ),
      ),
    );
  }

  /// نافذة المغادرة المبكرة مع حساب المردود
  Future<void> _showEarlyCheckoutDialog(BookingPaymentSummary summary) async {
    final dbInstance = ref.read(databaseProvider);
    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final now = DateTime.now();
    final plannedCheckout = widget.booking.checkoutDate != null
        ? DateTime.tryParse(widget.booking.checkoutDate!)
        : null;

    if (plannedCheckout == null || !now.isBefore(plannedCheckout)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا يوجد مغادرة مبكرة — الحجز انتهى أو لا يوجد تاريخ مغادرة مخطط')));
      return;
    }

    // حساب الليالي
    final actualNights = Time.nightsWithCutoff(checkin, checkout: now);
    final plannedNights = Time.nightsWithCutoff(checkin, checkout: plannedCheckout);
    final unusedNights = plannedNights - actualNights;

    if (unusedNights <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد ليالي غير مستخدمة للرد')));
      return;
    }

    // جلب ليالي الحجز لتحسب تكلفة الليالي الفعلية
    final nights =
        await (dbInstance.select(dbInstance.bookingNights)
              ..where((n) => n.bookingLocalId.equals(widget.booking.id))
              ..where((n) => n.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
            .get();

    // تكلفة الليالي الفعلية المستخدمة
    double actualNightsCost = 0;
    if (nights.isNotEmpty) {
      final effectiveCount = actualNights.clamp(0, nights.length);
      for (int i = 0; i < effectiveCount; i++) {
        actualNightsCost += nights[i].finalRate > 0 ? nights[i].finalRate : nights[i].nightlyRate;
      }
    } else {
      // بديل: سعر الغرفة × الليالي الفعلية
      final roomsRepo = ref.read(roomsRepoProvider);
      final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
      actualNightsCost = actualNights * (room?.price ?? 0);
    }

    final totalPaid = summary.paidAmount;
    final refundAmount = (totalPaid - actualNightsCost).clamp(0.0, totalPaid);

    if (!mounted) {
      return;
    }

    final dateFmt = DateFormat('dd/MM/yyyy');
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.currency_exchange, color: Colors.amber),
              SizedBox(width: 8),
              Text('مغادرة مبكرة — حساب المردود'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRefundInfoRow('الوصول', dateFmt.format(checkin)),
                _buildRefundInfoRow('المغادرة المخططة', dateFmt.format(plannedCheckout)),
                _buildRefundInfoRow('تاريخ المغادرة الفعلي', dateFmt.format(now)),
                const Divider(height: 20),
                _buildRefundInfoRow('الليالي المدفوعة', '$plannedNights ليلة'),
                _buildRefundInfoRow('الليالي المستخدمة', '$actualNights ليلة'),
                _buildRefundInfoRow('الليالي غير المستخدمة', '$unusedNights ليلة', valueColor: Colors.orange),
                const Divider(height: 20),
                _buildRefundInfoRow('إجمالي المدفوع', _currencyFmt.format(totalPaid)),
                _buildRefundInfoRow('تكلفة الليالي المستخدمة', _currencyFmt.format(actualNightsCost)),
                if (refundAmount > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.money_off, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          'المبلغ المردود: ${_currencyFmt.format(refundAmount.round())}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                if (refundAmount <= 0)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: const Text(
                      'لا يوجد مردود — المدفوع يساوي تكلفة الليالي المستخدمة',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            if (refundAmount > 0)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _processEarlyCheckout(refundAmount.round(), unusedNights, actualNights);
                },
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('تأكيد المغادرة والمردود'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
            if (refundAmount <= 0)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _processCheckout();
                },
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('تأكيد المغادرة فقط'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRefundInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: valueColor),
          ),
        ],
      ),
    );
  }

  /// معالجة المغادرة المبكرة مع تسجيل المردود
  Future<void> _processEarlyCheckout(int refundAmount, int unusedNights, int actualNights) async {
    try {
      // 0. حذف الليالي المشبوهة الملغاة من قاعدة البيانات
      await _deleteCancelledNights();

      final bookingsRepo = ref.read(bookingsRepoProvider);
      final roomsRepo = ref.read(roomsRepoProvider);
      final paymentsRepo = ref.read(paymentsRepoProvider);
      final nowIso = Time.nowIso();

      // 1. تسجيل المغادرة
      await bookingsRepo.update(
        widget.booking.id,
        status: 'مكتمل',
        actualCheckout: nowIso,
        calculatedNights: actualNights,
      );

      // 2. تسجيل دفعة المردود (مبلغ سالب)
      await paymentsRepo.create(
        bookingLocalId: widget.booking.id,
        serverBookingId: widget.booking.serverBookingId,
        roomNumber: widget.booking.roomNumber,
        amount: refundAmount.toDouble() * -1,
        paymentDate: nowIso,
        notes: 'مردود مغادرة مبكرة - $unusedNights ${unusedNights == 1 ? 'ليلة' : 'ليالي'} غير مستخدمة',
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      // 3. تحرير الغرفة
      final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
      if (room != null) {
        await roomsRepo.update(room.id, status: 'شاغرة');
      }

      // ✅ تسجيل تغيير المزامنة بعد تحرير الغرفة
      markDataChanged();

      // ✅ رفع التغييرات إلى Appwrite Cloud فوراً (push-only بدون pull)
      // يضمن عدم حدوث سحب تلقائي بعد الرفع، وبالتالي تجنّب تعارض البيانات
      // عند المغادرة المبكرة. الـ outbox subscription في AppwriteSyncManager
      // يستخدم sync(pull: false) تلقائياً، لكن هذا الاستدعاء الصريح يضمن
      // الرفع الفوري بدون انتظار debounce الافتراضي.
      unawaited(
        ref
            .read(appwriteSyncManagerProvider)
            .pushLocalChanges()
            .then((pushedCount) {
              debugPrint(
                '📤 [EarlyCheckout] push-only to Appwrite Cloud: '
                '${pushedCount > 0 ? "success ($pushedCount records)" : "deferred (will retry via outbox)"}',
              );
            })
            .catchError((Object e) {
              debugPrint(
                '⚠️ [EarlyCheckout] push to Appwrite Cloud failed: $e — '
                'سيتم إعادة المحاولة تلقائياً عبر outbox',
              );
            }),
      );

      // 4. إرسال رسالة واتساب
      final cleanedPhone = _cleanAndFormatPhone(_currentGuestPhone);
      if (cleanedPhone.isNotEmpty) {
        await _sendRefundConfirmation(refundAmount, unusedNights, cleanedPhone);
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تسجيل مغادرة مبكرة — المردود: ${_currencyFmt.format(refundAmount)} ($unusedNights ${unusedNights == 1 ? 'ليلة' : 'ليالي'})',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('❌ خطأ في المغادرة المبكرة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تسجيل المغادرة المبكرة: $e'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// رسالة واتساب تأكيد المردود
  Future<void> _sendRefundConfirmation(int refundAmount, int unusedNights, String cleanedPhone) async {
    if (cleanedPhone.isEmpty) {
      return;
    }
    final whatsappService = ref.read(whatsappServiceProvider);

    String message = 'عزيزي ${widget.booking.guestName}، تم تسجيل مغادرتكم المبكرة\n';
    message += 'رقم الغرفة: ${widget.booking.roomNumber}\n';
    message += 'مبلغ المردود: ${_formatAmountForMessage(refundAmount)} ريال\n';
    message += 'عدد الليالي غير المستخدمة: $unusedNights ${unusedNights == 1 ? 'ليلة' : 'ليالي'}\n';
    message += 'شكراً لاختيارك فندق مارينا\n';
    message += 'للاستفسار: 9677734587456';

    try {
      final result = await whatsappService.sendMessage(phoneE164: cleanedPhone, message: message);
      if (result.quotaMessage != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.quotaMessage!), backgroundColor: Colors.orange));
      }
    } catch (_) {
      // تجاهل الأخطاء
    }
  }

  /// ✅ إنشاء دين بالمبلغ المتبقي لدى النزيل
  /// يضيف الدين تلقائياً إلى جدول الديون مع ربطه بالحجز الحالي
  Future<void> _createDebtFromRemainingBalance(BookingPaymentSummary summary, db.Booking booking) async {
    final remaining = summary.remainingAmount;
    if (remaining <= 0) return;

    // تأكيد المستخدم
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add_circle, color: Colors.orange),
              SizedBox(width: 8),
              Text('إنشاء دين بالمبلغ المتبقي'),
            ],
          ),
          content: Text(
            'سيتم إنشاء دين بقيمة ${_currencyFmt.format(remaining)} '
            'للنزيل ${booking.guestName} (غرفة ${booking.roomNumber}).\n\n'
            'الدين سيُضاف تلقائياً إلى قائمة الديون ويمكن متابعته '
            'وسداد لاحقاً.\n\nهل تريد المتابعة؟',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop<bool>(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop<bool>(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('إنشاء الدين'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final debtsRepo = ref.read(debtsRepoProvider);
      final nowIso = Time.nowIso();

      await debtsRepo.create(
        bookingLocalId: booking.id,
        guestName: booking.guestName,
        checkinDate: booking.checkinDate,
        checkoutDate: booking.actualCheckout ?? booking.checkoutDate ?? nowIso,
        dateRecorded: nowIso,
        debtReason: 'مبلغ متبقي من إقامة - غرفة ${booking.roomNumber}',
        totalAmount: remaining,
        paidAmount: 0,
        paymentDate: nowIso,
        isSettled: false,
        note:
            'تم إنشاء هذا الدين تلقائياً من شاشة المدفوعات '
            'عند وجود مبلغ متبقي لدى النزيل.',
      );

      // ✅ تسجيل تغيير المزامنة
      markDataChanged();

      // ✅ رفع التغييرات إلى Appwrite Cloud فوراً (push-only)
      unawaited(
        ref
            .read(appwriteSyncManagerProvider)
            .pushLocalChanges()
            .then((pushedCount) {
              debugPrint(
                '📤 [CreateDebt] push-only to Appwrite Cloud: '
                '${pushedCount > 0 ? "success ($pushedCount records)" : "deferred"}',
              );
            })
            .catchError((Object e) {
              debugPrint('⚠️ [CreateDebt] push failed: $e');
            }),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ تم إنشاء دين بقيمة ${_currencyFmt.format(remaining)} '
            'وإضافته إلى قائمة الديون',
          ),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'عرض الديون',
            textColor: Colors.white,
            onPressed: () {
              // التنقل لشاشة الديون
              Navigator.pushNamed(context, '/debts');
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء الدين: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل إنشاء الدين: $e'), backgroundColor: Colors.red));
    }
  }

  /// ✅ خصم مبلغ من الليالي الفعلية (تخفيض على إجمالي الفاتورة)
  ///
  /// يطبّق خصم بمبلغ ثابت على الحجز عبر تحديث حقل `discount` و
  /// `discountType = 'total'`. هذا يقلّل `totalAmount` وبالتالي
  /// يقلّل `remainingAmount` — لا يؤثر على الديون السابقة.
  ///
  /// مثال: لو الإجمالي 50,000 والمدفوع 20,000 → المتبقي 30,000.
  /// خصم 5,000 → الإجمالي الجديد 45,000 → المتبقي 25,000.
  Future<void> _showDiscountAmountDialog(BookingPaymentSummary summary, db.Booking booking) async {
    // ✅ Defense-in-depth: تحقق من صلاحية المدير حتى لو استُدعيت من مكان آخر
    final currentUser = ref.read(authProvider).currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('⚠️ صلاحية الخصم متاحة للمدير فقط'), backgroundColor: Colors.red));
      return;
    }

    final amountController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.discount, color: Colors.green),
              SizedBox(width: 8),
              Text('خصم مبلغ من الليالي الفعلية'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'النزيل: ${booking.guestName} (غرفة ${booking.roomNumber})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _infoRow('إجمالي الفاتورة', _currencyFmt.format(summary.totalAmount)),
                _infoRow('المدفوع', _currencyFmt.format(summary.paidAmount)),
                _infoRow('المتبقي', _currencyFmt.format(summary.remainingAmount)),
                if (booking.discount > 0) _infoRow('خصم حالي', _currencyFmt.format(booking.discount)),
                const Divider(),
                const Text('مبلغ الخصم الجديد:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: '0',
                    suffixText: 'ريال',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    prefixIcon: Icon(Icons.attach_money, size: 18),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'سيتم إضافة هذا المبلغ إلى الخصم الحالي وتقليل المتبقي.',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop<bool>(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop<bool>(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('تطبيق الخصم'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final amountStr = amountController.text.replaceAll(RegExp('[^0-9.]'), '');
    final amount = double.tryParse(amountStr) ?? 0;
    if (amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('⚠️ المبلغ غير صالح'), backgroundColor: Colors.red));
      return;
    }

    if (amount > summary.remainingAmount) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ مبلغ الخصم يتجاوز المتبقي (${_currencyFmt.format(summary.remainingAmount)})'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final bookingsRepo = ref.read(bookingsRepoProvider);
      // ✅ أضف مبلغ الخصم الجديد إلى الخصم الحالي + اضبط discountType = 'total'
      final newDiscount = booking.discount + amount;
      await bookingsRepo.update(booking.id, discount: newDiscount, discountType: 'total');

      // ✅ تسجيل تغيير المزامنة + push فوري
      markDataChanged();
      unawaited(
        ref
            .read(appwriteSyncManagerProvider)
            .pushLocalChanges()
            .then((pushedCount) {
              debugPrint(
                '📤 [DiscountNights] push to Appwrite: '
                '${pushedCount > 0 ? "success ($pushedCount)" : "deferred"}',
              );
            })
            .catchError((Object e) {
              debugPrint('⚠️ [DiscountNights] push failed: $e');
            }),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ تم خصم ${_currencyFmt.format(amount)} من الليالي الفعلية. '
            'المتبقي الجديد: ${_currencyFmt.format(summary.remainingAmount - amount)}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('❌ خطأ في تطبيق الخصم: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل تطبيق الخصم: $e'), backgroundColor: Colors.red));
    }
  }

  /// صف معلومات مدمج للـ dialog
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// معالجة المغادرة العادية
  Future<void> _processCheckout() async {
    try {
      // 0. حذف الليالي المشبوهة الملغاة من قاعدة البيانات
      await _deleteCancelledNights();

      final bookingsRepo = ref.read(bookingsRepoProvider);
      final roomsRepo = ref.read(roomsRepoProvider);
      final nowIso = Time.nowIso();
      final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
      final nowDate = DateTime.parse(nowIso);
      final actualNights = Time.nightsWithCutoff(checkin, checkout: nowDate);
      await bookingsRepo.update(
        widget.booking.id,
        status: 'مكتمل',
        actualCheckout: nowIso,
        calculatedNights: actualNights,
      );
      final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
      if (room != null) {
        await roomsRepo.update(room.id, status: 'شاغرة');
      }
      // ✅ تسجيل تغيير المزامنة بعد تحرير الغرفة
      markDataChanged();

      // ✅ رفع التغييرات إلى Appwrite Cloud فوراً (push-only بدون pull)
      // هذا يضمن عدم حدوث سحب تلقائي بعد الرفع، وبالتالي تجنّب تعارض
      // البيانات عند تسجيل المغادرة. الـ outbox subscription في
      // AppwriteSyncManager يستخدم sync(pull: false) تلقائياً، لكن هذا
      // الاستدعاء الصريح يضمن الرفع الفوري بدون انتظار debounce الافتراضي.
      unawaited(
        ref
            .read(appwriteSyncManagerProvider)
            .pushLocalChanges()
            .then((pushedCount) {
              debugPrint(
                '📤 [Checkout] push-only to Appwrite Cloud: '
                '${pushedCount > 0 ? "success ($pushedCount records)" : "deferred (will retry via outbox)"}',
              );
            })
            .catchError((Object e) {
              debugPrint(
                '⚠️ [Checkout] push to Appwrite Cloud failed: $e — '
                'سيتم إعادة المحاولة تلقائياً عبر outbox',
              );
            }),
      );

      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل المغادرة بنجاح وتحرير الغرفة'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل المغادرة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تسجيل المغادرة: $e'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// نافذة تأكيد إلغاء دفعة اليوم الفندقي فقط (بدون تسجيل خروج)
  /// تستخدم عندما يخرج النزيل قبل بداية اليوم الفندقي الجديد وينسى العامل
  /// تسجيل خروجه فيتم احتساب يوم إضافي بالخطأ
  void _showCancelTodayPaymentDialog(BookingPaymentSummary summary) {
    final paymentsRepo = ref.read(paymentsRepoProvider);
    final hotelDay = HotelTimeEngine.getHotelDayKey();

    // عرض نافذة التأكيد مع تفاصيل الدفعات
    showDialog<void>(
      context: context,
      builder: (context) => FutureBuilder<List<db.Payment>>(
        future: paymentsRepo.paymentsByBooking(widget.booking.id).first,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const AlertDialog(content: Center(child: CircularProgressIndicator()));
          }

          final allPayments = snapshot.data ?? [];
          final todayPayments = allPayments
              .where(
                (p) =>
                    !p.isVoided &&
                    (p.hotelDayKey == hotelDay || (p.hotelDayKey == null && p.paymentDate.startsWith(hotelDay))),
              )
              .toList();

          if (todayPayments.isEmpty) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('لا توجد دفعات اليوم'),
                ],
              ),
              content: const Text('لا توجد مدفوعات مسجلة في اليوم الفندقي الحالي لإلغائها.'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
            );
          }

          final todayTotal = todayPayments.fold<double>(0, (s, p) => s + p.amount);

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.remove_circle_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('إلغاء دفعة اليوم الفندقي'),
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
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'اليوم الفندقي: $hotelDay',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'عدد المدفوعات المراد إلغاؤها: ${todayPayments.length}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إجمالي المبلغ المراد إلغاؤه: ${_currencyFmt.format(todayTotal)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '⚠️ سيتم حذف دفعات اليوم الفندقي فقط. سجل خروج النزيل منفصل عبر زر "تسجيل المغادرة".',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'تفاصيل المدفوعات المراد إلغاؤها:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ...todayPayments.map(
                    (p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              p.notes ?? p.paymentMethod,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _currencyFmt.format(p.amount),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _processCancelTodayPayments(todayPayments);
                },
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('تأكيد إلغاء الدفعات'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
            ],
          );
        },
      ),
    );
  }

  /// معالجة إلغاء دفعات اليوم الفندقي فقط (بدون تسجيل خروج أو تحرير غرفة)
  /// paymentsRepo.delete → dao.softDelete → _mergeOutbox → كتابة في outbox للمزامنة
  Future<void> _processCancelTodayPayments(List<db.Payment> paymentsToCancel) async {
    try {
      final paymentsRepo = ref.read(paymentsRepoProvider);

      // حذف (soft delete) دفعات اليوم الفندقي عبر PaymentsRepository
      // الذي يكتب إلى outbox تلقائياً عبر dao.softDelete → _mergeOutbox
      for (final p in paymentsToCancel) {
        await paymentsRepo.delete(p.id);
      }

      // ✅ تسجيل تغيير المزامنة (نفس النمط الموجود في _processCheckout)
      markDataChanged();

      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('تم إلغاء ${paymentsToCancel.length} دفعة بنجاح'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('❌ خطأ في إلغاء دفعات اليوم: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إلغاء الدفعات: $e'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _sendAccountStatement(BookingPaymentSummary summary) {
    if (_currentGuestPhone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا يوجد رقم هاتف للعميل'), backgroundColor: Colors.red));
      return;
    }

    final messagePreview = _buildAccountStatementMessage(summary);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.orange),
              SizedBox(width: 8),
              Text('إرسال كشف حساب'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // معلومات العميل السريعة
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    children: [
                      _buildStatementPreviewRow('العميل', widget.booking.guestName),
                      _buildStatementPreviewRow('الغرفة', widget.booking.roomNumber),
                      _buildStatementPreviewRow('الهاتف', _currentGuestPhone),
                      _buildStatementPreviewRow(
                        'الإجمالي',
                        '${CurrencyFormatter.formatAmount(summary.totalAmount)} ريال',
                      ),
                      _buildStatementPreviewRow(
                        'المدفوع',
                        '${CurrencyFormatter.formatAmount(summary.paidAmount)} ريال',
                        valueColor: Colors.green,
                      ),
                      _buildStatementPreviewRow(
                        'المتبقي',
                        '${CurrencyFormatter.formatAmount(summary.remainingAmount)} ريال',
                        valueColor: summary.remainingAmount > 0 ? Colors.red : Colors.green,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // زر معاينة الرسالة
                OutlinedButton.icon(
                  onPressed: () {
                    setDialogState(() {
                      _showFullPreview = !_showFullPreview;
                    });
                  },
                  icon: Icon(_showFullPreview ? Icons.visibility_off : Icons.visibility, size: 16),
                  label: Text(
                    _showFullPreview ? 'إخفاء المعاينة' : 'معاينة الرسالة',
                    style: const TextStyle(fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal,
                    side: const BorderSide(color: Colors.teal),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),

                // معاينة الرسالة الكاملة
                if (_showFullPreview) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        messagePreview,
                        style: const TextStyle(fontSize: 12, height: 1.6, fontFamily: 'Courier'),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${messagePreview.length}/1000 حرف',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: messagePreview.length > 1000
                                ? Colors.red
                                : messagePreview.length > 900
                                ? Colors.orange
                                : Colors.grey.shade600,
                          ),
                        ),
                        if (messagePreview.length > 1000)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.warning, size: 12, color: Colors.red),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            // ✅ مشاركة PDF فقط عبر Share sheet
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _sendStatementViaPdf(summary);
              },
              icon: const Icon(Icons.share, size: 18),
              label: const Text('مشاركة PDF'),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ],
        ),
      ),
    );
  }

  bool _showFullPreview = false;

  /// ✅ إرسال كشف الحساب كنص عبر واتساب — يفتح واتساب مباشرة
  /// المستخدم يختار الرقم بنفسه (لا حاجة لـ API)
  Future<void> _sendStatementViaWhatsAppText(BookingPaymentSummary summary) async {
    final message = _buildAccountStatementMessage(summary);
    final encodedMsg = Uri.encodeComponent(message);

    // فتح واتساب مباشرة مع النص جاهزاً — المستخدم يختار جهة الاتصال
    final whatsappUrl = 'https://wa.me/?text=$encodedMsg';

    try {
      final uri = Uri.parse(whatsappUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // fallback: محاولة فتح تطبيق واتساب مباشرة
        final appUri = Uri.parse('whatsapp://send?text=$encodedMsg');
        if (await canLaunchUrl(appUri)) {
          await launchUrl(appUri, mode: LaunchMode.externalApplication);
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تطبيق واتساب غير مثبت على الجهاز'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  /// ✅ إرسال كشف الحساب كـ PDF عبر واتساب
  /// يولّد PDF محلياً ثم يستخدم share_plus لمشاركته عبر واتساب
  Future<void> _sendStatementViaPdf(BookingPaymentSummary summary) async {
    if (!mounted) return;

    // ✅ إشعار تحميل
    final loading = LoadingSnackBar.show(context, message: 'جاري إنشاء كشف الحساب PDF...');

    try {
      // 1. توليد PDF
      final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
      final plannedCheckout = widget.booking.checkoutDate != null
          ? DateTime.tryParse(widget.booking.checkoutDate!)
          : null;
      final actualCheckout = widget.booking.actualCheckout != null
          ? DateTime.tryParse(widget.booking.actualCheckout!)
          : null;
      final checkout = actualCheckout ?? plannedCheckout ?? checkin;

      final roomsRepo = ref.read(roomsRepoProvider);
      final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;

      final invoice = Invoice(
        invoiceNumber: 'STMT${DateTime.now().millisecondsSinceEpoch}',
        bookingId: widget.booking.localUuid,
        guestName: widget.booking.guestName,
        guestPhone: _currentGuestPhone,
        roomNumber: widget.booking.roomNumber,
        checkinDate: checkin,
        checkoutDate: checkout,
        nights: Time.nightsWithCutoff(checkin, checkout: checkout),
        roomRate: room?.price ?? 0,
        totalAmount: summary.totalAmount,
        payments: summary.payments,
        remainingAmount: summary.remainingAmount,
        generatedAt: DateTime.now(),
      );

      // 2. حفظ PDF في ملف مؤقت
      final pdfBytes = await invoice.generatePdfBytes();
      final tempDir = await getTemporaryDirectory();
      final fileName = 'كشف_حساب_${widget.booking.guestName}_${widget.booking.roomNumber}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);

      // 3. إغلاق إشعار التحميل
      if (mounted) loading.close();

      // 4. مشاركة الملف عبر واتساب (Share sheet — المستخدم يختار واتساب)
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'كشف حساب - ${widget.booking.guestName} - غرفة ${widget.booking.roomNumber}',
        subject: 'كشف حساب - MARINA HOTEL',
      );
    } catch (e) {
      if (mounted) loading.close();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ في إنشاء PDF: $e'), backgroundColor: Colors.red));
    }
  }

  /// بناء رسالة كشف حساب مختصرة (اقصى 1000 حرف)
  String _buildAccountStatementMessage(BookingPaymentSummary summary) {
    final b = widget.booking;
    final checkin = b.checkinDate.split(' ').first;
    final checkout = b.checkoutDate?.split(' ').first ?? 'لم يحدد';
    final actualCheckout = b.actualCheckout?.split(' ').first;
    final nights = b.calculatedNights;
    final total = summary.totalAmount;
    final paid = summary.paidAmount;
    final remaining = summary.remainingAmount;

    final buf = StringBuffer();

    // رأس الكشف
    buf.writeln('كشف حساب - MARINA HOTEL');
    buf.writeln('━━━━━━━━━━━');

    // بيانات العميل والإقامة (مضغوطة)
    buf.writeln('العميل: ${b.guestName}');
    buf.write('الغرفة: ${b.roomNumber} | $nights ليلة');
    buf.writeln(' | الوصول: $checkin');
    buf.writeln('المغادرة: ${actualCheckout ?? checkout}');

    // الملخص المالي
    buf.writeln('━━━━━━━━━━━');
    buf.writeln('الإجمالي: ${CurrencyFormatter.formatAmount(total)} ريال');
    if (b.discount > 0) {
      final dType = b.discountType == 'per_night' ? '/ليلة' : '';
      buf.writeln('الخصم: -${CurrencyFormatter.formatAmount(b.discount)} ريال$dType');
    }
    buf.writeln('المدفوع: ${CurrencyFormatter.formatAmount(paid)} ريال');
    buf.writeln('المتبقي: ${CurrencyFormatter.formatAmount(remaining)} ريال');
    buf.writeln(remaining <= 0 ? 'الحالة: مكتمل' : 'الحالة: دفع جزئي');

    // سجل المدفوعات (سطر واحد لكل دفعة)
    if (summary.payments.isNotEmpty) {
      buf.writeln('━━━━━━━━━━━');
      buf.writeln('سجل المدفوعات:');
      for (int i = 0; i < summary.payments.length; i++) {
        final p = summary.payments[i];
        final pDate = DateFormat('dd/MM').format(p.paymentDate);
        final methodAr = _mapPaymentMethodToAr(p.method);
        final amountStr = CurrencyFormatter.formatAmount(p.amount);
        buf.writeln('${i + 1}.$amountStr - $methodAr - $pDate');
        // إيقاف إذا اقتربنا من الحد الأقصى
        if (buf.length > 950) {
          final remaining2 = summary.payments.length - i - 1;
          if (remaining2 > 0) {
            buf.writeln('+ $remaining2 دفعات أخرى...');
          }
          break;
        }
      }
    }

    // ديون إن وجدت
    if (_debtAmount > 0 && buf.length < 960) {
      buf.writeln('ديون: ${CurrencyFormatter.formatAmount(_debtAmount)} ريال');
    }

    // تذييل مختصر
    if (buf.length < 980) {
      buf.writeln('━━━━━━━━━━━');
      buf.write('مارينا هوتل | 9677734587456');
    }

    final msg = buf.toString();
    // ضمان عدم تجاوز 1000 حرف
    if (msg.length > 1000) {
      return '${msg.substring(0, 997)}...';
    }
    return msg;
  }

  /// تحويل طريقة الدفع من enum إلى عربي
  String _mapPaymentMethodToAr(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'نقدي';
      case PaymentMethod.card:
        return 'بطاقة ائتمانية';
      case PaymentMethod.transfer:
        return 'تحويل بنكي';
      case PaymentMethod.check:
        return 'شيك';
      case PaymentMethod.installment:
        return 'تقسيط';
    }
  }

  Widget _buildStatementPreviewRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.bold, color: valueColor, fontSize: 13),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performSendAccountStatement(BookingPaymentSummary summary) async {
    final whatsappService = ref.read(whatsappServiceProvider);
    final message = _buildAccountStatementMessage(summary);

    // إظهار مؤشر التحميل
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              SizedBox(width: 12),
              Text('جاري إرسال كشف الحساب...'),
            ],
          ),
          // ✅ يبقى ظاهراً حتى تنتهي عملية الإرسال ثم يُستبدل بالنتيجة
          duration: Duration(minutes: 5),
          backgroundColor: Colors.orange,
        ),
      );
    }

    try {
      final cleanedPhone = _cleanAndFormatPhone(_currentGuestPhone);
      final result = await whatsappService.sendMessage(phoneE164: cleanedPhone, message: message);
      final success = result.success;

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (result.quotaMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(result.quotaMessage!),
                ],
              ),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(success ? Icons.check_circle : Icons.error, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    success
                        ? 'تم إرسال كشف الحساب إلى ${widget.booking.guestName} بنجاح'
                        : 'فشل في إرسال كشف الحساب — تحقق من إعدادات الواتساب',
                  ),
                ],
              ),
              backgroundColor: success ? Colors.green : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Text('خطأ: $e'),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendPaymentReminder(BookingPaymentSummary summary) async {
    if (_currentGuestPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد رقم هاتف للعميل')));
      return;
    }

    final whatsappService = ref.read(whatsappServiceProvider);

    // بناء رسالة تذكير بسيطة
    String reminder = 'عزيزي ${widget.booking.guestName}\n';
    reminder += 'تذكير بالمبلغ المتبقي\n';
    reminder += 'رقم الغرفة: ${widget.booking.roomNumber}\n';
    reminder += 'المبلغ الإجمالي: ${_currencyFmt.format(summary.totalAmount)}\n';
    reminder += 'المبلغ المدفوع: ${_currencyFmt.format(summary.paidAmount)}\n';
    reminder += 'المبلغ المتبقي: ${_currencyFmt.format(summary.remainingAmount)}\n\n';
    reminder += 'نرجو منكم تسديد المبلغ المتبقي في أقرب وقت ممكن\n\n';
    reminder += 'شكراً لتعاونكم معنا\n';
    reminder += 'للاستفسار: 9677734587456';

    try {
      final cleanedPhone = _cleanAndFormatPhone(_currentGuestPhone);
      final result = await whatsappService.sendMessage(phoneE164: cleanedPhone, message: reminder);

      if (mounted) {
        if (result.quotaMessage != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(result.quotaMessage!), backgroundColor: Colors.orange));
        } else if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال تذكير الدفع للعميل بنجاح'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('فشل في إرسال تذكير الدفع'), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في إرسال التذكير: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// نافذة حوار تمديد الإقامة
  void _showExtendStayDialog() {
    final roomsRepo = ref.watch(roomsRepoProvider);
    final nightsController = TextEditingController(text: '1');
    final notesController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) => StreamBuilder<db.Room?>(
        stream: roomsRepo.watchByNumber(widget.booking.roomNumber),
        builder: (context, roomSnap) {
          final double roomRate = roomSnap.data?.price ?? 0;

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.add_circle_outline, color: Colors.blue),
                SizedBox(width: 8),
                Text('تمديد الإقامة'),
              ],
            ),
            content: StatefulBuilder(
              builder: (context, setState) {
                final nights = int.tryParse(nightsController.text) ?? 1;
                final totalCost = nights * roomRate;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        children: [
                          Text('سعر الليلة: ${_currencyFmt.format(roomRate)}'),
                          Text('عدد الليالي: $nights'),
                          Text(
                            'التكلفة الإجمالية: ${_currencyFmt.format(totalCost)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nightsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'عدد الليالي الإضافية',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() {}); // لتحديث التكلفة
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(labelText: 'ملاحظات', border: OutlineInputBorder()),
                    ),
                  ],
                );
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _processExtendStay(int.tryParse(nightsController.text) ?? 1, roomRate, notesController.text);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('تمديد وتسجيل دفعة'),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      // ✅ إصلاح تسرب ذاكرة: dispose المتحكمات بعد إغلاق الحوار
      nightsController.dispose();
      notesController.dispose();
    });
  }

  /// معالجة تمديد الإقامة
  Future<void> _processExtendStay(int additionalNights, double roomRate, String notes) async {
    if (additionalNights <= 0 || roomRate <= 0) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال عدد ليالي صحيح وسعر غرفة صحيح'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      final bookingsRepo = ref.read(bookingsRepoProvider);
      final paymentsRepo = ref.read(paymentsRepoProvider);

      // تحديث تاريخ المغادرة المخطط
      final currentCheckout = widget.booking.checkoutDate != null
          ? DateTime.tryParse(widget.booking.checkoutDate!)
          : DateTime.now().add(const Duration(days: 1));

      final newCheckout = (currentCheckout ?? DateTime.now()).add(Duration(days: additionalNights));

      final newExpectedNights = widget.booking.expectedNights + additionalNights;

      // تحديث الحجز
      await bookingsRepo.update(
        widget.booking.id,
        checkoutDate: _formatDateTime(newCheckout),
        expectedNights: newExpectedNights,
        notes: widget.booking.notes != null
            ? '${widget.booking.notes}\nتمديد: $additionalNights ${additionalNights == 1 ? 'ليلة' : 'ليالي'}'
            : 'تمديد: $additionalNights ${additionalNights == 1 ? 'ليلة' : 'ليالي'}',
      );

      // تسجيل دفعة الليالي الإضافية
      final double amount = additionalNights * roomRate;
      await paymentsRepo.create(
        bookingLocalId: widget.booking.id,
        serverBookingId: widget.booking.serverBookingId,
        roomNumber: widget.booking.roomNumber,
        amount: amount,
        paymentDate: Time.nowIso(),
        notes: notes.isEmpty
            ? 'تمديد $additionalNights ${additionalNights == 1 ? 'ليلة إضافية' : 'ليالي إضافية'}'
            : notes,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      // إرسال رسالة واتساب
      final cleanedPhone = _cleanAndFormatPhone(_currentGuestPhone);
      if (cleanedPhone.isNotEmpty) {
        await _sendExtensionConfirmation(additionalNights, amount, newCheckout, cleanedPhone);
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تمديد الإقامة $additionalNights ${additionalNights == 1 ? 'ليلة' : 'ليالي'} وتسجيل الدفعة'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('❌ خطأ في تمديد الإقامة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تمديد الإقامة: $e'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// رسالة تأكيد تمديد الإقامة
  Future<void> _sendExtensionConfirmation(
    int additionalNights,
    double amount,
    DateTime newCheckout,
    String cleanedPhone,
  ) async {
    final whatsappService = ref.read(whatsappServiceProvider);

    String message = 'عزيزي ${widget.booking.guestName}، تم تمديد إقامتكم\n';
    message += 'رقم الغرفة: ${widget.booking.roomNumber}\n';
    message += 'ليالي إضافية: $additionalNights ${additionalNights == 1 ? 'ليلة' : 'ليالي'}\n';
    message += 'المبلغ المدفوع: ${_formatAmountForMessage(amount)} ريال\n';
    message += 'تاريخ المغادرة الجديد: ${newCheckout.day}/${newCheckout.month}/${newCheckout.year}\n';
    message += 'شكراً لاختيارك فندق مارينا\n';
    message += 'للاستفسار: 9677734587456';

    try {
      final result = await whatsappService.sendMessage(phoneE164: cleanedPhone, message: message);
      if (result.quotaMessage != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.quotaMessage!), backgroundColor: Colors.orange));
      }
    } catch (_) {
      // تجاهل الأخطاء، الدفعة مسجلة بنجاح
    }
  }

  String _formatDate(String dateStr) {
    final date = DateParser.parse(dateStr);
    if (date == null) {
      return dateStr;
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatAmountForMessage(num amount) {
    return _currencyFmt.format(amount);
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }
}

class _PaymentTotals {
  const _PaymentTotals(this.total, this.remaining);
  final double total;
  final double remaining;
}
