import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/local_db.dart';
import 'payment_history_screen.dart';
import 'booking_checkout_screen.dart';

class PaymentsMainScreen extends ConsumerStatefulWidget {
  const PaymentsMainScreen({super.key});

  @override
  ConsumerState<PaymentsMainScreen> createState() => _PaymentsMainScreenState();
}

class _PaymentsMainScreenState extends ConsumerState<PaymentsMainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
    return AppScaffold(
      title: 'إدارة المدفوعات',
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            tabs: const [
              Tab(text: 'نظرة عامة', icon: Icon(Icons.dashboard, size: 20)),
              Tab(text: 'المعاملات', icon: Icon(Icons.list, size: 20)),
              Tab(text: 'الحجوزات النشطة', icon: Icon(Icons.hotel, size: 20)),
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
    );
  }

  Widget _buildOverviewTab() {
    final paymentsRepo = ref.watch(paymentsRepoProvider);

    return StreamBuilder<List<Payment>>(
      stream: paymentsRepo.paymentsByBooking(-1),
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
              
              // الرسم البياني
              _buildPaymentMethodChart(payments),
              
              const SizedBox(height: 16),
              
              // المدفوعات الأخيرة
              _buildRecentPayments(payments),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickStats(List<Payment> payments) {
    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final startOfMonth = DateTime(today.year, today.month, 1);

    // حساب المبالغ
    final totalAmount = payments.fold<double>(0, (sum, p) => sum + p.amount);
    
    final weeklyPayments = payments.where((p) {
      try {
        final date = DateTime.parse(p.paymentDate);
        return date.isAfter(startOfWeek);
      } catch (e) {
        return false;
      }
    }).toList();
    final weeklyAmount = weeklyPayments.fold<double>(0, (sum, p) => sum + p.amount);

    final monthlyPayments = payments.where((p) {
      try {
        final date = DateTime.parse(p.paymentDate);
        return date.isAfter(startOfMonth);
      } catch (e) {
        return false;
      }
    }).toList();
    final monthlyAmount = monthlyPayments.fold<double>(0, (sum, p) => sum + p.amount);

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'الإجمالي',
            '${totalAmount.toStringAsFixed(0)} ر.س',
            Icons.account_balance_wallet,
            Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'هذا الشهر',
            '${monthlyAmount.toStringAsFixed(0)} ر.س',
            Icons.calendar_month,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'هذا الأسبوع',
            '${weeklyAmount.toStringAsFixed(0)} ر.س',
            Icons.date_range,
            Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodChart(List<Payment> payments) {
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
                      title: '${entry.key}\n${(entry.value / methodCounts.values.reduce((a, b) => a + b) * 100).toStringAsFixed(1)}%',
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

  Widget _buildRecentPayments(List<Payment> payments) {
    final recentPayments = payments.take(5).toList();

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
                  'المدفوعات الأخيرة',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () => _tabController.animateTo(1),
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...recentPayments.map((payment) => ListTile(
              leading: Icon(
                _getPaymentMethodIcon(payment.paymentMethod),
                color: _getPaymentMethodColor(payment.paymentMethod),
              ),
              title: Text('${payment.amount.toStringAsFixed(2)} ر.س'),
              subtitle: Text('${payment.paymentMethod} • ${payment.paymentDate}'),
              trailing: payment.roomNumber != null 
                  ? Chip(
                      label: Text(payment.roomNumber!),
                      backgroundColor: Colors.blue.shade50,
                    )
                  : null,
            )),
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

    return StreamBuilder<List<Booking>>(
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
            .where((booking) => booking.status == 'محجوزة')
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
          padding: const EdgeInsets.all(16),
          itemCount: activeBookings.length,
          itemBuilder: (context, index) {
            final booking = activeBookings[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.shade100,
                  child: Text(
                    booking.roomNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
                title: Text(
                  booking.guestName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الهاتف: ${booking.guestPhone}'),
                    Text('دخول: ${booking.checkinDate}'),
                    if (booking.guestNationality != null)
                      Text('الجنسية: ${booking.guestNationality}'),
                  ],
                ),
                trailing: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BookingCheckoutScreen(booking: booking),
                      ),
                    );
                  },
                  icon: const Icon(Icons.payment, size: 16),
                  label: const Text('دفع'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
}