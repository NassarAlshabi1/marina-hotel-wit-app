import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart' as db;
import '../../utils/currency_formatter.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';
import '../../models/payment_models.dart';
import '../payments/payment_history_screen.dart';
import '../payments/booking_checkout_screen.dart';
import '../../mixins/sync_on_exit_mixin.dart';

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

            final paymentsRepo = ref.read(paymentsRepoProvider);
            return RefreshIndicator(
              color: Colors.indigo,
              onRefresh: () async => setState(() {}),
              child: _buildBody(paymentsRepo, income, expenses, balance),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(dynamic paymentsRepo, double income, double expenses, double balance) {
    return StreamBuilder<List<db.Payment>>(
      stream: paymentsRepo.watchAll(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final payments = snapshot.data!;

        return StreamBuilder<List<db.Booking>>(
          stream: ref.read(bookingsRepoProvider).watchList(),
          builder: (context, bookingsSnapshot) {
            final activeBookings = bookingsSnapshot.hasData
                ? bookingsSnapshot.data!
                    .where((b) => StatusUtils.isActiveBooking(b.status))
                    .toList()
                : <db.Booking>[];

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                // ─── بطاقة يوم الفندق ───
                _buildHotelDayCard(),

                const SizedBox(height: 12),

                // ─── بطاقة الصندوق: الايراد / المصروفات / المتبقي ───
                _buildCashDeskCard(income, expenses, balance),

                const SizedBox(height: 12),

                // ─── مدفوعات اليوم ───
                _buildTodayPayments(payments),

                const SizedBox(height: 12),

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
    final hotelDay = Time.hotelDayKey();
    final cutoff = now.hour >= 14;
    final dateFmt = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade700, Colors.indigo.shade500],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.calendar_today, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اليوم الفندقي',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hotelDay,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: cutoff ? Colors.orange.withOpacity(0.9) : Colors.green.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(cutoff ? Icons.nightlight : Icons.wb_sunny,
                    size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  cutoff ? 'بعد 14:00' : 'قبل 14:00',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.account_balance_wallet, size: 20, color: Colors.indigo.shade700),
              ),
              const SizedBox(width: 8),
              const Text(
                'حالة الصندوق',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // الايراد
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade50, Colors.green.shade100],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.trending_up, color: Colors.green.shade700, size: 20),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.formatAmount(income),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'الايراد',
                        style: TextStyle(fontSize: 11, color: Colors.green.shade600, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // المصروفات
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade50, Colors.red.shade100],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.trending_down, color: Colors.red.shade700, size: 20),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.formatAmount(expenses),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'المصروفات',
                        style: TextStyle(fontSize: 11, color: Colors.red.shade600, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // المتبقي
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: balance >= 0
                          ? [Colors.indigo.shade50, Colors.indigo.shade100]
                          : [Colors.orange.shade50, Colors.orange.shade100],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: balance >= 0 ? Colors.indigo.shade200 : Colors.orange.shade300,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        balance >= 0 ? Icons.savings : Icons.warning_amber,
                        color: balance >= 0 ? Colors.indigo.shade700 : Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.formatAmount(balance.abs()),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: balance >= 0 ? Colors.indigo.shade800 : Colors.orange.shade800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        balance >= 0 ? 'المتبقي' : 'عجز',
                        style: TextStyle(
                          fontSize: 11,
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

  // ─── مدفوعات اليوم (مجمّعة حسب الغرفة) ───
  Widget _buildTodayPayments(List<db.Payment> payments) {
    final hotelDay = Time.hotelDayKey();
    final todayPayments = payments
        .where((p) {
          if (p.isVoided) return false;
          if (p.hotelDayKey == hotelDay) return true;
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
      if (a == '__other__') return 1;
      if (b == '__other__') return -1;
      return a.compareTo(b);
    });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, size: 18, color: Colors.indigo),
                const SizedBox(width: 6),
                const Text(
                  'مدفوعات اليوم الفندقي',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
              padding: EdgeInsets.symmetric(vertical: 24),
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
              return _buildRoomPaymentTile(
                roomNumber: isOther ? null : key,
                totalAmount: total,
                paymentsCount: groupPayments.length,
              );
            }),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PaymentHistoryScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.arrow_forward_ios, size: 14),
                label: const Text('عرض التفاصيل'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomPaymentTile({
    required String? roomNumber,
    required double totalAmount,
    required int paymentsCount,
  }) {
    final isRoom = roomNumber != null;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isRoom ? Colors.grey.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // أيقونة الغرفة أو المدفوعات العامة
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: isRoom
                  ? Colors.indigo.shade50
                  : Colors.amber.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isRoom ? Icons.hotel : Icons.payments_outlined,
              size: 16,
              color: isRoom ? Colors.indigo.shade700 : Colors.amber.shade700,
            ),
          ),
          const SizedBox(width: 10),
          // رقم الغرفة + عدد العمليات
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRoom ? 'غرفة $roomNumber' : 'مدفوعات عامة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isRoom ? Colors.indigo.shade800 : Colors.amber.shade800,
                  ),
                ),
                Text(
                  '$paymentsCount ${paymentsCount == 1 ? 'عملية' : 'عمليات'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          // المجموع
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (isRoom ? Colors.green : Colors.orange).shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (isRoom ? Colors.green : Colors.orange).shade200,
              ),
            ),
            child: Text(
              CurrencyFormatter.formatAmount(totalAmount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: (isRoom ? Colors.green : Colors.orange).shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentTile(db.Payment payment) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _getMethodColor(payment.paymentMethod).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getMethodIcon(payment.paymentMethod),
              size: 16,
              color: _getMethodColor(payment.paymentMethod),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  CurrencyFormatter.formatAmount(payment.amount),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  payment.paymentMethod,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (payment.roomNumber != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Text(
                'غرفة ${payment.roomNumber}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── الحجوزات النشطة ───
  Widget _buildActiveBookings(List<db.Booking> bookings) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.hotel, size: 18, color: Colors.indigo),
                const SizedBox(width: 6),
                const Text(
                  'الحجوزات النشطة',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'لا توجد حجوزات نشطة',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            )
          else
            ...bookings.map((b) => _buildBookingTile(b)),
        ],
      ),
    );
  }

  Widget _buildBookingTile(db.Booking booking) {
    final isPaid = booking.isFullyPaid;
    final hasBalance = (booking.remainingBalanceCached ?? 0) > 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isPaid
            ? Colors.green.shade50
            : hasBalance
                ? Colors.orange.shade50
                : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isPaid
                ? Colors.green.shade100
                : hasBalance
                    ? Colors.orange.shade100
                    : Colors.grey.shade200,
            child: Text(
              booking.roomNumber,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: isPaid
                    ? Colors.green.shade800
                    : hasBalance
                        ? Colors.orange.shade800
                        : Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.guestName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${booking.guestPhone}',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${booking.guestNationality}',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                if (hasBalance)
                  Text(
                    'متبقي: ${CurrencyFormatter.formatAmount(booking.remainingBalanceCached ?? 0)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 30,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookingCheckoutScreen(booking: booking),
                  ),
                );
              },
              icon: const Icon(Icons.payment, size: 13),
              label: const Text('دفع', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isPaid ? Colors.grey.shade400 : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── أدوات مساعدة ───

  Color _getMethodColor(String method) {
    switch (method) {
      case 'نقدي':
        return Colors.green;
      case 'بطاقة':
      case 'بطاقة ائتمان':
        return Colors.blue;
      case 'تحويل':
      case 'تحويل بنكي':
        return Colors.orange;
      case 'شيك':
        return Colors.purple;
      case 'تقسيط':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  IconData _getMethodIcon(String method) {
    switch (method) {
      case 'نقدي':
        return Icons.money;
      case 'بطاقة':
      case 'بطاقة ائتمان':
        return Icons.credit_card;
      case 'تحويل':
      case 'تحويل بنكي':
        return Icons.account_balance;
      case 'شيك':
        return Icons.receipt_long;
      case 'تقسيط':
        return Icons.calendar_view_month;
      default:
        return Icons.payment;
    }
  }

  // ─── إضافة دفعة جديدة تراكمية ───

  void _showNewPaymentDialog() {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final referenceController = TextEditingController();
    PaymentMethod selectedMethod = PaymentMethod.cash;

    showDialog(
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
                              color: isSelected ? Colors.white : method.color),
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
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('تسجيل الدفعة'),
              ),
            ],
          ),
        ),
      ),
    );
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
      if (!mounted) return;
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
          break;
        case PaymentMethod.card:
          dbMethod = 'بطاقة';
          break;
        case PaymentMethod.transfer:
          dbMethod = 'تحويل';
          break;
        case PaymentMethod.check:
          dbMethod = 'شيك';
          break;
        case PaymentMethod.installment:
          dbMethod = 'تقسيط';
          break;
      }

      await paymentsRepo.create(
        bookingLocalId: null,
        amount: parsedAmount.toDouble(),
        paymentDate: Time.nowIso(),
        notes: notes.trim().isEmpty ? null : notes.trim(),
        paymentMethod: dbMethod,
        revenueType: 'other',
      );

      if (mounted) {
        Navigator.pop(dialogContext);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تسجيل الدفعة ${CurrencyFormatter.formatAmount(parsedAmount.toDouble())} بنجاح',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
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
}
