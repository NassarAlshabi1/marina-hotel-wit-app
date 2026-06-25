import 'dart:async';

import 'package:drift/drift.dart' as d;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/repository_providers.dart';
import '../../services/booking_derived_fields_service.dart';
import '../../services/local_db.dart';
import '../../utils/app_logger.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_parser.dart';
import '../../utils/hotel_date_helper.dart';
import '../../utils/hotel_day_ticker.dart';
import '../../utils/time.dart';

/// قرار المستخدم بشأن الليالي المنسية المُضافة تلقائياً بعد موعد المغادرة
enum ForgottenNightsDecision {
  /// لا توجد ليالٍ منسية — تابع العملية بشكل طبيعي
  noForgottenNights,
  /// احتساب جميع الليالي بما فيها المنسية
  countAll,
  /// حذف الليالي الإضافية ثم المتابعة
  cancelExtra,
  /// إلغاء العملية بالكامل
  userCancelled,
}

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
    final paymentsRepo = ref.watch(paymentsRepoProvider);
    final roomsRepo = ref.watch(roomsRepoProvider);

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
                      ? Time.nightsWithCutoff(
                          checkin,
                          checkout: plannedCheckout,
                        )
                      : 1);
            // ✅ الليالي المتوقعة الأصلية تُحسب من تواريخ الحجز الأصلية
            // (لا تعتمد على booking.expectedNights لأنها تُحدّث ديناميكياً
            //  بواسطة BookingDerivedFieldsService لتساوي actualNights).
            // هذا ضروري لاكتشاف الليالي المنسية بدقة.
            final originalExpectedNights = (checkin != null && plannedCheckout != null)
                ? Time.nightsWithCutoff(checkin, checkout: plannedCheckout)
                : expectedNights;
            // إذا لم يسجل النزيل خروج، نستخدم الوقت الحالي لحساب الليالي
            // حتى يتم تطبيق قاعدة الساعة 14:00 (إضافة ليلة إذا تجاوزت الساعة 14)
            final effectiveCheckout = actualCheckout ?? DateTime.now();
            final hasNotCheckedOut = actualCheckout == null;
            final nowIsAfterCutoff = HotelDateHelper.isNowAfterCutoff();
            final actualNights = checkin != null
                ? Time.nightsWithCutoff(
                    checkin,
                    checkout: effectiveCheckout,
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
                    // ✅ إصلاح حرج: استخدام finalRate بدلاً من nightlyRate
                    // finalRate يتضمن تعديلات الأسعار (خصومات/إضافات)
                    // nightlyRate هو السعر الأساسي بدون تعديلات → يُسبب مبلغ خاطئ عند الخروج
                    ? nights.fold<double>(0, (sum, n) => sum + (n.finalRate > 0 ? n.finalRate : n.nightlyRate))
                    : (() {
                        final checkout = actualCheckout ?? DateTime.now();
                        if (discount > 0 && discountType == 'per_night' && checkin != null) {
                          final discountedNights = _countNightsWithDiscount(
                            checkin,
                            checkout,
                            discountStartDate,
                          );
                          final fullNights = (actualNights - discountedNights)
                              .clamp(0, actualNights);
                          final discountedRate = (roomPrice - discount).clamp(
                            0.0,
                            roomPrice,
                          );
                          return (fullNights * roomPrice) +
                              (discountedNights * discountedRate);
                        }
                        return actualNights * roomPrice;
                      })();

                final totalDue = discount > 0 && discountType == 'total'
                    ? (nightTotal - discount).clamp(0.0, nightTotal)
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
                              // ✅ نستخدم originalExpectedNights (المحسوبة من plannedCheckout)
                              //    بدلاً من expectedNights التي تُحدّث ديناميكياً
                              if (hasNotCheckedOut && nowIsAfterCutoff && actualNights > originalExpectedNights)
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
                                        'تمت إضافة ${actualNights - originalExpectedNights} ليلة بعد الساعة 14:00 (لم يسجل النزيل خروج)',
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

                                // المبلغ المتبقي > 0 → زر "تسجيل خروج" برتقالي
                                if (remainingAmount > 0) {
                                  return ElevatedButton.icon(
                                    onPressed: _isProcessing
                                        ? null
                                        : () => _checkoutWithDebt(
                                              context,
                                              remainingAmount,
                                              nights: nights,
                                              originalExpectedNights: originalExpectedNights,
                                              actualNights: actualNights,
                                              checkin: checkin,
                                              plannedCheckout: plannedCheckout,
                                            ),
                                    icon: const Icon(Icons.logout),
                                    label: const Text('تسجيل خروج'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                    ),
                                  );
                                }

                                // المبلغ = 0 → زر "إتمام الحجز" أزرق كما كان
                                return ElevatedButton.icon(
                                  onPressed: _isProcessing
                                      ? null
                                      : () => _completeCheckout(
                                            context,
                                            nights: nights,
                                            originalExpectedNights: originalExpectedNights,
                                            actualNights: actualNights,
                                            checkin: checkin,
                                            plannedCheckout: plannedCheckout,
                                          ),
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
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
    } finally {
      amountController.dispose();
      notesController.dispose();
    }
  }

  // ──────────────────────────────────────────────────────────────
  // نظام احترافي لمعالجة النسيان — فحص الليالي الإضافية التلقائية
  // ──────────────────────────────────────────────────────────────

  /// تنسيق التاريخ بصيغة عربية قصيرة (يوم/شهر/سنة)
  String _formatArabicDate(String isoOrKey) {
    try {
      final normalized = isoOrKey.contains('T')
          ? isoOrKey
          : '${isoOrKey}T00:00:00';
      final dt = DateTime.parse(normalized);
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
    } catch (_) {
      return isoOrKey;
    }
  }

  /// فحص وجود ليالٍ إضافية تلقائية بعد تاريخ المغادرة المتوقع.
  ///
  /// المنطق الاحترافي:
  /// - يحسب **الليالي المتوقعة الأصلية** مباشرة من `checkin + plannedCheckout`
  ///   (ولا يعتمد على `booking.expectedNights` لأنها تُحدّث ديناميكياً
  ///    بواسطة BookingDerivedFieldsService ← ستساوي دائماً actualNights).
  /// - يحسب **الليالي الفعلية** من `checkin → now` (إذا لم يُسجل الخروج بعد).
  /// - إذا كان الفعلي > المتوقع الأصلي، فهناك ليالٍ إضافية تلقائية
  ///   ناتجة على الأرجح عن نسيان الموظف تسجيل الخروج في الوقت.
  /// - يستخدم سجلات `BookingNight` لعرض التواريخ إن وُجدت، وإلا يحسبها
  ///   من تاريخ الدخول + عدد الليالي المتوقعة الأصلية.
  Future<ForgottenNightsDecision> _checkForgottenNights(
    BuildContext context, {
    required List<BookingNight> nights,
    required int originalExpectedNights,
    required int actualNights,
    required DateTime? checkin,
    required DateTime? plannedCheckout,
  }) async {
    // ⚠️ إذا لم يكن هناك موعد مغادرة مخطط، فلا يمكن تحديد "ليالٍ منسية"
    if (plannedCheckout == null || checkin == null) {
      return ForgottenNightsDecision.noForgottenNights;
    }
    if (originalExpectedNights <= 0) {
      return ForgottenNightsDecision.noForgottenNights;
    }

    // ✅ المعيار الأساسي: actualNights > originalExpectedNights
    // (لا نعتمد على nights.length لأن السجلات قد لا تكون مُحدّثة بعد)
    final extraCount = actualNights - originalExpectedNights;
    AppLogger.info(
      '🔍 فحص الليالي المنسية: actualNights=$actualNights, '
      'originalExpectedNights=$originalExpectedNights, '
      'extraCount=$extraCount, nightsRecords=${nights.length}',
      tag: 'CHECKOUT',
    );
    if (extraCount <= 0) {
      return ForgottenNightsDecision.noForgottenNights;
    }

    // تجهيز قائمة تواريخ الليالي الإضافية
    // الأولوية: سجلات BookingNight إن وُجدت، وإلا نحسبها من checkin.
    final List<String> extraDates = [];

    if (nights.isNotEmpty) {
      final sortedNights = [...nights]
        ..sort((a, b) => a.hotelDayKey.compareTo(b.hotelDayKey));
      final extraNights = sortedNights.length > originalExpectedNights
          ? sortedNights.sublist(originalExpectedNights)
          : <BookingNight>[];
      for (final n in extraNights) {
        extraDates.add(n.hotelDayKey);
      }
    }

    // إذا لم توجد سجلات كافية، نحسب التواريخ مباشرة من checkin
    if (extraDates.length < extraCount) {
      extraDates.clear();
      // بداية اليوم الفندقي لليلة الأولى بعد الموعد المتوقع
      // قاعدة اليوم الفندقي: اليوم يبدأ عند 14:01 (hotelStartHour=14, hotelStartMinute=1)
      // لذلك نستخدم HotelDateHelper.getHotelDay لتحديد "يوم الفندق" لكل ليلة
      final checkinHotelDay = HotelDateHelper.getHotelDay(checkin);
      // أول ليلة إضافية تبدأ بعد originalExpectedNights يوم من يوم الدخول الفندقي
      for (int i = 0; i < extraCount; i++) {
        final extraDay = checkinHotelDay.add(Duration(days: originalExpectedNights + i));
        extraDates.add(Time.dateToString(extraDay));
      }
    }

    final extraDatesText = extraDates
        .map((d) => '• ${_formatArabicDate(d)}')
        .join('\n');

    final pluralized = extraCount == 1
        ? 'ليلة واحدة'
        : '$extraCount ليالٍ';
    final originalCheckoutStr = _formatArabicDate(Time.dateToString(plannedCheckout));

    // عرض حوار الخيارات للمستخدم (المدير/الموظف المخوّل)
    if (!mounted) return ForgottenNightsDecision.userCancelled;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.orange.shade700, size: 28),
              const SizedBox(width: 8),
              const Expanded(child: Text('تنبيه: ليالٍ إضافية تلقائية')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تمت إضافة $pluralized بعد موعد المغادرة المتوقع ($originalCheckoutStr)، '
                  'يُحتمل أن يكون السبب نسيان تسجيل الخروج في الوقت المحدد.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الليالي الإضافية المُضافة:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        extraDatesText,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'هل تريد احتساب هذه الليالي أم إلغاؤها؟',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: const Text('إلغاء العملية'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(ctx).pop('cancel_extra'),
              icon: const Icon(Icons.delete_sweep, size: 18),
              label: const Text('إلغاء الليالي الإضافية'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(ctx).pop('count_all'),
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('احتساب الليالي'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    switch (result) {
      case 'count_all':
        return ForgottenNightsDecision.countAll;
      case 'cancel_extra':
        // حذف الليالي الإضافية (soft-delete) — نمرّر السجلات إن وُجدت
        final sortedNights = nights.isNotEmpty
            ? ([...nights]..sort((a, b) => a.hotelDayKey.compareTo(b.hotelDayKey)))
            : <BookingNight>[];
        final extraNightsRecords = sortedNights.length > originalExpectedNights
            ? sortedNights.sublist(originalExpectedNights)
            : <BookingNight>[];
        if (extraNightsRecords.isNotEmpty) {
          await _softDeleteExtraNights(extraNightsRecords);
        }
        // إعادة بناء الحقول المشتقة للحجز ليعكس المبلغ الجديد
        await _refreshBookingNights();
        return ForgottenNightsDecision.cancelExtra;
      default:
        return ForgottenNightsDecision.userCancelled;
    }
  }

  /// Soft-delete لسجلات الليالي الإضافية (وضع علامة deletedAt)
  Future<void> _softDeleteExtraNights(
    List<BookingNight> extraNights,
  ) async {
    if (extraNights.isEmpty) return;
    final db = ref.read(databaseProvider);
    final nowUtc = DateTime.now().toUtc();
    final stamp = nowUtc.millisecondsSinceEpoch ~/ 1000;
    final stampIso = nowUtc.toIso8601String();

    await db.transaction(() async {
      for (final night in extraNights) {
        await (db.update(db.bookingNights)
              ..where((n) => n.id.equals(night.id)))
            .write(BookingNightsCompanion(
          deletedAt: d.Value(stamp),
          deletedAtIso: d.Value(stampIso),
          updatedAt: d.Value(stamp),
          updatedAtIso: d.Value(stampIso),
          lastModified: d.Value(stamp),
          lastModifiedEpoch: d.Value(stamp),
          version: d.Value(night.version + 1),
        ));
      }
    });

    AppLogger.warning(
      '🗑️ تم حذف ${extraNights.length} ليلة إضافية للحجز ${widget.booking.id} '
      '(سبب محتمل: نسيان تسجيل الخروج)',
      tag: 'CHECKOUT',
    );
  }

  /// تسجيل خروج مع خيارات الدين عند وجود مبلغ متبقي
  Future<void> _checkoutWithDebt(
    BuildContext context,
    double remainingAmount, {
    required List<BookingNight> nights,
    required int originalExpectedNights,
    required int actualNights,
    required DateTime? checkin,
    required DateTime? plannedCheckout,
  }) async {
    // ─── فحص الليالي الإضافية المنسية قبل المتابعة ───
    final forgottenDecision = await _checkForgottenNights(
      context,
      nights: nights,
      originalExpectedNights: originalExpectedNights,
      actualNights: actualNights,
      checkin: checkin,
      plannedCheckout: plannedCheckout,
    );
    if (forgottenDecision == ForgottenNightsDecision.userCancelled) {
      return; // المستخدم ألغى العملية بالكامل
    }
    if (!context.mounted) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تسجيل خروج'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'النزيل لم يسدد المبلغ الكامل. هل ترغب في؟',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'المبلغ المتبقي:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      CurrencyFormatter.formatAmount(remainingAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop('no_debt'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade600,
                foregroundColor: Colors.white,
              ),
              child: const Text('تسجيل خروج بدون دين'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop('with_debt'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('تسجيل خروج مع دين'),
            ),
          ],
        ),
      ),
    );

    if (choice == null || choice == 'cancel') return;
    if (!mounted) return;

    setState(() => _isProcessing = true);

    try {
      final bookingsRepo = ref.read(bookingsRepoProvider);
      final roomsRepo = ref.read(roomsRepoProvider);

      // ✅ تحديث حالة الحجز → مكتمل + خروج
      final nowIso = Time.nowIso();
      final checkin =
          DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
      final nowDate = DateTime.parse(nowIso);
      final actualNights = Time.nightsWithCutoff(checkin, checkout: nowDate);

      await bookingsRepo.update(
        widget.booking.id,
        status: 'مكتمل',
        actualCheckout: nowIso,
        calculatedNights: actualNights,
      );

      // ✅ تحديث الغرفة → شاغرة
      await roomsRepo.refreshAllRoomOccupancy();
      markDataChanged();

      if (!mounted) return;

      if (choice == 'with_debt') {
        // ✅ إنشاء دين في قائمة الديون
        final debtsRepo = ref.read(debtsRepoProvider);
        await debtsRepo.create(
          bookingLocalId: widget.booking.id,
          guestName: widget.booking.guestName,
          checkinDate: widget.booking.checkinDate,
          checkoutDate: nowIso,
          debtReason: 'مبلغ متبقي بعد تسجيل الخروج',
          totalAmount: remainingAmount,
          paidAmount: 0,
          paymentDate: nowIso,
          note:
              'حجز غرفة ${widget.booking.roomNumber} — مبلغ متبقي بعد تسجيل الخروج',
        );

        if (mounted) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم تسجيل الخروج وإضافة دين بقيمة ${CurrencyFormatter.formatAmount(remainingAmount)} إلى قائمة الديون',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
        }
      } else {
        // no_debt — إغلاق الحجز مباشرة بدون إنشاء دين
        if (mounted) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تم تسجيل الخروج بنجاح بدون دين'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
        }
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

  Future<void> _completeCheckout(
    BuildContext context, {
    required List<BookingNight> nights,
    required int originalExpectedNights,
    required int actualNights,
    required DateTime? checkin,
    required DateTime? plannedCheckout,
  }) async {
    // ─── فحص الليالي الإضافية المنسية قبل المتابعة ───
    final forgottenDecision = await _checkForgottenNights(
      context,
      nights: nights,
      originalExpectedNights: originalExpectedNights,
      actualNights: actualNights,
      checkin: checkin,
      plannedCheckout: plannedCheckout,
    );
    if (forgottenDecision == ForgottenNightsDecision.userCancelled) {
      return; // المستخدم ألغى العملية بالكامل
    }
    if (!context.mounted) return;

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

        if (mounted) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تم إتمام الحجز بنجاح'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
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
