import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/booking_derived_fields_service.dart';
import '../../services/local_db.dart';
import '../../utils/time.dart';
import '../../utils/currency_formatter.dart';
import '../../mixins/sync_on_exit_mixin.dart';

class BookingCheckoutScreen extends ConsumerStatefulWidget {
  final Booking booking;

  const BookingCheckoutScreen({super.key, required this.booking});

  @override
  ConsumerState<BookingCheckoutScreen> createState() =>
      _BookingCheckoutScreenState();
}

class _BookingCheckoutScreenState extends ConsumerState<BookingCheckoutScreen>
    with SyncOnExitMixin {
  @override
  String get screenId => 'booking_checkout';
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _refreshBookingNights();
  }

  Future<void> _refreshBookingNights() async {
    final db = ref.read(databaseProvider);
    final derivedService = BookingDerivedFieldsService(db);
    await derivedService.refreshForBookingId(widget.booking.id);
  }

  DateTime? _parseDateTime(String? value) {
    if (value == null) return null;
    final v = value.trim();
    if (v.isEmpty) return null;
    final normalized = v.contains('T') ? v : v.replaceFirst(' ', 'T');
    final withSeconds = normalized.length == 16
        ? '${normalized}:00'
        : normalized;
    try {
      return DateTime.parse(withSeconds);
    } catch (_) {
      return null;
    }
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
        title: 'دفع الحجز والمغادرة',
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
            
            // حساب الليالي الفعلية بناءً على الوقت الحالي إذا لم يغادر بعد
            final now = DateTime.now();
            final effectiveCheckout = actualCheckout ?? now;
            
            final expectedNights = widget.booking.expectedNights > 0
                ? widget.booking.expectedNights
                : (checkin != null
                      ? Time.nightsWithCutoff(
                          checkin,
                          checkout: plannedCheckout,
                        )
                      : 1);
            
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
                
                // حساب التكلفة بناءً على الليالي الفعلية (المغادرة المبكرة)
                final nightTotal = (() {
                  if (nights.isNotEmpty) {
                    // إذا كانت الليالي مسجلة يدوياً، نأخذها بعين الاعتبار
                    return nights.fold<double>(0, (sum, n) => sum + n.nightlyRate);
                  }
                  
                  if (checkin == null) return expectedNights * roomPrice;
                  
                  if (discount > 0 && discountType == 'per_night') {
                    final discountedNights = _countNightsWithDiscount(
                      checkin,
                      effectiveCheckout,
                      discountStartDate,
                    );
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
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'معلومات الحجز',
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      widget.booking.status,
                                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Text('النزيل: ${widget.booking.guestName}', style: const TextStyle(fontSize: 16)),
                              Text('رقم الغرفة: ${widget.booking.roomNumber}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.login, size: 16, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text('الدخول: ${widget.booking.checkinDate}'),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.logout, size: 16, color: Colors.red),
                                  const SizedBox(width: 4),
                                  Text('المغادرة (الآن): ${Time.nowIso().substring(0, 16).replaceFirst('T', ' ')}'),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('الليالي المحسوبة: $actualNights ليلة', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text(
                                    'سعر الليلة: ${CurrencyFormatter.formatAmount(roomPrice)}',
                                  ),
                                ],
                              ),
                              if (discount > 0)
                                Text(
                                  'التخفيض (${discountType == 'total' ? 'إجمالي' : 'لكل ليلة'}): ${CurrencyFormatter.formatAmount(discount)}',
                                  style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold),
                                ),
                              const Divider(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('إجمالي المستحق فعلياً:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  Text(
                                    CurrencyFormatter.formatAmount(totalDue),
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'الوضع المالي',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: StreamBuilder<List<Payment>>(
                          stream: paymentsRepo.paymentsByBooking(widget.booking.id),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            final payments = snapshot.data ?? const <Payment>[];
                            final totalPaid = payments.fold<double>(0, (sum, p) => sum + p.amount);
                            final balance = totalPaid - totalDue;

                            return Column(
                              children: [
                                Card(
                                  color: balance >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      children: [
                                        _buildSummaryRow('إجمالي المدفوع سابقاً', totalPaid, Colors.black87),
                                        const Divider(),
                                        if (balance > 0)
                                          _buildSummaryRow('المبلغ المتبقي للنزيل (استرجاع)', balance, Colors.green.shade700)
                                        else if (balance < 0)
                                          _buildSummaryRow('المبلغ المتبقي على النزيل (دفع)', balance.abs(), Colors.red.shade700)
                                        else
                                          const Text('الحساب متوازن ✅', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: payments.length,
                                    itemBuilder: (context, index) {
                                      final payment = payments[index];
                                      final isRefund = payment.amount < 0;
                                      return ListTile(
                                        leading: Icon(isRefund ? Icons.remove_circle : Icons.add_circle, color: isRefund ? Colors.red : Colors.green),
                                        title: Text(CurrencyFormatter.formatAmount(payment.amount.abs())),
                                        subtitle: Text('${payment.paymentMethod} - ${payment.paymentDate.substring(0, 10)}'),
                                        trailing: Text(isRefund ? 'استرجاع' : 'دفع'),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      // أزرار العمليات
                      StreamBuilder<List<Payment>>(
                        stream: paymentsRepo.paymentsByBooking(widget.booking.id),
                        builder: (context, snapshot) {
                          final totalPaid = snapshot.data?.fold<double>(0, (sum, p) => sum + p.amount) ?? 0.0;
                          final balance = totalPaid - totalDue;

                          return Row(
                            children: [
                              if (balance < 0)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isProcessing ? null : () => _addPayment(context, balance.abs(), false),
                                    icon: const Icon(Icons.add),
                                    label: const Text('تحصيل المتبقي'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                  ),
                                ),
                              if (balance > 0)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isProcessing ? null : () => _addPayment(context, balance, true),
                                    icon: const Icon(Icons.undo),
                                    label: const Text('استرجاع المتبقي'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isProcessing || balance != 0 ? null : () => _completeCheckout(context, actualNights),
                                  icon: const Icon(Icons.check_circle),
                                  label: const Text('إتمام المغادرة'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                ),
                              ),
                            ],
                          );
                        },
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
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
        Text(CurrencyFormatter.formatAmount(amount), style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
      ],
    );
  }

  Future<void> _addPayment(BuildContext context, double suggestedAmount, bool isRefund) async {
    final amountController = TextEditingController(text: suggestedAmount.toInt().toString());
    final notesController = TextEditingController(text: isRefund ? 'استرجاع مبلغ متبقي بسبب مغادرة مبكرة' : '');
    String selectedMethod = 'نقدي';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(isRefund ? 'استرجاع مبلغ للنزيل' : 'تحصيل مبلغ من النزيل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedMethod,
                items: const [
                  DropdownMenuItem(value: 'نقدي', child: Text('نقدي')),
                  DropdownMenuItem(value: 'تحويل', child: Text('تحويل بنكي')),
                ],
                onChanged: (v) => selectedMethod = v!,
                decoration: const InputDecoration(labelText: 'طريقة الدفع', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'ملاحظات', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
          ],
        ),
      ),
    );

    if (result == true) {
      final amount = double.tryParse(amountController.text) ?? 0.0;
      if (amount <= 0) return;

      setState(() => _isProcessing = true);
      try {
        final paymentsRepo = ref.read(paymentsRepoProvider);
        await paymentsRepo.create(
          bookingLocalId: widget.booking.id,
          roomNumber: widget.booking.roomNumber,
          amount: isRefund ? -amount : amount, // المبلغ بالسالب في حال الاسترجاع
          paymentDate: Time.nowIso(),
          notes: notesController.text,
          paymentMethod: selectedMethod,
          revenueType: isRefund ? 'refund' : 'room',
        );
        markDataChanged();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _completeCheckout(BuildContext context, int actualNights) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد المغادرة'),
        content: const Text('هل تريد إتمام عملية المغادرة وإخلاء الغرفة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إتمام')),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isProcessing = true);
      try {
        final bookingsRepo = ref.read(bookingsRepoProvider);
        final roomsRepo = ref.read(roomsRepoProvider);
        final nowIso = Time.nowIso();

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
        
        markDataChanged();
        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }
}
