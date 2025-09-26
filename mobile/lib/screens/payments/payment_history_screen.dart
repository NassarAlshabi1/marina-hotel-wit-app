import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/local_db.dart';
import '../../utils/time.dart';

class PaymentHistoryScreen extends ConsumerStatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  ConsumerState<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends ConsumerState<PaymentHistoryScreen> {
  String? _selectedRevenueType;
  String? _selectedPaymentMethod;
  DateTime? _fromDate;
  DateTime? _toDate;
  
  final List<String> _revenueTypes = ['room', 'service', 'deposit', 'other'];
  final List<String> _paymentMethods = ['نقدي', 'بطاقة', 'تحويل', 'شيك'];

  @override
  Widget build(BuildContext context) {
    final paymentsRepo = ref.watch(paymentsRepoProvider);
    
    return AppScaffold(
      title: 'تاريخ المدفوعات',
      actions: [
        IconButton(
          icon: const Icon(Icons.filter_list),
          onPressed: _showFilterDialog,
        ),
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: _clearFilters,
        ),
      ],
      body: Column(
        children: [
          // شريط الفلاتر
          if (_hasActiveFilters()) _buildActiveFiltersChips(),
          
          // قائمة المدفوعات
          Expanded(
            child: StreamBuilder<List<Payment>>(
              stream: paymentsRepo.paymentsByBooking(-1), // -1 لجلب كل المدفوعات
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'حدث خطأ في تحميل البيانات',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                }
                
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.payment_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'لا توجد مدفوعات مسجلة',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'عند إضافة مدفوعات جديدة ستظهر هنا',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }
                
                List<Payment> payments = snapshot.data!;
                
                // تطبيق الفلاتر
                payments = _applyFilters(payments);
                
                if (payments.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.filter_list_off,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'لا توجد مدفوعات تطابق الفلاتر المحددة',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'جرب تعديل الفلاتر أو إزالتها',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }
                
                // حساب الإجمالي
                final totalAmount = payments.fold<double>(
                  0, 
                  (sum, payment) => sum + payment.amount,
                );
                
                return Column(
                  children: [
                    // شريط الإحصائيات
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.shade400, Colors.green.shade600],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'إجمالي المدفوعات',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${totalAmount.toStringAsFixed(2)} ريال',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'عدد المدفوعات: ${payments.length}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // قائمة المدفوعات
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: payments.length,
                        itemBuilder: (context, index) {
                          final payment = payments[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _getPaymentMethodColor(payment.paymentMethod).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _getPaymentMethodIcon(payment.paymentMethod),
                                  color: _getPaymentMethodColor(payment.paymentMethod),
                                ),
                              ),
                              title: Text(
                                '${payment.amount.toStringAsFixed(2)} ريال',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.payment, size: 16, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Text(
                                        payment.paymentMethod,
                                        style: TextStyle(color: Colors.grey.shade700),
                                      ),
                                      const SizedBox(width: 12),
                                      Icon(Icons.category, size: 16, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Text(
                                        _getRevenueTypeLabel(payment.revenueType),
                                        style: TextStyle(color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Text(
                                        payment.paymentDate,
                                        style: TextStyle(color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
                                  if (payment.notes != null && payment.notes!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(Icons.note, size: 16, color: Colors.grey.shade600),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            payment.notes!,
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              trailing: payment.roomNumber != null 
                                  ? Chip(
                                      label: Text(payment.roomNumber!),
                                      backgroundColor: Colors.blue.shade50,
                                    )
                                  : null,
                              onTap: () => _showPaymentDetails(payment),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  bool _hasActiveFilters() {
    return _selectedRevenueType != null || 
           _selectedPaymentMethod != null || 
           _fromDate != null || 
           _toDate != null;
  }
  
  Widget _buildActiveFiltersChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          if (_selectedRevenueType != null)
            Chip(
              label: Text('النوع: ${_getRevenueTypeLabel(_selectedRevenueType!)}'),
              onDeleted: () => setState(() => _selectedRevenueType = null),
            ),
          if (_selectedPaymentMethod != null)
            Chip(
              label: Text('الطريقة: $_selectedPaymentMethod'),
              onDeleted: () => setState(() => _selectedPaymentMethod = null),
            ),
          if (_fromDate != null)
            Chip(
              label: Text('من: ${Time.dateToString(_fromDate!)}'),
              onDeleted: () => setState(() => _fromDate = null),
            ),
          if (_toDate != null)
            Chip(
              label: Text('إلى: ${Time.dateToString(_toDate!)}'),
              onDeleted: () => setState(() => _toDate = null),
            ),
        ],
      ),
    );
  }
  
  List<Payment> _applyFilters(List<Payment> payments) {
    return payments.where((payment) {
      // فلتر نوع الإيراد
      if (_selectedRevenueType != null && 
          payment.revenueType != _selectedRevenueType) {
        return false;
      }
      
      // فلتر طريقة الدفع
      if (_selectedPaymentMethod != null && 
          payment.paymentMethod != _selectedPaymentMethod) {
        return false;
      }
      
      // فلتر التاريخ
      if (_fromDate != null || _toDate != null) {
        try {
          final paymentDate = DateTime.parse(payment.paymentDate);
          if (_fromDate != null && paymentDate.isBefore(_fromDate!)) {
            return false;
          }
          if (_toDate != null && paymentDate.isAfter(_toDate!)) {
            return false;
          }
        } catch (e) {
          // إذا فشل تحليل التاريخ، تجاهل هذا الفلتر
        }
      }
      
      return true;
    }).toList();
  }
  
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('فلترة المدفوعات'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // فلتر نوع الإيراد
                  DropdownButtonFormField<String>(
                    value: _selectedRevenueType,
                    decoration: const InputDecoration(
                      labelText: 'نوع الإيراد',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('جميع الأنواع')),
                      ..._revenueTypes.map((type) => DropdownMenuItem(
                        value: type, 
                        child: Text(_getRevenueTypeLabel(type)),
                      )),
                    ],
                    onChanged: (value) => setDialogState(() => _selectedRevenueType = value),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // فلتر طريقة الدفع
                  DropdownButtonFormField<String>(
                    value: _selectedPaymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'طريقة الدفع',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('جميع الطرق')),
                      ..._paymentMethods.map((method) => DropdownMenuItem(
                        value: method, 
                        child: Text(method),
                      )),
                    ],
                    onChanged: (value) => setDialogState(() => _selectedPaymentMethod = value),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // فلتر التاريخ من
                  ListTile(
                    title: const Text('من تاريخ'),
                    subtitle: Text(_fromDate != null ? Time.dateToString(_fromDate!) : 'غير محدد'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: _fromDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setDialogState(() => _fromDate = date);
                      }
                    },
                  ),
                  
                  // فلتر التاريخ إلى
                  ListTile(
                    title: const Text('إلى تاريخ'),
                    subtitle: Text(_toDate != null ? Time.dateToString(_toDate!) : 'غير محدد'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: _toDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setDialogState(() => _toDate = date);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {}); // تحديث الشاشة الرئيسية
                  Navigator.of(ctx).pop();
                },
                child: const Text('تطبيق الفلاتر'),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _clearFilters() {
    setState(() {
      _selectedRevenueType = null;
      _selectedPaymentMethod = null;
      _fromDate = null;
      _toDate = null;
    });
  }
  
  void _showPaymentDetails(Payment payment) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تفاصيل الدفعة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('المبلغ', '${payment.amount.toStringAsFixed(2)} ريال'),
              _buildDetailRow('طريقة الدفع', payment.paymentMethod),
              _buildDetailRow('نوع الإيراد', _getRevenueTypeLabel(payment.revenueType)),
              _buildDetailRow('التاريخ', payment.paymentDate),
              if (payment.roomNumber != null)
                _buildDetailRow('رقم الغرفة', payment.roomNumber!),
              if (payment.notes != null && payment.notes!.isNotEmpty)
                _buildDetailRow('ملاحظات', payment.notes!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق'),
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
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
  
  String _getRevenueTypeLabel(String type) {
    switch (type) {
      case 'room':
        return 'إيراد غرفة';
      case 'service':
        return 'خدمات إضافية';
      case 'deposit':
        return 'عربون';
      case 'other':
        return 'أخرى';
      default:
        return type;
    }
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