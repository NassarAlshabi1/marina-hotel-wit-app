import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/sync_service.dart';
import '../../models/payment_models.dart';
import 'booking_payment_screen.dart';
import 'payment_history_screen.dart';

class PaymentsMainScreen extends ConsumerStatefulWidget {
  const PaymentsMainScreen({super.key});

  @override
  ConsumerState<PaymentsMainScreen> createState() => _PaymentsMainScreenState();
}

class _PaymentsMainScreenState extends ConsumerState<PaymentsMainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // بيانات تجريبية
  final List<Payment> _todayPayments = [];
  final List<Payment> _pendingPayments = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSampleData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadSampleData() {
    // بيانات تجريبية
    _todayPayments.addAll([
      Payment(
        id: '1',
        bookingId: 'booking_1',
        amount: 300.0,
        method: PaymentMethod.cash,
        status: PaymentStatus.completed,
        paymentDate: DateTime.now().subtract(const Duration(hours: 2)),
        notes: 'دفعة مقدمة',
        receivedBy: 'admin',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      Payment(
        id: '2',
        bookingId: 'booking_2',
        amount: 450.0,
        method: PaymentMethod.card,
        status: PaymentStatus.completed,
        paymentDate: DateTime.now().subtract(const Duration(hours: 1)),
        cardLastFourDigits: '1234',
        receivedBy: 'admin',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ]);

    _pendingPayments.addAll([
      Payment(
        id: '3',
        bookingId: 'booking_3',
        amount: 200.0,
        method: PaymentMethod.transfer,
        status: PaymentStatus.pending,
        paymentDate: DateTime.now().subtract(const Duration(minutes: 30)),
        referenceNumber: 'TRF123456',
        receivedBy: 'cashier',
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
        updatedAt: DateTime.now().subtract(const Duration(minutes: 30)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsListProvider);
    
    return AppScaffold(
      title: 'إدارة المدفوعات',
      actions: [
        IconButton(
          onPressed: () => ref.read(syncServiceProvider).runSync(),
          icon: const Icon(Icons.sync),
          tooltip: 'مزامنة',
        ),
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PaymentHistoryScreen()),
          ),
          icon: const Icon(Icons.history),
          tooltip: 'جميع المدفوعات',
        ),
      ],
      body: Column(
        children: [
          // إحصائيات اليوم
          _buildTodayStats(),
          
          const SizedBox(height: 16),
          
          // أشرطة التبويب
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
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
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'مدفوعات اليوم'),
                Tab(text: 'في الانتظار'),
                Tab(text: 'حجوزات تحتاج دفع'),
              ],
            ),
          ),
          
          // محتوى التبويبات
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTodayPaymentsTab(),
                _buildPendingPaymentsTab(),
                _buildUnpaidBookingsTab(bookingsAsync),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayStats() {
    final todayTotal = _todayPayments.fold<double>(0, (sum, p) => sum + p.amount);
    final pendingTotal = _pendingPayments.fold<double>(0, (sum, p) => sum + p.amount);
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade50, Colors.green.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.today, color: Colors.green, size: 28),
              SizedBox(width: 12),
              Text(
                'إحصائيات اليوم',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatChip('مدفوعات اليوم', _todayPayments.length, Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('في الانتظار', _pendingPayments.length, Colors.orange)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('الإجمالي', '${todayTotal.toStringAsFixed(0)} ر.س', Colors.blue)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, dynamic value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTodayPaymentsTab() {
    if (_todayPayments.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payment, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا توجد مدفوعات اليوم', style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _todayPayments.length,
      itemBuilder: (context, index) {
        final payment = _todayPayments[index];
        return _buildPaymentSummaryCard(payment);
      },
    );
  }

  Widget _buildPendingPaymentsTab() {
    if (_pendingPayments.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا توجد مدفوعات في الانتظار', style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingPayments.length,
      itemBuilder: (context, index) {
        final payment = _pendingPayments[index];
        return _buildPendingPaymentCard(payment);
      },
    );
  }

  Widget _buildUnpaidBookingsTab(AsyncValue bookingsAsync) {
    return bookingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('خطأ: $e')),
      data: (bookings) {
        // فلترة الحجوزات التي تحتاج دفع (محجوزة أو نشطة)
        final unpaidBookings = bookings.where((b) => 
          b.status == 'محجوزة' || b.status == 'نشط').toList();

        if (unpaidBookings.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text('جميع الحجوزات مدفوعة', style: TextStyle(fontSize: 18)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: unpaidBookings.length,
          itemBuilder: (context, index) {
            final booking = unpaidBookings[index];
            return _buildUnpaidBookingCard(booking);
          },
        );
      },
    );
  }

  Widget _buildPaymentSummaryCard(Payment payment) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: payment.method.color.withOpacity(0.2),
          child: Icon(payment.method.icon, color: payment.method.color),
        ),
        title: Text('${payment.amount.toStringAsFixed(2)} ر.س'),
        subtitle: Text('${payment.method.displayName} • ${_formatTime(payment.paymentDate)}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: payment.status.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: payment.status.color),
          ),
          child: Text(
            payment.status.displayName,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: payment.status.color,
            ),
          ),
        ),
        onTap: () => _showPaymentDetails(payment),
      ),
    );
  }

  Widget _buildPendingPaymentCard(Payment payment) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.orange.withOpacity(0.2),
                  child: Icon(payment.method.icon, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${payment.amount.toStringAsFixed(2)} ر.س',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(payment.method.displayName),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Text(
                    'في الانتظار',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            if (payment.referenceNumber != null)
              Text('رقم المرجع: ${payment.referenceNumber}'),
            
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmPayment(payment),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('تأكيد'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rejectPayment(payment),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('رفض'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnpaidBookingCard(booking) {
    // حساب المبلغ المطلوب (تجريبي)
    final nights = booking.calculatedNights;
    final estimatedAmount = nights * 150.0; // سعر افتراضي
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.red.withOpacity(0.2),
          child: Text(
            booking.roomNumber,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
        ),
        title: Text(booking.guestName),
        subtitle: Text(
          'غرفة ${booking.roomNumber} • ${nights} ليلة\n'
          'المبلغ المتوقع: ${estimatedAmount.toStringAsFixed(2)} ر.س',
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        isThreeLine: true,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BookingPaymentScreen(booking: booking),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showPaymentDetails(Payment payment) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تفاصيل الدفعة #${payment.id}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('المبلغ', '${payment.amount.toStringAsFixed(2)} ر.س'),
              _buildDetailRow('طريقة الدفع', payment.method.displayName),
              _buildDetailRow('الحالة', payment.status.displayName),
              _buildDetailRow('التاريخ والوقت', _formatDateTime(payment.paymentDate)),
              _buildDetailRow('المحاسب', payment.receivedBy),
              if (payment.referenceNumber != null)
                _buildDetailRow('رقم المرجع', payment.referenceNumber!),
              if (payment.cardLastFourDigits != null)
                _buildDetailRow('آخر أرقام البطاقة', '****${payment.cardLastFourDigits}'),
              if (payment.bankName != null)
                _buildDetailRow('البنك', payment.bankName!),
              if (payment.notes != null && payment.notes!.isNotEmpty)
                _buildDetailRow('ملاحظات', payment.notes!),
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
                _generateReceiptForPayment(payment);
              },
              child: const Text('طباعة إيصال'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _confirmPayment(Payment payment) {
    setState(() {
      final index = _pendingPayments.indexWhere((p) => p.id == payment.id);
      if (index != -1) {
        final confirmedPayment = payment.copyWith(
          status: PaymentStatus.completed,
          updatedAt: DateTime.now(),
        );
        _pendingPayments.removeAt(index);
        _todayPayments.add(confirmedPayment);
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تأكيد دفعة ${payment.amount.toStringAsFixed(2)} ر.س'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _rejectPayment(Payment payment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رفض الدفعة'),
        content: const Text('هل تريد رفض هذه الدفعة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _pendingPayments.removeWhere((p) => p.id == payment.id);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم رفض الدفعة'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('رفض'),
          ),
        ],
      ),
    );
  }

  void _generateReceiptForPayment(Payment payment) {
    // TODO: إنشاء إيصال للدفعة
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إنشاء الإيصال... (قيد التطوير)')),
    );
  }
}