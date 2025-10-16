import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booking.dart';

class PaymentCheckoutScreen extends StatefulWidget {
  final Booking booking;
  const PaymentCheckoutScreen({super.key, required this.booking});

  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends State<PaymentCheckoutScreen> {
  late List<BookingPaymentEntry> _payments;
  late Booking _currentBooking;
  final NumberFormat _numberFormat = NumberFormat.decimalPattern('en');
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm', 'en');

  @override
  void initState() {
    super.initState();
    _payments = List<BookingPaymentEntry>.from(widget.booking.payments);
    _refreshBooking();
  }

  void _refreshBooking() {
    _currentBooking = widget.booking.copyWith(payments: List.unmodifiable(_payments));
  }

  double get _remaining => _currentBooking.remaining();

  Future<void> _addPayment() async {
    if (_remaining <= 0) {
      return;
    }

    final entry = await _showPaymentDialog();
    if (entry != null && mounted) {
      setState(() {
        _payments.add(entry);
        _refreshBooking();
      });
      _showSnack('تم إضافة الدفعة بنجاح', Colors.green);
    }
  }

  Future<void> _editPayment(int index) async {
    final entry = await _showPaymentDialog(initial: _payments[index], index: index);
    if (entry != null && mounted) {
      setState(() {
        _payments[index] = entry;
        _refreshBooking();
      });
      _showSnack('تم تعديل الدفعة', Colors.blue);
    }
  }

  Future<void> _deletePayment(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الدفعة'),
          content: const Text('هل أنت متأكد من حذف الدفعة المحددة؟'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _payments.removeAt(index);
        _refreshBooking();
      });
      _showSnack('تم حذف الدفعة', Colors.red);
    }
  }

  Future<BookingPaymentEntry?> _showPaymentDialog({BookingPaymentEntry? initial, int? index}) async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(
      text: initial != null ? initial.amount.toStringAsFixed(initial.amount.truncateToDouble() == initial.amount ? 0 : 2) : '',
    );
    final notesController = TextEditingController(text: initial?.notes ?? '');
    String method = initial?.method ?? 'نقدي';

    double maxAllowed = _maxAmountAllowed(skipIndex: index);
    if (maxAllowed <= 0 && index == null) {
      _showSnack('لا توجد مبالغ متبقية لإضافتها', Colors.orange);
      return null;
    }

    return showDialog<BookingPaymentEntry>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(index == null ? 'إضافة دفعة جديدة' : 'تعديل الدفعة'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'المبلغ',
                    helperText: 'الحد الأقصى: ${_numberFormat.format(maxAllowed)}',
                  ),
                  validator: (value) {
                    final raw = (value ?? '').replaceAll(',', '').trim();
                    final parsed = double.tryParse(raw);
                    if (parsed == null) {
                      return 'أدخل مبلغاً صالحاً';
                    }
                    if (parsed <= 0) {
                      return 'يجب أن يكون المبلغ أكبر من صفر';
                    }
                    if (parsed > maxAllowed + 1e-6) {
                      return 'لا يمكن أن يتجاوز المبلغ ${_numberFormat.format(maxAllowed)}';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: const InputDecoration(labelText: 'طريقة الدفع'),
                  items: const [
                    DropdownMenuItem(value: 'نقدي', child: Text('نقدي')),
                    DropdownMenuItem(value: 'بطاقة', child: Text('بطاقة ائتمان')),
                    DropdownMenuItem(value: 'تحويل', child: Text('تحويل بنكي')),
                    DropdownMenuItem(value: 'شيك', child: Text('شيك')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      method = value;
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final parsed = double.parse(amountController.text.replaceAll(',', '').trim());
                  Navigator.of(ctx).pop(
                    BookingPaymentEntry(
                      amount: parsed,
                      paymentDate: initial?.paymentDate ?? DateTime.now(),
                      method: method,
                      notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                    ),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  double _maxAmountAllowed({int? skipIndex}) {
    final payments = List<BookingPaymentEntry>.from(_payments);
    if (skipIndex != null) {
      payments.removeAt(skipIndex);
    }
    final temp = widget.booking.copyWith(payments: List.unmodifiable(payments));
    final remaining = temp.remaining();
    final allowed = remaining <= 0 ? 0 : remaining;
    return allowed;
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  void _completeCheckout() {
    _showSnack('تم إتمام تسجيل المغادرة بنجاح', Colors.green);
  }

  Future<bool> _handleWillPop() async {
    Navigator.of(context).pop(_currentBooking);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final totalDue = _currentBooking.totalDue();
    final paid = _currentBooking.paidTotal;

    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الدفع والمغادرة'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_currentBooking),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('معلومات الحجز', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      _infoRow(Icons.person, 'النزيل', _currentBooking.guestName),
                      _infoRow(Icons.bed, 'الغرفة', _currentBooking.roomNumber),
                      _infoRow(
                        Icons.night_shelter,
                        'عدد الليالي',
                        '${_currentBooking.nightsForBilling()} ليلة',
                      ),
                      _infoRow(
                        Icons.price_change,
                        'سعر الليلة',
                        _numberFormat.format(_currentBooking.nightlyRate),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _totalRow('الإجمالي', _numberFormat.format(totalDue), Colors.blue),
                      const SizedBox(height: 6),
                      _totalRow('المدفوع', _numberFormat.format(paid), Colors.green),
                      const Divider(),
                      _totalRow(
                        'المتبقي',
                        _numberFormat.format(_remaining),
                        _remaining > 0 ? Colors.red : Colors.green,
                        isBold: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('سجل المدفوعات', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (_payments.isEmpty)
                          const Expanded(
                            child: Center(child: Text('لا توجد مدفوعات مسجلة')),
                          )
                        else
                          Expanded(
                            child: ListView.builder(
                              itemCount: _payments.length,
                              itemBuilder: (context, index) {
                                final payment = _payments[index];
                                return Card(
                                  elevation: 0,
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    leading: const Icon(Icons.receipt_long, color: Colors.green),
                                    title: Text(
                                      _numberFormat.format(payment.amount),
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_dateFormat.format(payment.paymentDate)),
                                        Text('طريقة الدفع: ${payment.method}'),
                                        if (payment.notes != null && payment.notes!.isNotEmpty)
                                          Text('ملاحظات: ${payment.notes!}'),
                                      ],
                                    ),
                                    trailing: Wrap(
                                      spacing: 0,
                                      children: [
                                        IconButton(
                                          tooltip: 'تعديل',
                                          onPressed: () => _editPayment(index),
                                          icon: const Icon(Icons.edit, color: Colors.blue),
                                        ),
                                        IconButton(
                                          tooltip: 'حذف',
                                          onPressed: () => _deletePayment(index),
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _remaining <= 0 ? null : _addPayment,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('إضافة دفعة'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _remaining > 0 ? null : _completeCheckout,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('تسجيل المغادرة'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: color, fontWeight: isBold ? FontWeight.w800 : FontWeight.w600)),
        Text(value, style: TextStyle(color: color, fontWeight: isBold ? FontWeight.w800 : FontWeight.w700)),
      ],
    );
  }
}
