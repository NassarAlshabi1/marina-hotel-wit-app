import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../models/payment_models.dart';

class PaymentHistoryScreen extends ConsumerStatefulWidget {
  final String? bookingId; // null يعني عرض جميع المدفوعات
  
  const PaymentHistoryScreen({
    super.key,
    this.bookingId,
  });

  @override
  ConsumerState<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends ConsumerState<PaymentHistoryScreen> {
  PaymentMethod? _selectedMethod;
  PaymentStatus? _selectedStatus;
  DateTimeRange? _dateRange;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // بيانات تجريبية
  List<Payment> _allPayments = [];

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  void _loadPayments() {
    // بيانات تجريبية
    _allPayments = [
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
        bookingId: 'booking_1',
        amount: 150.0,
        method: PaymentMethod.card,
        status: PaymentStatus.completed,
        paymentDate: DateTime.now().subtract(const Duration(hours: 1)),
        cardLastFourDigits: '1234',
        referenceNumber: 'REF789456',
        receivedBy: 'admin',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      Payment(
        id: '3',
        bookingId: 'booking_2',
        amount: 500.0,
        method: PaymentMethod.transfer,
        status: PaymentStatus.pending,
        paymentDate: DateTime.now().subtract(const Duration(minutes: 30)),
        bankName: 'البنك الأهلي',
        referenceNumber: 'TRF123456',
        notes: 'تحويل من حساب العميل',
        receivedBy: 'cashier',
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
        updatedAt: DateTime.now().subtract(const Duration(minutes: 30)),
      ),
    ];

    // فلترة حسب الحجز إذا تم تحديده
    if (widget.bookingId != null) {
      _allPayments = _allPayments.where((p) => p.bookingId == widget.bookingId).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredPayments = _getFilteredPayments();
    
    return AppScaffold(
      title: widget.bookingId != null ? 'سجل مدفوعات الحجز' : 'سجل جميع المدفوعات',
      actions: [
        IconButton(
          onPressed: _showFilterDialog,
          icon: const Icon(Icons.filter_list),
          tooltip: 'تصفية',
        ),
        IconButton(
          onPressed: () => _exportPayments(filteredPayments),
          icon: const Icon(Icons.file_download),
          tooltip: 'تصدير',
        ),
      ],
      body: Column(
        children: [
          // شريط البحث والإحصائيات
          _buildSearchAndStats(filteredPayments),
          
          const SizedBox(height: 16),
          
          // قائمة المدفوعات
          Expanded(
            child: _buildPaymentsList(filteredPayments),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndStats(List<Payment> payments) {
    final totalAmount = payments.fold<double>(0, (sum, p) => sum + p.amount);
    final completedCount = payments.where((p) => p.status == PaymentStatus.completed).length;
    
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          // شريط البحث
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'البحث في المدفوعات...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty 
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // إحصائيات سريعة
          Row(
            children: [
              Expanded(child: _buildStatChip('إجمالي المدفوعات', payments.length, Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('مكتملة', completedCount, Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('المبلغ الإجمالي', totalAmount.toStringAsFixed(0), Colors.purple)),
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
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsList(List<Payment> payments) {
    if (payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.payment, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('لا توجد مدفوعات', style: TextStyle(fontSize: 18)),
            if (_hasActiveFilters())
              TextButton(
                onPressed: _clearFilters,
                child: const Text('مسح الفلاتر'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: payments.length,
      itemBuilder: (context, index) {
        final payment = payments[index];
        return _buildPaymentCard(context, payment);
      },
    );
  }

  Widget _buildPaymentCard(BuildContext context, Payment payment) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // رأس الدفعة
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: payment.method.color.withOpacity(0.2),
                  child: Icon(payment.method.icon, color: payment.method.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${payment.amount.toStringAsFixed(2)} ر.س',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        payment.method.displayName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: payment.status.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: payment.status.color),
                  ),
                  child: Text(
                    payment.status.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: payment.status.color,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // تفاصيل الدفعة
            Row(
              children: [
                Expanded(
                  child: _buildDetailChip('التاريخ', _formatDateTime(payment.paymentDate), Icons.calendar_today),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDetailChip('المحاسب', payment.receivedBy, Icons.person),
                ),
              ],
            ),
            
            if (payment.referenceNumber != null || payment.cardLastFourDigits != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (payment.referenceNumber != null)
                    Expanded(
                      child: _buildDetailChip('رقم المرجع', payment.referenceNumber!, Icons.confirmation_number),
                    ),
                  if (payment.referenceNumber != null && payment.cardLastFourDigits != null)
                    const SizedBox(width: 8),
                  if (payment.cardLastFourDigits != null)
                    Expanded(
                      child: _buildDetailChip('البطاقة', '****${payment.cardLastFourDigits}', Icons.credit_card),
                    ),
                ],
              ),
            ],
            
            if (payment.bankName != null || payment.notes != null) ...[
              const SizedBox(height: 8),
              if (payment.bankName != null)
                _buildDetailChip('البنك', payment.bankName!, Icons.account_balance),
              if (payment.notes != null && payment.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ملاحظات:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      Text(
                        payment.notes!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            
            const SizedBox(height: 12),
            
            // أزرار العمليات
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _generateReceipt(payment),
                    icon: const Icon(Icons.receipt, size: 16),
                    label: const Text('طباعة إيصال'),
                  ),
                ),
                const SizedBox(width: 8),
                if (payment.status == PaymentStatus.completed)
                  OutlinedButton(
                    onPressed: () => _showRefundDialog(payment),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('استرداد'),
                  ),
                if (payment.status == PaymentStatus.pending)
                  ElevatedButton(
                    onPressed: () => _confirmPayment(payment),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('تأكيد'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Payment> _getFilteredPayments() {
    var filtered = _allPayments;

    // فلترة حسب البحث
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((p) {
        return p.bookingId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            p.receivedBy.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (p.notes?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
            (p.referenceNumber?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      }).toList();
    }

    // فلترة حسب طريقة الدفع
    if (_selectedMethod != null) {
      filtered = filtered.where((p) => p.method == _selectedMethod).toList();
    }

    // فلترة حسب الحالة
    if (_selectedStatus != null) {
      filtered = filtered.where((p) => p.status == _selectedStatus).toList();
    }

    // فلترة حسب التاريخ
    if (_dateRange != null) {
      filtered = filtered.where((p) {
        return p.paymentDate.isAfter(_dateRange!.start) &&
            p.paymentDate.isBefore(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    return filtered;
  }

  bool _hasActiveFilters() {
    return _selectedMethod != null || 
           _selectedStatus != null || 
           _dateRange != null || 
           _searchQuery.isNotEmpty;
  }

  void _clearFilters() {
    setState(() {
      _selectedMethod = null;
      _selectedStatus = null;
      _dateRange = null;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('تصفية المدفوعات'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // فلترة طريقة الدفع
                  const Text('طريقة الدفع:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('الكل'),
                        selected: _selectedMethod == null,
                        onSelected: (selected) => setDialogState(() => _selectedMethod = null),
                      ),
                      ...PaymentMethod.values.map((method) => FilterChip(
                        label: Text(method.displayName),
                        selected: _selectedMethod == method,
                        onSelected: (selected) => setDialogState(() => _selectedMethod = selected ? method : null),
                      )),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // فلترة الحالة
                  const Text('الحالة:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('الكل'),
                        selected: _selectedStatus == null,
                        onSelected: (selected) => setDialogState(() => _selectedStatus = null),
                      ),
                      ...PaymentStatus.values.map((status) => FilterChip(
                        label: Text(status.displayName),
                        selected: _selectedStatus == status,
                        onSelected: (selected) => setDialogState(() => _selectedStatus = selected ? status : null),
                      )),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // فلترة التاريخ
                  ListTile(
                    leading: const Icon(Icons.date_range),
                    title: const Text('فترة زمنية'),
                    subtitle: Text(
                      _dateRange != null
                          ? '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}'
                          : 'جميع التواريخ',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_dateRange != null)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setDialogState(() => _dateRange = null),
                          ),
                        IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: () async {
                            final range = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 30)),
                              initialDateRange: _dateRange,
                            );
                            if (range != null) {
                              setDialogState(() => _dateRange = range);
                            }
                          },
                        ),
                      ],
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
              ElevatedButton(
                onPressed: () {
                  setState(() {}); // تطبيق الفلاتر
                  Navigator.pop(context);
                },
                child: const Text('تطبيق'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _generateReceipt(Payment payment) {
    // TODO: إنشاء الإيصال
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إنشاء الإيصال... (قيد التطوير)')),
    );
  }

  void _showRefundDialog(Payment payment) {
    final reasonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('استرداد الدفعة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('المبلغ المراد استرداده: ${payment.amount.toStringAsFixed(2)} ر.س'),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'سبب الاسترداد*',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى كتابة سبب الاسترداد')),
                  );
                  return;
                }
                
                Navigator.pop(context);
                _processRefund(payment, reasonController.text.trim());
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('تأكيد الاسترداد'),
            ),
          ],
        ),
      ),
    );
  }

  void _processRefund(Payment payment, String reason) {
    setState(() {
      final refundedPayment = payment.copyWith(
        status: PaymentStatus.refunded,
        notes: '${payment.notes ?? ''}\nمسترد: $reason',
        updatedAt: DateTime.now(),
      );
      
      final index = _allPayments.indexWhere((p) => p.id == payment.id);
      if (index != -1) {
        _allPayments[index] = refundedPayment;
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم استرداد ${payment.amount.toStringAsFixed(2)} ر.س'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _confirmPayment(Payment payment) {
    setState(() {
      final confirmedPayment = payment.copyWith(
        status: PaymentStatus.completed,
        updatedAt: DateTime.now(),
      );
      
      final index = _allPayments.indexWhere((p) => p.id == payment.id);
      if (index != -1) {
        _allPayments[index] = confirmedPayment;
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تأكيد دفعة ${payment.amount.toStringAsFixed(2)} ر.س'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _exportPayments(List<Payment> payments) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تصدير المدفوعات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('اختر تنسيق التصدير:'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _exportToPDF(payments);
                    },
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('PDF'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _exportToExcel(payments);
                    },
                    icon: const Icon(Icons.table_chart),
                    label: const Text('Excel'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  void _exportToPDF(List<Payment> payments) {
    // TODO: تصدير إلى PDF
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تصدير التقرير كـ PDF... (قيد التطوير)')),
    );
  }

  void _exportToExcel(List<Payment> payments) {
    // TODO: تصدير إلى Excel
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تصدير التقرير كـ Excel... (قيد التطوير)')),
    );
  }
}