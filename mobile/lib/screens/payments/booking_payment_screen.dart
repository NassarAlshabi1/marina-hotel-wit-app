// ignore_for_file: unused_element

import 'dart:async';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../models/payment_models.dart';
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
import '../../utils/time.dart';
import 'payment_history_screen.dart';

class BookingPaymentScreen extends ConsumerStatefulWidget {

  const BookingPaymentScreen({super.key, required this.booking});
  final db.Booking booking;

  @override
  ConsumerState<BookingPaymentScreen> createState() =>
      _BookingPaymentScreenState();
}

class _BookingPaymentScreenState extends ConsumerState<BookingPaymentScreen>
    with SingleTickerProviderStateMixin, SyncOnExitMixin {
  @override
  String get screenId => 'booking_payment';
  late TabController _tabController;
  late TextEditingController _phoneController;
  final _currencyFmt = NumberFormat('#,##0', 'en_US');
  double _remainingAmount = 0;
  String _currentGuestPhone = '';  // ✅ إصلاح: تهيئة بسلسلة فارغة
  bool _isSavingPayment = false;
  double _debtAmount = 0;
  StreamSubscription<void>? _hotelDayTickerSub;


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
    // ✅ إصلاح: حذف _refreshBookingNights() من initState
    // كان يعيد حساب الليالي بـ DateTime.now() كل مرة تُفتح فيها الشاشة
    // مما يغيّر المبلغ الإجمالي والمتبقي للحجوزات النشطة بدون سبب
    // الآن cached values تتحدث فقط عند:
    // 1. إضافة/إلغاء دفعة (repository يُسمي refreshForBookingId تلقائياً)
    // 2. تغير اليوم الفندقي (HotelDayTicker)
    // 3. سحب الشاشة للأسفل (RefreshIndicator)
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
      for (final d in debts) {
        if (d.isSettled == 0 && d.remainingAmount > 0) {
          totalDebt += d.remainingAmount;
        }
      }
      setState(() {
        _debtAmount = totalDebt;
      });
    }
  }

  Future<void> _refreshBookingNights() async {
    final db = ref.read(databaseProvider);
    final derivedService = BookingDerivedFieldsService(db);
    await derivedService.refreshForBookingId(widget.booking.id);
  }

  DateTime? _parseDateTime(String? value) => DateParser.parse(value);

  int _countNightsWithDiscount(
    DateTime checkin,
    DateTime checkout,
    DateTime? discountStartDate,
  ) {
    if (discountStartDate == null) {
      return HotelDateHelper.calculateNights(checkIn: checkin, checkOut: checkout);
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
    return HotelDateHelper.calculateNights(checkIn: effectiveStart, checkOut: checkout);
  }

  @override
  void dispose() {
    _hotelDayTickerSub?.cancel();
    _tabController.dispose();
    _phoneController.dispose();
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
          builder: (ctx) => AlertDialog(
            title: const Text('جاري الحفظ'),
            content: const Text('يرجى الانتظار حتى يتم حفظ الدفعة...'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
      },
      child: AppScaffold(
      title: 'معالجة المدفوعات',
      actions: [
        IconButton(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute<void>(builder: (context) =>
                  PaymentHistoryScreen(bookingId: widget.booking.localUuid),
            ),
          ),
          icon: const Icon(Icons.history),
          tooltip: 'سجل المدفوعات',
        ),
      ],
      body: StreamBuilder<db.Booking?>(
        stream: ref.watch(bookingsRepoProvider).watchOne(widget.booking.id),
        builder: (context, bookingSnap) {
          final booking = bookingSnap.data ?? widget.booking;
          return StreamBuilder<db.Room?>(
            stream: roomsRepo.watchByNumber(booking.roomNumber),
            builder: (context, roomSnap) {
              final double roomRate = roomSnap.data?.price ?? 0;
              final checkin = DateTime.tryParse(booking.checkinDate);
              if (checkin == null) {
                return const Center(
                  child: Text('خطأ: تاريخ الوصول للحجز غير صالح.'),
                );
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
              final discountStartDate = _parseDateTime(
                booking.discountStartDate,
          );

          // ─── StreamBuilder لتعديلات الأسعار (booking_price_adjustments) ───
          return StreamBuilder<List<db.BookingPriceAdjustment>>(
            stream: (dbInstance.select(dbInstance.bookingPriceAdjustments)
                  ..where((a) => (a.bookingLocalId.equals(booking.id) | a.bookingLocalUuid.equals(booking.localUuid)))
                  ..where((a) => a.isActive.equals(true))
                  ..where((a) => a.deletedAt.isNull()))
                .watch(),
            builder: (context, adjSnap) {
              final rawAdjustments = adjSnap.data ?? const <db.BookingPriceAdjustment>[];
              final filteredAdjustments = StayBalanceCalculator.filterActiveAdjustments(booking, rawAdjustments);

          return StreamBuilder<List<db.BookingNight>>(
            stream:
                (dbInstance.select(dbInstance.bookingNights)
                      ..where((n) => n.bookingLocalId.equals(booking.id))
                      ..where((n) => n.deletedAt.isNull()))
                    .watch(),
            builder: (context, nightsSnap) {
              final nights = nightsSnap.data ?? const <db.BookingNight>[];
              final nightsCount = nights.isNotEmpty
                  ? nights.length
                  : actualNights;
              final double nightTotal = nights.isNotEmpty
                  ? nights.fold<double>(
                      0,
                      (sum, n) =>
                          sum + (n.finalRate > 0 ? n.finalRate : n.nightlyRate),
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
                        final discountedRate = (roomRate - discount)
                            .clamp(0, roomRate).toDouble();
                        return (fullNights * roomRate) +
                            (discountedNights * discountedRate);
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
                discountedNights =
                    nights.where((n) => n.adjustment < 0).length;
                surchargeNights =
                    nights.where((n) => n.adjustment > 0).length;
                normalNights =
                    nightsCount - discountedNights - surchargeNights;
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
                    final allRatesMatchBase = nights.every(
                      (n) => (n.finalRate - n.baseRate).abs() < 0.01,
                    );
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
                discountedNights = _countNightsWithDiscount(
                  checkin,
                  checkout,
                  discountStartDate,
                );
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
                      .where((p) =>
                          !p.isVoided &&
                          (p.hotelDayKey == hotelDay ||
                              (p.hotelDayKey == null &&
                                  p.paymentDate.startsWith(hotelDay))),)
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
                    overallStatus: remainingAmount <= 0
                        ? PaymentStatus.completed
                        : PaymentStatus.pending,
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
                          unselectedLabelColor: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
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
                            _buildNewPaymentTab(summary, nights: nights, remainingAmount: remainingAmount, roomRate: roomRate),
                            _buildActionsTab(summary),
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
    final plannedText = plannedCheckout != null
        ? dateFmt.format(plannedCheckout)
        : null;
    final actualText = actualCheckout != null
        ? dateFmt.format(actualCheckout)
        : null;
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
        border: Border.all(
          color: summary.isFullyPaid
              ? Colors.green.shade200
              : Colors.blue.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.blue,
                child: Text(
                  widget.booking.roomNumber,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.booking.guestName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'غرفة ${widget.booking.roomNumber}${hasPhone ? ' • $_currentGuestPhone' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      identityLine,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      'الجنسية: ${widget.booking.guestNationality}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      'الوصول: $checkinText',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (plannedText != null)
                      Text(
                        'المغادرة المخطط: $plannedText',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    // ─── تاريخ المغادرة التلقائي (محسوب من المدفوعات التراكمية) ───
                    Builder(builder: (context) {
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
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      );
                    },),
                    if (actualText != null)
                      Text(
                        'المغادرة الفعلي: $actualText',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: summary.isFullyPaid
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: summary.isFullyPaid ? Colors.green : Colors.orange,
                  ),
                ),
                child: Text(
                  summary.isFullyPaid ? 'مكتمل الدفع' : 'دفع جزئي',
                  style: TextStyle(
                    fontSize: 12,
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
                color: actualNights > expectedNights
                    ? Colors.orange
                    : Colors.green,
              ),
              // مؤشر إضافة ليلة بعد الساعة 14:00 للنزلاء الذين لم يسجلوا خروج
              if (hasNotCheckedOut && nowIsAfterCutoff && actualNightsDynamic > expectedNights)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_debtAmount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        ),
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
                  value:
                      '$discountedNights (-${_currencyFmt.format(totalDiscount)})',
                  color: Colors.purple,
                ),
              if (surchargeNights > 0)
                _buildDetailChip(
                  context,
                  icon: Icons.trending_up,
                  label: 'ليالي مزادة',
                  value:
                      '$surchargeNights (+${_currencyFmt.format(totalSurcharge)})',
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
                  const Text(
                    'تقدم الدفع',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
                  ),
                  Text(
                    '${summary.paidPercentage.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
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
                  valueColor: AlwaysStoppedAnimation<Color>(
                    summary.isFullyPaid ? Colors.green : Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Row(
            children: [
              Expanded(
                child: _buildAmountChip(
                  'الإجمالي',
                  summary.totalAmount,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: _buildAmountChip(
                  'المدفوع',
                  summary.paidAmount,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: _buildAmountChip(
                  'المتبقي',
                  summary.remainingAmount,
                  Colors.red,
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: _buildAmountChip(
                  'مدفوع اليوم',
                  todayPaidAmount,
                  Colors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showPaymentDialog(
                PaymentMethod.cash,
                null,
                'رصيد تراكمي للنزيل',
                true,
              ),
              icon: const Icon(Icons.account_balance_wallet, size: 14),
              label: const Text(
                'إضافة دفعة رصيد تراكمي',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountChip(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            _currencyFmt.format(amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8)),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: chipColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: chipColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 2),
          Text(value, style: TextStyle(color: chipColor, fontSize: 11)),
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
            Text(
              'تم سداد المبلغ كاملاً',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'يمكنك الآن تسجيل مغادرة العميل',
              style: TextStyle(color: Colors.grey),
            ),
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
            const Text(
              'إضافة دفعة جديدة',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
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
            decoration: const InputDecoration(
              labelText: 'رقم هاتف النزيل',
              border: OutlineInputBorder(),
            ),
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
          child: Text(
            'دفعات سريعة',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildQuickPaymentButton(
                '25%',
                (remaining * 25 / 100).round(),
                summary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildQuickPaymentButton(
                '50%',
                (remaining * 50 / 100).round(),
                summary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildQuickPaymentButton(
                '75%',
                (remaining * 75 / 100).round(),
                summary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildQuickPaymentButton(
                '100%',
                remaining,
                summary,
              ),
            ),
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
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: method.color,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickPaymentButton(
    String label,
    int amount,
    BookingPaymentSummary summary,
  ) {
    return ElevatedButton(
      onPressed: amount > 0
          ? () => _showPaymentDialog(PaymentMethod.cash, amount)
          : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
          Text(
            _currencyFmt.format(amount),
            style: const TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsTab(BookingPaymentSummary summary) {
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
          MaterialPageRoute<void>(builder: (context) =>
                PaymentHistoryScreen(bookingId: widget.booking.localUuid),
          ),
        ),
      ),
      _buildActionCard(
        'تسجيل المغادرة',
        summary.isFullyPaid ? 'تسجيل مغادرة العميل' : 'تحذير: يوجد مبلغ متبقي!',
        Icons.logout,
        summary.isFullyPaid ? Colors.green : Colors.red,
        () => _showCheckoutConfirmation(summary),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  const Text(
                    'معلومات الحجز',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow('رقم الحجز', widget.booking.localUuid),
                  _buildInfoRow(
                    'تاريخ الوصول',
                    widget.booking.checkinDate.split(' ')[0],
                  ),
                  if (widget.booking.checkoutDate != null)
                    _buildInfoRow(
                      'تاريخ المغادرة',
                      widget.booking.checkoutDate!.split(' ')[0],
                    ),
                  _buildInfoRow('الحالة', widget.booking.status),
                  if (widget.booking.notes != null &&
                      widget.booking.notes!.isNotEmpty)
                    _buildInfoRow('ملاحظات', widget.booking.notes!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
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
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog(PaymentMethod method, [int? presetAmount, String? presetNotes, bool isPendingBalance = false]) {
    final amountController = TextEditingController(
      text: presetAmount != null ? presetAmount.toString() : '',
    );
    final notesController = TextEditingController(text: presetNotes ?? '');
    final referenceController = TextEditingController();
    final cardDigitsController = TextEditingController();
    final bankController = TextEditingController();

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
                    decoration: const InputDecoration(
                      labelText: 'المبلغ*',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+'),
                      ),
                    ],
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
                      decoration: const InputDecoration(
                        labelText: 'اسم البنك',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (method == PaymentMethod.transfer ||
                      method == PaymentMethod.check) ...[
                    TextField(
                      controller: referenceController,
                      decoration: const InputDecoration(
                        labelText: 'رقم المرجع/الشيك',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
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
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('تسجيل الدفعة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendPaymentConfirmation(
    double amountPaidNow,
    double remaining,
    String cleanedPhone,
  ) async {
    if (cleanedPhone.isEmpty) {
      return;
    }

    final whatsappService = ref.read(whatsappServiceProvider);

    final message = StringBuffer()
      ..writeln('عزيزي ${widget.booking.guestName}')
      ..writeln(
        'تم استلام دفعتك بقيمة ${_formatAmountForMessage(amountPaidNow)} ريال',
      )
      ..writeln('رقم الغرفة: ${widget.booking.roomNumber}')
      ..writeln('المبلغ المتبقي: ${_formatAmountForMessage(remaining)} ريال')
      ..writeln('شكراً لاختيارك فندق مارينا')
      ..write('للاستفسار: 9677734587456');

    try {
      final result = await whatsappService.sendMessage(
        phoneE164: cleanedPhone,
        message: message.toString(),
      );
      if (result.quotaMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.quotaMessage!), backgroundColor: Colors.orange),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر إرسال رسالة واتساب')),
        );
      }
    }
  }

  /// التحقق من وجود ليالي إضافية
  bool _shouldShowExtendedStayOptions(BookingPaymentSummary summary) {
    final checkin =
        DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final now = DateTime.now();
    final currentStay = HotelDateHelper.calculateNights(checkIn: checkin, checkOut: now);
    final expectedNights = widget.booking.expectedNights;

    // عرض خيارات الليالي الإضافية إذا:
    // 1. الليالي الحالية أكثر من المتوقعة
    // 2. أو إذا كان اليوم الحالي بعد تاريخ المغادرة المخطط
    final plannedCheckout = widget.booking.checkoutDate != null
        ? DateTime.tryParse(widget.booking.checkoutDate!)
        : null;
    final isPastCheckoutDate =
        plannedCheckout != null && now.isAfter(plannedCheckout);

    return currentStay > expectedNights || isPastCheckoutDate;
  }

  /// عرض خيارات دفع الليالي الإضافية
  Widget _buildExtendedStayPaymentOptions(BookingPaymentSummary summary) {
    final checkin =
        DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final now = DateTime.now();
    final currentStay = HotelDateHelper.calculateNights(checkIn: checkin, checkOut: now);
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // دفع سريع للليالي الإضافية
          Row(
            children: [
              Expanded(
                child: _buildDailyPaymentButton('دفع ليلة واحدة', summary, 1),
              ),
              const SizedBox(width: 8),
              if (extraNights >= 2) ...[
                Expanded(
                  child: _buildDailyPaymentButton('دفع ليلتين', summary, 2),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _buildDailyPaymentButton(
                  'دفع كل الإضافي ($extraNights)',
                  summary,
                  extraNights,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// زر دفع سريع للليالي الإضافية
  Widget _buildDailyPaymentButton(
    String label,
    BookingPaymentSummary summary,
    int nights,
  ) {
    final roomsRepo = ref.watch(roomsRepoProvider);

    return StreamBuilder<db.Room?>(
      stream: roomsRepo.watchByNumber(widget.booking.roomNumber),
      builder: (context, roomSnap) {
        final double roomRate = roomSnap.data?.price ?? 0;
        // تطبيق خصم الحجز على سعر الغرفة
        final double discount = widget.booking.discount;
        final double effectiveRate = (discount > 0 && widget.booking.discountType == 'per_night')
            ? (roomRate - discount).clamp(0.0, roomRate)
            : roomRate;
        final amount = nights * effectiveRate;

        return ElevatedButton(
          onPressed: amount > 0
              ? () => _showDailyPaymentDialog(nights, amount)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                _currencyFmt.format(amount),
                style: const TextStyle(fontSize: 11),
              ),
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
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
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
              decoration: const InputDecoration(
                labelText: 'ملاحظات',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () =>
                _processDailyPayment(amount, notesController.text, nights),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('تسجيل الدفعة'),
          ),
        ],
      ),
    );
  }

  /// معالجة دفع الليالي الإضافية
  Future<void> _processDailyPayment(
    double amount,
    String notes,
    int nights,
  ) async {
    final paymentsRepo = ref.read(paymentsRepoProvider);

    await paymentsRepo.create(
      bookingLocalId: widget.booking.id,
      serverBookingId: widget.booking.serverBookingId,
      roomNumber: widget.booking.roomNumber,
      amount: amount,
      paymentDate: Time.nowIso(),
      notes: notes.isEmpty
          ? 'دفع $nights ${nights == 1 ? 'ليلة' : 'ليالي'} إضافية'
          : notes,
      paymentMethod: 'نقدي', // افتراضي، يمكن تحسينه لاحقاً
      revenueType: 'room', // رسوم غرفة للليالي الإضافية
    );

    // ignore: use_build_context_synchronously
    Navigator.pop(context);

    // حساب المتبقي الجديد
    final roomsRepo = ref.read(roomsRepoProvider);
    final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
    final double roomRate = room?.price ?? 0;
    final checkin =
        DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final now = DateTime.now();
    final currentNights = HotelDateHelper.calculateNights(checkIn: checkin, checkOut: now);
    final currentTotal = currentNights * roomRate;
    final allPayments = await paymentsRepo
        .paymentsByBooking(widget.booking.id)
        .first;
    final totalPaid = allPayments.fold<double>(0, (s, p) => s + p.amount);
    double newRemaining = currentTotal - totalPaid;
    if (newRemaining < 0) {
      newRemaining = 0;
    }

    // إرسال رسالة واتساب
    final cleanedPhone = _cleanAndFormatPhone(_currentGuestPhone);
    if (cleanedPhone.isNotEmpty) {
      await _sendExtendedStayPaymentConfirmation(
        amount,
        newRemaining,
        cleanedPhone,
        nights,
      );
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم تسجيل دفع $nights ${nights == 1 ? 'ليلة' : 'ليالي'} إضافية - ${_currencyFmt.format(amount)}',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'إغلاق',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
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
    message +=
        'دفع $nightsPaid ${nightsPaid == 1 ? 'ليلة إضافية' : 'ليالي إضافية'}\n';
    message += 'المبلغ المتبقي: ${_formatAmountForMessage(remaining)} ريال\n';
    message += 'شكراً لاختيارك فندق مارينا\n';
    message += 'للاستفسار: 9677734587456';

    try {
      final result = await whatsappService.sendMessage(
        phoneE164: cleanedPhone,
        message: message,
      );
      if (result.quotaMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.quotaMessage!), backgroundColor: Colors.orange),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر إرسال رسالة واتساب')),
        );
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

    final checkin =
        DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final plannedCheckout = widget.booking.checkoutDate != null
        ? DateTime.tryParse(widget.booking.checkoutDate!)
        : null;
    final actualCheckout = widget.booking.actualCheckout != null
        ? DateTime.tryParse(widget.booking.actualCheckout!)
        : null;
    final actualNights = HotelDateHelper.calculateNights(
      checkIn: checkin,
      checkOut: actualCheckout ?? plannedCheckout,
    );

    final nights =
        await (dbInstance.select(dbInstance.bookingNights)
              ..where((n) => n.bookingLocalId.equals(widget.booking.id))
              ..where((n) => n.deletedAt.isNull()))
            .get();
    final discount = widget.booking.discount;
    final discountType = widget.booking.discountType;
    final discountStartDate = _parseDateTime(widget.booking.discountStartDate);

    final double nightTotal = nights.isNotEmpty
        ? nights.fold<double>(
            0,
            (sum, n) => sum + (n.finalRate > 0 ? n.finalRate : n.nightlyRate),
          )
        : (() {
            final checkout = actualCheckout ?? plannedCheckout;
            if (checkout == null) {
              return actualNights * roomRate;
            }
            if (discount > 0 && discountType == 'per_night') {
              final discountedNights = _countNightsWithDiscount(
                checkin,
                checkout,
                discountStartDate,
              );
              final fullNightsRaw = actualNights - discountedNights;
              final fullNights = fullNightsRaw < 0 ? 0 : fullNightsRaw;
              final discountedRate =
                  (roomRate - discount).clamp(0, roomRate).toDouble();
              return (fullNights * roomRate) +
                  (discountedNights * discountedRate);
            }
            return actualNights * roomRate;
          })();

    final double totalAmount = discount > 0 && discountType == 'total'
        ? (nightTotal - discount).clamp(0, nightTotal).toDouble()
        : nightTotal;
    final payments = await paymentsRepo
        .paymentsByBooking(widget.booking.id)
        .first;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')));
      return;
    }
    if (parsedAmount % 1 != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ يجب أن يكون بدون كسور')),
      );
      return;
    }
    final double amount = parsedAmount;

    setState(() {
      _isSavingPayment = true;
    });

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يمكن حساب الليالي الإضافية')),
          );
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'سيتم تحديث تاريخ المغادرة وإضافة الليالي الجديدة',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
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
        newCheckout = (currentCheckout ?? DateTime.now()).add(
          Duration(days: extraNights),
        );
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
        await bookingsRepo.update(
          widget.booking.id,
          guestPhone: cleanedPhone,
        );
        if (mounted) {
          setState(() {
            _currentGuestPhone = cleanedPhone;
            if (_phoneController.text != cleanedPhone) {
              _phoneController.value = TextEditingValue(
                text: cleanedPhone,
                selection: TextSelection.collapsed(
                  offset: cleanedPhone.length,
                ),
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
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'إغلاق',
            onPressed: messenger.hideCurrentSnackBar,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذّر تسجيل الدفعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPayment = false;
        });
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
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
      // ✅ إصلاح: استخدام guestPhone من الحجز كـ fallback
      final phoneToUse = _currentGuestPhone.isNotEmpty
          ? _currentGuestPhone
          : widget.booking.guestPhone;
      final receipt = Receipt(
        receiptNumber: 'REC${DateTime.now().millisecondsSinceEpoch}',
        payment: payment,
        guestName: widget.booking.guestName,
        guestPhone: phoneToUse,
        roomNumber: widget.booking.roomNumber,
        generatedAt: DateTime.now(),
      );
      await receipt.generatePDF();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء الإيصال: $e')),
        );
      }
    }
  }

  Future<void> _generateInvoice(BookingPaymentSummary summary) async {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      // ✅ إصلاح: استخدام guestPhone من الحجز كـ fallback
      final phoneToUse = _currentGuestPhone.isNotEmpty
          ? _currentGuestPhone
          : widget.booking.guestPhone;
      final checkin =
          DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
      final plannedCheckout = widget.booking.checkoutDate != null
          ? DateTime.tryParse(widget.booking.checkoutDate!)
          : null;
      final actualCheckout = widget.booking.actualCheckout != null
          ? DateTime.tryParse(widget.booking.actualCheckout!)
          : null;
      final checkout = actualCheckout ?? plannedCheckout ?? checkin;
      final roomsRepo = ref.read(roomsRepoProvider);
      final room =
          await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
      final invoice = Invoice(
        invoiceNumber: 'INV${DateTime.now().millisecondsSinceEpoch}',
        bookingId: widget.booking.localUuid,
        guestName: widget.booking.guestName,
        guestPhone: phoneToUse,
        roomNumber: widget.booking.roomNumber,
        checkinDate: checkin,
        checkoutDate: checkout,
        nights: HotelDateHelper.calculateNights(checkIn: checkin, checkOut: checkout),
        roomRate: room?.price ?? 0,
        totalAmount: summary.totalAmount,
        payments: summary.payments,
        remainingAmount: summary.remainingAmount,
        generatedAt: DateTime.now(),
      );
      await invoice.generatePDF();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء الفاتورة: $e')),
        );
      }
    }
  }

  /// نافذة تأكيد المغادرة العادية
  void _showCheckoutConfirmation(BookingPaymentSummary summary) {
    final hasRemaining = summary.remainingAmount > 0;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              hasRemaining ? Icons.warning : Icons.check_circle,
              color: hasRemaining ? Colors.red : Colors.green,
            ),
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
                          'المبلغ المتبقي: ${_currencyFmt.format(summary.remainingAmount)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '⚠️ سيتم خصم المبلغ من راتبكم',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                        fontSize: 14,
                      ),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _processCheckout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: hasRemaining ? Colors.red : Colors.green,
            ),
            child: Text(hasRemaining ? 'متابعة رغم ذلك' : 'تأكيد المغادرة'),
          ),
        ],
      ),
    );
  }

  /// نافذة المغادرة المبكرة مع حساب المردود
  Future<void> _showEarlyCheckoutDialog(BookingPaymentSummary summary) async {
    final dbInstance = ref.read(databaseProvider);
    final checkin =
        DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final now = DateTime.now();
    final plannedCheckout = widget.booking.checkoutDate != null
        ? DateTime.tryParse(widget.booking.checkoutDate!)
        : null;

    if (plannedCheckout == null || !now.isBefore(plannedCheckout)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد مغادرة مبكرة — الحجز انتهى أو لا يوجد تاريخ مغادرة مخطط'),
        ),
      );
      return;
    }

    // حساب الليالي
    final actualNights = HotelDateHelper.calculateNights(checkIn: checkin, checkOut: now);
    final plannedNights = HotelDateHelper.calculateNights(checkIn: checkin, checkOut: plannedCheckout);
    final unusedNights = plannedNights - actualNights;

    if (unusedNights <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد ليالي غير مستخدمة للرد')),
      );
      return;
    }

    // جلب ليالي الحجز لتحسب تكلفة الليالي الفعلية
    final nights = await (dbInstance.select(dbInstance.bookingNights)
          ..where((n) => n.bookingLocalId.equals(widget.booking.id))
          ..where((n) => n.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
        .get();

    // تكلفة الليالي الفعلية المستخدمة
    double actualNightsCost = 0;
    if (nights.isNotEmpty) {
      final effectiveCount = actualNights.clamp(0, nights.length);
      for (int i = 0; i < effectiveCount; i++) {
        actualNightsCost +=
            nights[i].finalRate > 0 ? nights[i].finalRate : nights[i].nightlyRate;
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
    unawaited(showDialog<void>(
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
              _buildRefundInfoRow(
                'الليالي غير المستخدمة',
                '$unusedNights ليلة',
                valueColor: Colors.orange,
              ),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                          fontSize: 16,
                        ),
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          if (refundAmount > 0)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _processEarlyCheckout(
                  refundAmount.round(),
                  unusedNights,
                  actualNights,
                );
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
    ),);
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
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  /// معالجة المغادرة المبكرة مع تسجيل المردود
  Future<void> _processEarlyCheckout(
    int refundAmount,
    int unusedNights,
    int actualNights,
  ) async {
    try {
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
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'إغلاق',
            textColor: Colors.white,
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ خطأ في المغادرة المبكرة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تسجيل المغادرة المبكرة: $e'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// رسالة واتساب تأكيد المردود
  Future<void> _sendRefundConfirmation(
    int refundAmount,
    int unusedNights,
    String cleanedPhone,
  ) async {
    if (cleanedPhone.isEmpty) {
      return;
    }
    final whatsappService = ref.read(whatsappServiceProvider);

    String message = 'عزيزي ${widget.booking.guestName}، تم تسجيل مغادرتكم المبكرة\n';
    message += 'رقم الغرفة: ${widget.booking.roomNumber}\n';
    message +=
        'مبلغ المردود: ${_formatAmountForMessage(refundAmount)} ريال\n';
    message +=
        'عدد الليالي غير المستخدمة: $unusedNights ${unusedNights == 1 ? 'ليلة' : 'ليالي'}\n';
    message += 'شكراً لاختيارك فندق مارينا\n';
    message += 'للاستفسار: 9677734587456';

    try {
      final result = await whatsappService.sendMessage(
        phoneE164: cleanedPhone,
        message: message,
      );
      if (result.quotaMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.quotaMessage!), backgroundColor: Colors.orange),
        );
      }
    } catch (_) {
      // تجاهل الأخطاء
    }
  }

  /// معالجة المغادرة العادية
  Future<void> _processCheckout() async {
    try {
      final bookingsRepo = ref.read(bookingsRepoProvider);
      final roomsRepo = ref.read(roomsRepoProvider);
      final nowIso = Time.nowIso();
      final checkin =
          DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
      final nowDate = DateTime.parse(nowIso);
      final actualNights = HotelDateHelper.calculateNights(checkIn: checkin, checkOut: nowDate);
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
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('تم تسجيل المغادرة بنجاح وتحرير الغرفة'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'إغلاق',
            textColor: Colors.white,
            onPressed: messenger.hideCurrentSnackBar,
          ),
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
            duration: const Duration(seconds: 5),
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
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }

          final allPayments = snapshot.data ?? [];
          final todayPayments = allPayments.where((p) =>
              !p.isVoided &&
              (p.hotelDayKey == hotelDay ||
                  (p.hotelDayKey == null &&
                      p.paymentDate.startsWith(hotelDay))),).toList();

          if (todayPayments.isEmpty) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('لا توجد دفعات اليوم'),
                ],
              ),
              content: const Text(
                'لا توجد مدفوعات مسجلة في اليوم الفندقي الحالي لإلغائها.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                ),
              ],
            );
          }

          final todayTotal = todayPayments.fold<double>(
              0, (s, p) => s + p.amount,);

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
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'عدد المدفوعات المراد إلغاؤها: ${todayPayments.length}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إجمالي المبلغ المراد إلغاؤه: ${_currencyFmt.format(todayTotal)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.red,
                          ),
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...todayPayments.map((p) => Padding(
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
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
  Future<void> _processCancelTodayPayments(
      List<db.Payment> paymentsToCancel,) async {
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
          content: Text(
            'تم إلغاء ${paymentsToCancel.length} دفعة بنجاح',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'إغلاق',
            textColor: Colors.white,
            onPressed: messenger.hideCurrentSnackBar,
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ خطأ في إلغاء دفعات اليوم: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إلغاء الدفعات: $e'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _sendAccountStatement(BookingPaymentSummary summary) {
    if (_currentGuestPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد رقم هاتف للعميل'),
          backgroundColor: Colors.red,
        ),
      );
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
                      _buildStatementPreviewRow(
                        'العميل',
                        widget.booking.guestName,
                      ),
                      _buildStatementPreviewRow(
                        'الغرفة',
                        widget.booking.roomNumber,
                      ),
                      _buildStatementPreviewRow(
                        'الهاتف',
                        _currentGuestPhone,
                      ),
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
                        valueColor: summary.remainingAmount > 0
                            ? Colors.red
                            : Colors.green,
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
                  icon: Icon(
                    _showFullPreview
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 16,
                  ),
                  label: Text(
                    _showFullPreview
                        ? 'إخفاء المعاينة'
                        : 'معاينة الرسالة',
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
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          fontFamily: 'Courier',
                        ),
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _performSendAccountStatement(summary);
              },
              icon: const Icon(Icons.send, size: 18),
              label: const Text('إرسال واتساب'),
            ),
          ],
        ),
      ),
    );
  }

  bool _showFullPreview = false;

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

  Widget _buildStatementPreviewRow(
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: valueColor,
                fontSize: 13,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performSendAccountStatement(
    BookingPaymentSummary summary,
  ) async {
    final whatsappService = ref.read(whatsappServiceProvider);
    final message = _buildAccountStatementMessage(summary);

    // إظهار مؤشر التحميل
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('جاري إرسال كشف الحساب...'),
            ],
          ),
          duration: Duration(seconds: 30),
          backgroundColor: Colors.orange,
        ),
      );
    }

    try {
      final cleanedPhone = _cleanAndFormatPhone(_currentGuestPhone);
      final result = await whatsappService.sendMessage(
        phoneE164: cleanedPhone,
        message: message,
      );
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
                  Icon(
                    success ? Icons.check_circle : Icons.error,
                    color: Colors.white,
                  ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا يوجد رقم هاتف للعميل')));
      return;
    }

    final whatsappService = ref.read(whatsappServiceProvider);

    // بناء رسالة تذكير بسيطة
    String reminder = 'عزيزي ${widget.booking.guestName}\n';
    reminder += 'تذكير بالمبلغ المتبقي\n';
    reminder += 'رقم الغرفة: ${widget.booking.roomNumber}\n';
    reminder +=
        'المبلغ الإجمالي: ${_currencyFmt.format(summary.totalAmount)}\n';
    reminder += 'المبلغ المدفوع: ${_currencyFmt.format(summary.paidAmount)}\n';
    reminder +=
        'المبلغ المتبقي: ${_currencyFmt.format(summary.remainingAmount)}\n\n';
    reminder += 'نرجو منكم تسديد المبلغ المتبقي في أقرب وقت ممكن\n\n';
    reminder += 'شكراً لتعاونكم معنا\n';
    reminder += 'للاستفسار: 9677734587456';

    try {
      final cleanedPhone = _cleanAndFormatPhone(_currentGuestPhone);
      final result = await whatsappService.sendMessage(
        phoneE164: cleanedPhone,
        message: reminder,
      );

      if (mounted) {
        if (result.quotaMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.quotaMessage!),
              backgroundColor: Colors.orange,
            ),
          );
        } else if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إرسال تذكير الدفع للعميل بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل في إرسال تذكير الدفع'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إرسال التذكير: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
          // تطبيق خصم الحجز على سعر الغرفة
          final double discount = widget.booking.discount;
          final double effectiveRate = (discount > 0 && widget.booking.discountType == 'per_night')
              ? (roomRate - discount).clamp(0.0, roomRate)
              : roomRate;

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
                final totalCost = nights * effectiveRate;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
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
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _processExtendStay(
                    int.tryParse(nightsController.text) ?? 1,
                    roomRate,
                    notesController.text,
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('تمديد وتسجيل دفعة'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// معالجة تمديد الإقامة
  Future<void> _processExtendStay(
    int additionalNights,
    double roomRate,
    String notes,
  ) async {
    if (additionalNights <= 0 || roomRate <= 0) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال عدد ليالي صحيح وسعر غرفة صحيح'),
          backgroundColor: Colors.red,
        ),
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

      final newCheckout = (currentCheckout ?? DateTime.now()).add(
        Duration(days: additionalNights),
      );

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
        await _sendExtensionConfirmation(
          additionalNights,
          amount,
          newCheckout,
          cleanedPhone,
        );
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تمديد الإقامة $additionalNights ${additionalNights == 1 ? 'ليلة' : 'ليالي'} وتسجيل الدفعة',
          ),
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
      debugPrint('❌ خطأ في تمديد الإقامة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تمديد الإقامة: $e'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 5),
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
    message +=
        'ليالي إضافية: $additionalNights ${additionalNights == 1 ? 'ليلة' : 'ليالي'}\n';
    message += 'المبلغ المدفوع: ${_formatAmountForMessage(amount)} ريال\n';
    message +=
        'تاريخ المغادرة الجديد: ${newCheckout.day}/${newCheckout.month}/${newCheckout.year}\n';
    message += 'شكراً لاختيارك فندق مارينا\n';
    message += 'للاستفسار: 9677734587456';

    try {
      final result = await whatsappService.sendMessage(
        phoneE164: cleanedPhone,
        message: message,
      );
      if (result.quotaMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.quotaMessage!), backgroundColor: Colors.orange),
        );
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
