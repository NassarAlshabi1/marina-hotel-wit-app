import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as d;
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/local_db.dart';
import '../../utils/time.dart';

class BookingCheckoutScreen extends ConsumerStatefulWidget {
  final Booking booking;
  
  const BookingCheckoutScreen({
    super.key,
    required this.booking,
  });

  @override
  ConsumerState<BookingCheckoutScreen> createState() => _BookingCheckoutScreenState();
}

class _BookingCheckoutScreenState extends ConsumerState<BookingCheckoutScreen> {
  bool _isProcessing = false;
  
  @override
  Widget build(BuildContext context) {
    final paymentsRepo = ref.watch(paymentsRepoProvider);
    final roomsRepo = ref.watch(roomsRepoProvider);
    
    return AppScaffold(
      title: 'دفع الحجز',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // معلومات الحجز
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
                    Text('رقم الغرفة: ${widget.booking.roomNumber}'),
                    Text('تاريخ الدخول: ${widget.booking.checkinDate}'),
                    if (widget.booking.checkoutDate != null)
                      Text('تاريخ الخروج: ${widget.booking.checkoutDate}'),
                    Text('الحالة: ${widget.booking.status}'),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // المدفوعات السابقة
            Text(
              'المدفوعات السابقة',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: StreamBuilder<List<Payment>>(
                stream: paymentsRepo.paymentsByBooking(widget.booking.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
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
                  
                  final payments = snapshot.data!;
                  final totalPaid = payments.fold<double>(
                    0, 
                    (sum, payment) => sum + payment.amount,
                  );
                  
                  return Column(
                    children: [
                      // إجمالي المدفوع
                      Card(
                        color: Colors.green.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'إجمالي المدفوع:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${totalPaid.toStringAsFixed(2)} ريال',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // قائمة المدفوعات
                      Expanded(
                        child: ListView.builder(
                          itemCount: payments.length,
                          itemBuilder: (context, index) {
                            final payment = payments[index];
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  payment.paymentMethod == 'نقدي' 
                                      ? Icons.money 
                                      : Icons.credit_card,
                                  color: Colors.green,
                                ),
                                title: Text(
                                  '${payment.amount.toStringAsFixed(2)} ريال',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('طريقة الدفع: ${payment.paymentMethod}'),
                                    Text('النوع: ${payment.revenueType}'),
                                    Text('التاريخ: ${payment.paymentDate}'),
                                    if (payment.notes != null && payment.notes!.isNotEmpty)
                                      Text('ملاحظات: ${payment.notes}'),
                                  ],
                                ),
                                trailing: payment.roomNumber != null 
                                    ? Chip(
                                        label: Text(payment.roomNumber!),
                                        backgroundColor: Colors.blue.shade50,
                                      )
                                    : null,
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
            
            const SizedBox(height: 16),
            
            // أزرار العمليات
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _addPayment(context),
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
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _completeCheckout(context),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('إتمام الحجز'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _addPayment(BuildContext context) async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    String selectedMethod = 'نقدي';
    String selectedType = 'room';
    
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
                  decoration: const InputDecoration(
                    labelText: 'المبلغ *',
                    suffixText: 'ريال',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedMethod,
                  decoration: const InputDecoration(
                    labelText: 'طريقة الدفع',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'نقدي', child: Text('نقدي')),
                    DropdownMenuItem(value: 'بطاقة', child: Text('بطاقة ائتمان')),
                    DropdownMenuItem(value: 'تحويل', child: Text('تحويل بنكي')),
                    DropdownMenuItem(value: 'شيك', child: Text('شيك')),
                  ],
                  onChanged: (value) => selectedMethod = value!,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'نوع الإيراد',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'room', child: Text('إيراد غرفة')),
                    DropdownMenuItem(value: 'service', child: Text('خدمات إضافية')),
                    DropdownMenuItem(value: 'deposit', child: Text('عربون')),
                    DropdownMenuItem(value: 'other', child: Text('أخرى')),
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
    
    if (result == true) {
      final amount = double.tryParse(amountController.text);
      if (amount == null || amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى إدخال مبلغ صحيح'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
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
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إضافة الدفعة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }
  
  Future<void> _completeCheckout(BuildContext context) async {
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              child: const Text('إتمام'),
            ),
          ],
        ),
      ),
    );
    
    if (result == true) {
      setState(() => _isProcessing = true);
      
      try {
        final bookingsRepo = ref.read(bookingsRepoProvider);
        final roomsRepo = ref.read(roomsRepoProvider);
        
        // تحديث حالة الحجز
        await bookingsRepo.update(
          widget.booking.id,
          status: 'مكتمل',
          checkoutDate: Time.nowIso(),
        );
        
        // تحديث حالة الغرفة إلى شاغرة
        final roomsStream = roomsRepo.watchByNumber(widget.booking.roomNumber);
        final room = await roomsStream.first;
        if (room != null) {
          await roomsRepo.update(
            room.id,
            status: 'شاغرة',
          );
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إتمام الحجز بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        
        Navigator.of(context).pop();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }
}