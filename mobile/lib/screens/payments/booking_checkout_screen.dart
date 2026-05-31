import 'dart:async';

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

  const BookingCheckoutScreen({super.key, required this.booking});
  final Booking booking;

  @override
  ConsumerState<BookingCheckoutScreen> createState() =>
      _BookingCheckoutScreenState();
}

class _BookingCheckoutScreenState extends ConsumerState<BookingCheckoutScreen>
    with SyncOnExitMixin {
  @override
  String get screenId => 'booking_checkout';
  bool _isProcessing = false;
  StreamSubscription<void>? _hotelDayTickerSub;

  @override
  void initState() {
    super.initState();
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

  Future<void> _refreshBookingNights() async {
    final db = ref.read(databaseProvider);
    final derivedService = BookingDerivedFieldsService(db);
    await derivedService.refreshForBookingId(widget.booking.id);
  }

  DateTime? _parseDateTime(String? value) => DateParser.parse(value);

  @override
  void dispose() {
    _hotelDayTickerSub?.cancel();
    super.dispose();
  }

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
  Widget build(BuildContext context) {
    final paymentsRepo = ref.watch(paymentsRepoProvider);
    final roomsRepo = ref.watch(roomsRepoProvider);

    // ✅ إصلاح: استخدام HotelDateHelper بدلاً من DateTime.now()
    // لضمان اتساق الحسابات عند إعادة فتح الشاشة
    // اليوم الفندقي (14:00 -> 14:00) يضمن ثبات الحسابات
    final now = HotelDateHelper.getHotelDay(DateTime.now());
    // ignore: unused_local_variable
    final hotelDayNow = HotelDateHelper.getHotelDayKey();

    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'دفع الحجز',
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
                : (checkin != null
                      ? HotelDateHelper.calculateNights(
                          checkIn: checkin,
                          checkOut: plannedCheckout,
                        )
                      : 1);
            // ✅ إصلاح: استخدام تاريخ اليوم الفندقي بدلاً من DateTime.now()
            // هذا يضمن اتساق الحسابات عند إعادة فتح الشاشة في أوقات مختلفة
            //Guest who hasn't checked out: use HotelDay for consistent calculations
            final effectiveCheckout = actualCheckout ?? now;
            final hasNotCheckedOut = actualCheckout == null;
            final nowIsAfterCutoff = HotelDateHelper.isNowAfterCutoff();
            final actualNights = checkin != null
                ? HotelDateHelper.calculateNights(
                    checkIn: checkin,
                    checkOut: effectiveCheckout,
                  )
                : expectedNights;

            final dbInstance = ref.watch(databaseProvider);
            final discount = widget.booking.discount;
            final discountType = widget.booking.discountType;
            final discountStartDate = _parseDateTime(
              widget.booking.discountStartDate,
            );

            return StreamBuilder<List<BookingNight>>(
              stream:
                  (dbInstance.select(dbInstance.bookingNights)
                        ..where(
                          (n) => n.bookingLocalId.equals(widget.booking.id),
                        )
                        ..where((n) => n.deletedAt.isNull()))
                      .watch(),
              builder: (context, nightsSnap) {
                final nights = nightsSnap.data ?? const <BookingNight>[];
                final nightsCount = nights.isNotEmpty
                    ? nights.length
                    : actualNights;
                final nightTotal = nights.isNotEmpty
                    ? nights.fold<double>(0, (sum, n) =>
                        sum + (n.finalRate > 0 ? n.finalRate : n.nightlyRate))
                    : (() {
                        // ✅ إصلاح: استخدام effectiveCheckout (الذي هو now أو actualCheckout)
                        final checkout = effectiveCheckout;
                        if (discount > 0 && discountType == 'per_night' && checkin != null) {
                          final discountedNights = _countNightsWithDiscount(
                            checkin,
                            checkout,
                            discountStartDate,
                          );
                          final fullNights = (actualNights - discountedNights)
                              .clamp(0, actualNights).toInt();
                          final discountedRate = (roomPrice - discount).clamp(
                            0.0,
                            roomPrice,
                          ).toDouble();
                          return (fullNights * roomPrice) +
                              (discountedNights * discountedRate);
                        }
                        return actualNights * roomPrice;
                      })();

                final totalDue = discount > 0 && discountType == 'total'
                    ? (nightTotal - discount).clamp(0.0, nightTotal).toDouble()
                    : nightTotal;

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'معلومات الحجز',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
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
                              if (actualCheckout != null)
                                Text('الليالي الفعلية: $nightsCount'),
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
                              Text(
                                'سعر الليلة: ${CurrencyFormatter.formatAmount(roomPrice)}',
                              ),
                              if (discount > 0)
                                Text(
                                  'التخفيض: ${CurrencyFormatter.formatAmount(discount)}',
                                  style: const TextStyle(color: Colors.purple),
                                ),
                              Text(
                                'المبلغ المستحق: ${CurrencyFormatter.formatAmount(totalDue)}',
                              ),
                              Text('الحالة: ${widget.booking.status}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'المدفوعات السابقة',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        flex: 2,
                        child: StreamBuilder<List<Payment>>(
                          stream: paymentsRepo.paymentsByBooking(
                            widget.booking.id,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final payments = snapshot.data ?? const <Payment>[];
                            if (payments.isEmpty) {
                              return const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text(
                                    'لا توجد مدفوعات سابقة',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }

                            // ✅ استبعاد المدفوعات الملغاة
                            final totalPaid = payments
                                .where((p) => !p.isVoided)
                                .fold<double>(
                                  0,
                                  (sum, payment) => sum + payment.amount,
                                );
                            final remainingAmount = (totalDue - totalPaid)
                                .clamp(0, totalDue)
                                .toDouble();

                            return Column(
                              children: [
                                Card(
                                  color: Colors.blue.shade50,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildSummaryRow(
                                          'المبلغ المستحق',
                                          totalDue,
                                          Colors.blue,
                                        ),
                                        const SizedBox(height: 6),
                                        _buildSummaryRow(
                                          'إجمالي المدفوع',
                                          totalPaid,
                                          Colors.green,
                                        ),
                                        const SizedBox(height: 6),
                                        _buildSummaryRow(
                                          'المتبقي',
                                          remainingAmount,
                                          remainingAmount <= 0
                                              ? Colors.green
                                              : Colors.red,
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
                                              payment.paymentMethod == 'تحويل'
                                                  ? Icons.account_balance
                                                  : Icons.money,
                                              color:
                                                  payment.paymentMethod == 'تحويل'
                                                  ? Colors.blue
                                                  : Colors.green,
                                            ),
                                            title: Text(
                                              CurrencyFormatter.formatAmount(
                                                payment.amount,
                                              ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'طريقة الدفع: ${payment.paymentMethod}',
                                                ),
                                                Text(
                                                  'النوع: ${payment.revenueType}',
                                                ),
                                                Text(
                                                  'التاريخ: ${payment.paymentDate}',
                                                ),
                                                if (payment.notes != null &&
                                                    payment.notes!.isNotEmpty)
                                                  Text(
                                                    'ملاحظات: ${payment.notes}',
                                                  ),
                                              ],
                                            ),
                                            trailing: payment.roomNumber != null
                                                ? Chip(
                                                    label: Text(
                                                      payment.roomNumber!,
                                                    ),
                                                    backgroundColor:
                                                        Colors.blue.shade50,
                                                  )
                                                : null,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing
                                  ? null
                                  : () => _addPayment(context),
                              icon: const Icon(Icons.add_circle),
                              label: const Text('إضافة دفعة جديدة'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StreamBuilder<List<Payment>>(
                              stream: paymentsRepo.paymentsByBooking(
                                widget.booking.id,
                              ),
                              builder: (context, snapshot) {
                                // ✅ استبعاد المدفوعات الملغاة
                                final totalPaid =
                                    snapshot.data
                                        ?.where((p) => !p.isVoided)
                                        .fold<double>(
                                          0,
                                          (sum, payment) => sum + payment.amount,
                                        ) ??
                                    0.0;
                                final remainingAmount = (totalDue - totalPaid)
                                    .clamp(0, totalDue).toDouble();
                                return ElevatedButton.icon(
                                  onPressed:
                                      _isProcessing || remainingAmount > 0
                                      ? null
                                      : () => _completeCheckout(context),
                                  icon: const Icon(Icons.check_circle),
                                  label: const Text('إتمام الحجز'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
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
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        Text(
          CurrencyFormatter.formatAmount(amount),
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
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
                    DropdownMenuItem(value: 'نقدي', child: Text('نقدي', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyMedium?.color))),
                    DropdownMenuItem(value: 'تحويل', child: Text('تحويل بنكي', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyMedium?.color))),
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
                    DropdownMenuItem(value: 'room', child: Text('إيراد غرفة', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyMedium?.color))),
                    DropdownMenuItem(
                      value: 'service',
                      child: Text('خدمات إضافية', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyMedium?.color)),
                    ),
                    DropdownMenuItem(value: 'deposit', child: Text('عربون', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyMedium?.color))),
                    DropdownMenuItem(value: 'other', child: Text('أخرى', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyMedium?.color))),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result ?? false) {
      final parsedAmount =
          CurrencyFormatter.parseAmount(amountController.text);
      if (parsedAmount == null || parsedAmount <= 0) {
        // ignore: use_build_context_synchronously
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

        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تم إضافة الدفعة بنجاح'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'إغلاق',
              textColor: Colors.white,
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            ),
          ),
        );
      } catch (e) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
        );
      } finally {
        setState(() => _isProcessing = false);
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
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
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
      setState(() => _isProcessing = true);

      try {
        final bookingsRepo = ref.read(bookingsRepoProvider);
        final roomsRepo = ref.read(roomsRepoProvider);

        // ✅ تحديث حالة الحجز + حالة الغرفة في معاملة واحدة
        final nowIso = Time.nowIso();
        final checkin =
            DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
        final nowDate = DateTime.parse(nowIso);
        final actualNights = HotelDateHelper.calculateNights(checkIn: checkin, checkOut: nowDate);

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

        if (mounted) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تم إتمام الحجز بنجاح'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'إغلاق',
                textColor: Colors.white,
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              ),
            ),
          );
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isProcessing = false);
        }
      }
    }
  }
}
