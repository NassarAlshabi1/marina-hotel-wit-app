import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../models/payment_models.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart' as db;
import '../../utils/currency_formatter.dart';
import '../../utils/stream_helpers.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';
import '../payments/booking_checkout_screen.dart';

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen>
    with SyncOnExitMixin {
  @override
  String get screenId => 'finance';
  bool _isSavingPayment = false;

  // ✅ ValueNotifier — أسرع بديل لـ StreamBuilder في الهواتف الضعيفة
  ValueNotifier<List<db.Payment>>? _paymentsNotifier;
  ValueNotifier<List<db.Booking>>? _bookingsNotifier;

  @override
  void initState() {
    super.initState();
    _initNotifiers();
  }

  void _initNotifiers() {
    final paymentsRepo = ref.read(paymentsRepoProvider);
    _paymentsNotifier = StreamToValueNotifier(
      source: paymentsRepo.watchAll() as Stream<List<db.Payment>>,
      debounce: const Duration(milliseconds: 150),
      initialValue: <db.Payment>[],
    );
    _bookingsNotifier = StreamToValueNotifier(
      source: ref.read(bookingsRepoProvider).watchList(),
      debounce: const Duration(milliseconds: 150),
      initialValue: <db.Booking>[],
    );
  }

  @override
  void dispose() {
    _paymentsNotifier?.dispose();
    _bookingsNotifier?.dispose();
    super.dispose();
  }

  /// ✅ إصلاح: استخراج الوقت من سلسلة تاريخ بأي صيغة (ISO أو SQL)
  /// بدلاً من split(' ').last.substring(0, 5) الذي يفشل مع صيغة ISO
  String _extractTime(String dateStr) {
    try {
      final normalized = dateStr.contains('T')
          ? dateStr
          : dateStr.replaceFirst(' ', 'T');
      final dt = DateTime.parse(normalized);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      // Fallback: محاولة split على المسافة
      final parts = dateStr.split(' ');
      if (parts.length >= 2 && parts.last.length >= 5) {
        return parts.last.substring(0, 5);
      }
      return '--:--';
    }
  }

  @override
  Widget build(BuildContext context) {
    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'الصندوق والمالية',
        fab: FloatingActionButton.extended(
          onPressed: _isSavingPayment ? null : _showNewPaymentDialog,
          icon: const Icon(Icons.add_card),
          label: const Text('دفعة جديدة'),
          backgroundColor: Colors.green,
        ),
        body: Consumer(
          builder: (context, ref, _) {
            final todayIncome = ref.watch(todayPaymentsProvider);
            final todayExpenses = ref.watch(todayExpensesProvider);

            final income = todayIncome.valueOrNull ?? 0.0;
            final expenses = todayExpenses.valueOrNull ?? 0.0;
            final balance = income - expenses;

            return RefreshIndicator(
              color: Colors.indigo,
              onRefresh: () async => setState(() {}),
              child: _buildBody(income, expenses, balance),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(double income, double expenses, double balance) {
    // ✅ P0: استخدام ValueListenableBuilder بدلاً من StreamBuilder المتداخل
    // الأسرع للأجهزة الضعيفة — لا يعيد بناء كامل الشاشة
    return ValueListenableBuilder<List<db.Payment>>(
      valueListenable: _paymentsNotifier!,
      builder: (context, payments, _) {
        return ValueListenableBuilder<List<db.Booking>>(
          valueListenable: _bookingsNotifier!,
          builder: (context, bookings, _) {
            final activeBookings = bookings
                .where((b) => StatusUtils.isActiveBooking(b.status))
                .toList();

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: [
                // ─── بطاقة يوم الفندق ───
                _buildHotelDayCard(),

                const SizedBox(height: 8),

                // ─── بطاقة الصندوق: الايراد / المصروفات / المتبقي ───
                _buildCashDeskCard(income, expenses, balance),

                const SizedBox(height: 8),

                // ─── مدفوعات اليوم ───
                _buildTodayPayments(payments),

                const SizedBox(height: 8),

                // ─── الحجوزات النشطة ───
                _buildActiveBookings(activeBookings),

                const SizedBox(height: 80),
              ],
            );
          },
        );
      },
    );
  }

  // ─── بطاقة يوم الفندق ───
  Widget _buildHotelDayCard() {
    final now = DateTime.now();
    final hotelDay = HotelTimeEngine.getHotelDayKey();
    final cutoff = now.hour >= 14;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade700, Colors.indigo.shade500],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.calendar_today, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اليوم الفندقي',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  hotelDay,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cutoff ? Colors.orange.withValues(alpha: 0.9) : Colors.green.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(cutoff ? Icons.nightlight : Icons.wb_sunny,
                    size: 12, color: Colors.white,),
                const SizedBox(width: 3),
                Text(
                  cutoff ? 'بعد 14:00' : 'قبل 14:00',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── بطاقة الصندوق: الايراد / المصروفات / المتبقي ───
  Widget _buildCashDeskCard(double income, double expenses, double balance) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.account_balance_wallet, size: 16, color: Colors.indigo.shade700),
              ),
              const SizedBox(width: 6),
              const Text(
                'حالة الصندوق',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // الايراد
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade50, Colors.green.shade100],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.trending_up, color: Colors.green.shade700, size: 16),
                      const SizedBox(height: 2),
                      Text(
                        CurrencyFormatter.formatAmount(income),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'الايراد',
                        style: TextStyle(fontSize: 10, color: Colors.green.shade600, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // المصروفات
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade50, Colors.red.shade100],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.trending_down, color: Colors.red.shade700, size: 16),
                      const SizedBox(height: 2),
                      Text(
                        CurrencyFormatter.formatAmount(expenses),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'المصروفات',
                        style: TextStyle(fontSize: 10, color: Colors.red.shade600, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // المتبقي
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: balance >= 0
                          ? [Colors.indigo.shade50, Colors.indigo.shade100]
                          : [Colors.orange.shade50, Colors.orange.shade100],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: balance >= 0 ? Colors.indigo.shade200 : Colors.orange.shade300,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        balance >= 0 ? Icons.savings : Icons.warning_amber,
                        color: balance >= 0 ? Colors.indigo.shade700 : Colors.orange.shade700,
                        size: 16,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        CurrencyFormatter.formatAmount(balance.abs()),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: balance >= 0 ? Colors.indigo.shade800 : Colors.orange.shade800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        balance >= 0 ? 'المتبقي' : 'عجز',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: balance >= 0 ? Colors.indigo.shade600 : Colors.orange.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── مدفوعات اليوم (مجمّعة حسب الغرفة ومفصلة) ───
  Widget _buildTodayPayments(List<db.Payment> payments) {
    final hotelDay = HotelTimeEngine.getHotelDayKey();
    final todayPayments = payments
        .where((p) {
          if (p.isVoided) {
            return false;
          }
          if (p.hotelDayKey == hotelDay) {
            return true;
          }
          if (p.hotelDayKey == null &&
              p.paymentDate.startsWith(hotelDay)) {
            return true;
          }
          return false;
        })
        .toList();

    // تجميع المدفوعات حسب رقم الغرفة
    final grouped = <String, List<db.Payment>>{};
    for (final p in todayPayments) {
      final key = (p.roomNumber != null && p.roomNumber!.trim().isNotEmpty)
          ? p.roomNumber!.trim()
          : '__other__';
      grouped.putIfAbsent(key, () => []).add(p);
    }

    // ترتيب: الغرف أولاً (مرتبة تصاعدياً)، ثم المدفوعات العامة
    final sortedKeys = grouped.keys.toList()..sort((a, b) {
      if (a == '__other__') {
        return 1;
      }
      if (b == '__other__') {
        return -1;
      }
      return a.compareTo(b);
    });

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, size: 16, color: Colors.indigo),
                const SizedBox(width: 5),
                const Text(
                  'تفاصيل مدفوعات اليوم الفندقي',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${todayPayments.length} عملية',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          if (todayPayments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'لا توجد مدفوعات اليوم',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            )
          else
            ...sortedKeys.map((key) {
              final groupPayments = grouped[key]!;
              final total = groupPayments.fold<double>(
                0, (s, p) => s + p.amount,
              );
              final isOther = key == '__other__';
              return _buildRoomPaymentGroup(
                roomNumber: isOther ? null : key,
                totalAmount: total,
                payments: groupPayments,
              );
            }),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildRoomPaymentGroup({
    required String? roomNumber,
    required double totalAmount,
    required List<db.Payment> payments,
  }) {
    final isRoom = roomNumber != null;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isRoom ? Colors.indigo.shade50 : Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: (isRoom ? Colors.indigo : Colors.amber).shade100),
          ),
          child: Row(
            children: [
              Icon(
                isRoom ? Icons.hotel : Icons.payments_outlined,
                size: 14,
                color: isRoom ? Colors.indigo.shade700 : Colors.amber.shade700,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  isRoom ? 'غرفة $roomNumber' : 'مدفوعات عامة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: isRoom ? Colors.indigo.shade800 : Colors.amber.shade800,
                  ),
                ),
              ),
              Text(
                CurrencyFormatter.formatAmount(totalAmount),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isRoom ? Colors.indigo.shade900 : Colors.amber.shade900,
                ),
              ),
            ],
          ),
        ),
        ...payments.map(_buildSinglePaymentDetail),
        const Divider(indent: 40, endIndent: 40, height: 10),
      ],
    );
  }

  Widget _buildSinglePaymentDetail(db.Payment p) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 35, top: 3, bottom: 3),
      child: Row(
        children: [
          if (p.notes?.isNotEmpty ?? false)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.notes!,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // ✅ إصلاح: تحليل التاريخ بشكل صحيح بدلاً من split(' ')
                  // التاريخ قد يكون بصيغة ISO (2025-06-15T14:30:00) بدون مسافة
                  Text(
                    _extractTime(p.paymentDate),
                    style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Text(
                // ✅ إصلاح: تحليل التاريخ بشكل صحيح بدلاً من split(' ')
                _extractTime(p.paymentDate),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ),
          Text(
            CurrencyFormatter.formatAmount(p.amount),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // ─── الحجوزات النشطة ───
  Widget _buildActiveBookings(List<db.Booking> bookings) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.hotel, size: 16, color: Colors.indigo),
                const SizedBox(width: 5),
                const Text(
                  'الحجوزات النشطة',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${bookings.length} حجز',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          if (bookings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'لا توجد حجوزات نشطة',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            )
          else
            ...bookings.map(_buildBookingTile),
        ],
      ),
    );
  }

  Widget _buildBookingTile(db.Booking booking) {
    final isPaid = booking.isFullyPaid;
    final hasBalance = booking.remainingBalanceCached > 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: isPaid
            ? Colors.green.shade50
            : hasBalance
                ? Colors.orange.shade50
                : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: isPaid
                ? Colors.green.shade100
                : hasBalance
                    ? Colors.orange.shade100
                    : Colors.grey.shade200,
            child: Text(
              booking.roomNumber,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10,
                color: isPaid
                    ? Colors.green.shade800
                    : hasBalance
                        ? Colors.orange.shade800
                        : Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.guestName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Text(
                      booking.guestPhone,
                      style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      booking.guestNationality,
                      style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                if (hasBalance)
                  Text(
                    'متبقي: ${CurrencyFormatter.formatAmount(booking.remainingBalanceCached)}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 26,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => BookingCheckoutScreen(booking: booking),
                  ),
                );
              },
              icon: const Icon(Icons.payment, size: 12),
              label: const Text('دفع', style: TextStyle(fontSize: 10)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isPaid ? Colors.grey.shade400 : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── إضافة دفعة جديدة تراكمية ───

  void _showNewPaymentDialog() {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final referenceController = TextEditingController();
    PaymentMethod selectedMethod = PaymentMethod.cash;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.add_card, color: Colors.green),
                SizedBox(width: 8),
                Text('دفعة جديدة تراكمية'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'طريقة الدفع',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: PaymentMethod.values.map((method) {
                        final isSelected = selectedMethod == method;
                        return ChoiceChip(
                          avatar: Icon(method.icon,
                              size: 16,
                              color: isSelected ? Colors.white : method.color,),
                          label: Text(
                            method.displayName,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white : method.color,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: method.color,
                          onSelected: (_) {
                            setDialogState(() {
                              selectedMethod = method;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      decoration: const InputDecoration(
                        labelText: 'المبلغ *',
                        prefixText: 'ر.ي ',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (selectedMethod == PaymentMethod.transfer ||
                        selectedMethod == PaymentMethod.check) ...[
                      TextField(
                        controller: referenceController,
                        decoration: const InputDecoration(
                          labelText: 'رقم المرجع / الشيك',
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
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: _isSavingPayment
                    ? null
                    : () => _saveStandalonePayment(
                          ctx,
                          amountController.text,
                          notesController.text,
                          referenceController.text,
                          selectedMethod,
                        ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: _isSavingPayment
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white,),
                      )
                    : const Text('تسجيل الدفعة'),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      amountController.dispose();
      notesController.dispose();
      referenceController.dispose();
    });
  }

  Future<void> _saveStandalonePayment(
    BuildContext dialogContext,
    String amountText,
    String notes,
    String reference,
    PaymentMethod method,
  ) async {
    final parsedAmount = CurrencyFormatter.parseAmount(amountText);
    if (parsedAmount == null || parsedAmount <= 0) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال مبلغ صحيح'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSavingPayment = true);

    try {
      final paymentsRepo = ref.read(paymentsRepoProvider);

      String dbMethod;
      switch (method) {
        case PaymentMethod.cash:
          dbMethod = 'نقدي';
        case PaymentMethod.card:
          dbMethod = 'بطاقة';
        case PaymentMethod.transfer:
          dbMethod = 'تحويل';
        case PaymentMethod.check:
          dbMethod = 'شيك';
        case PaymentMethod.installment:
          dbMethod = 'تقسيط';
      }

      await paymentsRepo.create(
        amount: parsedAmount,
        paymentDate: Time.nowIso(),
        notes: notes.trim().isEmpty ? null : notes.trim(),
        paymentMethod: dbMethod,
        revenueType: 'other',
      );

      // إرسال إشعار واتساب
      unawaited(_sendPaymentWhatsAppNotification(
        amount: parsedAmount,
        method: dbMethod,
        notes: notes.trim(),
      ),);

      if (mounted) {
        // ignore: use_build_context_synchronously
        Navigator.pop(dialogContext);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تسجيل الدفعة ${CurrencyFormatter.formatAmount(parsedAmount)} بنجاح',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        Navigator.pop(dialogContext);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تسجيل الدفعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingPayment = false);
      }
    }
  }

  Future<void> _sendPaymentWhatsAppNotification({
    required double amount,
    required String method,
    required String notes,
  }) async {
    try {
      final whatsappService = ref.read(whatsappServiceProvider);

      final message = StringBuffer()
        ..writeln('إشعار دفعة جديدة')
        ..writeln('━━━━━━━━━━━━━━━')
        ..writeln('المبلغ: ${CurrencyFormatter.formatAmount(amount)}')
        ..writeln('طريقة الدفع: $method')
        ..writeln('التاريخ: ${Time.nowIso()}')
        ..writeln('اليوم الفندقي: ${HotelTimeEngine.getHotelDayKey()}')
        ..writeln(notes.isNotEmpty ? 'ملاحظات: $notes' : '');

      final result = await whatsappService.sendMessage(
        phoneE164: '9677734587456',
        message: message.toString(),
      );
      if (result.quotaMessage != null) {
        debugPrint('تجاوز حصة الواتساب: ${result.quotaMessage}');
      }
    } catch (_) {
      debugPrint('تعذّر إرسال إشعار واتساب للدفعة التراكمية');
    }
  }
}
