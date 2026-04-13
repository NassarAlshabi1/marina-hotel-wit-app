import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart' as db;
import '../../utils/currency_formatter.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';
import '../../models/payment_models.dart';
import 'payment_history_screen.dart';
import 'booking_checkout_screen.dart';
import '../../mixins/sync_on_exit_mixin.dart';

class PaymentsMainScreen extends ConsumerStatefulWidget {
  const PaymentsMainScreen({super.key});

  @override
  ConsumerState<PaymentsMainScreen> createState() => _PaymentsMainScreenState();
}

class _PaymentsMainScreenState extends ConsumerState<PaymentsMainScreen>
    with SingleTickerProviderStateMixin, SyncOnExitMixin {
  @override
  String get screenId => 'payments_main';
  late TabController _tabController;
  bool _isSavingPayment = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'إدارة المدفوعات',
        fab: FloatingActionButton.extended(
          onPressed: _isSavingPayment ? null : _showNewPaymentDialog,
          icon: const Icon(Icons.add_card),
          label: const Text('دفعة جديدة'),
          backgroundColor: Colors.green,
        ),
        body: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              tabs: const [
                Tab(text: 'نظرة عامة', icon: Icon(Icons.dashboard, size: 18)),
                Tab(text: 'المعاملات', icon: Icon(Icons.list, size: 18)),
                Tab(text: 'الحجوزات النشطة', icon: Icon(Icons.hotel, size: 18)),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildTransactionsTab(),
                  _buildActiveBookingsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final paymentsRepo = ref.watch(paymentsRepoProvider);

    return StreamBuilder<List<db.Payment>>(
      stream: paymentsRepo.watchAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.payment_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'لا توجد مدفوعات مسجلة',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final payments = snapshot.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // الإحصائيات السريعة
              _buildQuickStats(payments),

              const SizedBox(height: 16),

              // المدفوعات الأخيرة
              _buildRecentPayments(payments),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickStats(List<db.Payment> payments) {
    final today = DateTime.now();
    final hotelDay = Time.hotelDayKey();
    final startOfMonth = DateTime(today.year, today.month, 1);

    // حساب المبالغ
    final totalAmount = payments.fold<double>(0, (sum, p) => sum + p.amount);

    // مدفوعات اليوم الفندقي الحالي (من 14:00 أمس إلى 14:00 اليوم)
    final todayPayments = payments.where((p) {
      final paymentDay = Time.hotelDayKeyFromIso(p.paymentDate);
      return paymentDay == hotelDay;
    }).toList();
    final todayAmount = todayPayments.fold<double>(
      0,
      (sum, p) => sum + p.amount,
    );

    // مدفوعات هذا الشهر
    final monthlyPayments = payments.where((p) {
      try {
        final date = DateTime.parse(p.paymentDate);
        return date.isAfter(startOfMonth);
      } catch (e) {
        return false;
      }
    }).toList();
    final monthlyAmount = monthlyPayments.fold<double>(
      0,
      (sum, p) => sum + p.amount,
    );

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'اليوم الفندقي',
            CurrencyFormatter.formatAmount(todayAmount),
            Icons.today,
            Colors.amber.shade700,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'الإجمالي',
            CurrencyFormatter.formatAmount(totalAmount),
            Icons.account_balance_wallet,
            Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'هذا الشهر',
            CurrencyFormatter.formatAmount(monthlyAmount),
            Icons.calendar_month,
            Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 1),
            Text(
              title,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildPaymentMethodChart(List<db.Payment> payments) {
    final methodCounts = <String, double>{};

    for (final payment in payments) {
      methodCounts[payment.paymentMethod] =
          (methodCounts[payment.paymentMethod] ?? 0) + payment.amount;
    }

    if (methodCounts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'توزيع المدفوعات حسب الطريقة',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: methodCounts.entries.map((entry) {
                    final color = _getPaymentMethodColor(entry.key);
                    return PieChartSectionData(
                      value: entry.value,
                      title:
                          '${entry.key}\n${(entry.value / methodCounts.values.reduce((a, b) => a + b) * 100).toStringAsFixed(1)}%',
                      color: color,
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentPayments(List<db.Payment> payments) {
    // عرض مدفوعات اليوم الفندقي الحالي
    final hotelDay = Time.hotelDayKey();
    final todayPayments = payments.where((p) {
      final paymentDay = Time.hotelDayKeyFromIso(p.paymentDate);
      return paymentDay == hotelDay;
    }).toList();

    // ترتيب تنازلي حسب التاريخ
    todayPayments.sort((a, b) {
      try {
        return DateTime.parse(b.paymentDate).compareTo(DateTime.parse(a.paymentDate));
      } catch (_) {
        return 0;
      }
    });

    final recentPayments = todayPayments.take(10).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'مدفوعات اليوم الفندقي',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () => _tabController.animateTo(1),
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...recentPayments.map(
              (payment) => ListTile(
                leading: Icon(
                  _getPaymentMethodIcon(payment.paymentMethod),
                  color: _getPaymentMethodColor(payment.paymentMethod),
                ),
                title: Text(CurrencyFormatter.formatAmount(payment.amount)),
                subtitle: Text(
                  '${payment.paymentMethod} • ${payment.paymentDate}',
                ),
                trailing: payment.roomNumber != null
                    ? Chip(
                        label: Text(payment.roomNumber!),
                        backgroundColor: Colors.blue.shade50,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsTab() {
    return const PaymentHistoryScreen();
  }

  Widget _buildActiveBookingsTab() {
    final bookingsRepo = ref.watch(bookingsRepoProvider);

    return StreamBuilder<List<db.Booking>>(
      stream: bookingsRepo.watchList(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hotel_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'لا توجد حجوزات نشطة',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final activeBookings = snapshot.data!
            .where((booking) => StatusUtils.isActiveBooking(booking.status))
            .toList();

        if (activeBookings.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text(
                  'جميع الحجوزات مكتملة!',
                  style: TextStyle(fontSize: 18, color: Colors.green),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: activeBookings.length,
          itemBuilder: (context, index) {
            final booking = activeBookings[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.orange.shade100,
                  child: Text(
                    booking.roomNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                      fontSize: 11,
                    ),
                  ),
                ),
                title: Text(
                  booking.guestName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الهاتف: ${booking.guestPhone}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    Text(
                      'دخول: ${booking.checkinDate}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    Text(
                      'الجنسية: ${booking.guestNationality}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                trailing: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            BookingCheckoutScreen(booking: booking),
                      ),
                    );
                  },
                  icon: const Icon(Icons.payment, size: 14),
                  label: const Text('دفع', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }

  Color _getPaymentMethodColor(String method) {
    switch (method) {
      case 'نقدي':
        return Colors.green;
      case 'بطاقة':
        return Colors.blue;
      case 'تحويل':
        return Colors.orange;
      case 'شيك':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getPaymentMethodIcon(String method) {
    switch (method) {
      case 'نقدي':
        return Icons.money;
      case 'بطاقة':
        return Icons.credit_card;
      case 'تحويل':
        return Icons.account_balance;
      case 'شيك':
        return Icons.receipt_long;
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
                    // اختيار طريقة الدفع
                    const Text(
                      'طريقة الدفع',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
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
                              color: isSelected
                                  ? Colors.white
                                  : method.color),
                          label: Text(
                            method.displayName,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white : method.color,
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
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

                    // حقل المبلغ
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

                    // رقم المرجع (للتحويل والشيك)
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

                    // ملاحظات
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
