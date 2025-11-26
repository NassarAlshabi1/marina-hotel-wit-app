import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/time.dart';

/// شاشة لإنشاء دين من حجز موجود
class CreateDebtFromBookingScreen extends ConsumerStatefulWidget {
  const CreateDebtFromBookingScreen({super.key});

  @override
  ConsumerState<CreateDebtFromBookingScreen> createState() => _CreateDebtFromBookingScreenState();
}

class _CreateDebtFromBookingScreenState extends ConsumerState<CreateDebtFromBookingScreen> {
  Booking? _selectedBooking;
  int _actualNights = 0;
  double _roomRate = 0;
  double _totalCost = 0;
  double _paidAmount = 0;
  String _debtReason = 'إقامة أيام إضافية بدون دفع';

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsListProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء دين من حجز'),
        backgroundColor: Colors.orange.shade600,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // شرح الميزة
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      const Text(
                        'كيفية استخدام هذه الميزة:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '١. اختر الحجز الذي له دين\n'
                    '٢. أدخل عدد الأيام الفعلية التي مكث فيها النزيل\n'
                    '٣. أدخل سعر الغرفة لليلة الواحدة\n'
                    '٤. أدخل المبلغ الذي دفعه النزيل\n'
                    '٥. سيتم حساب الدين تلقائياً',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // اختيار الحجز
            const Text('اختر الحجز:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            
            Expanded(
              child: bookingsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (bookings) {
                  // تصفية الحجوزات المكتملة فقط
                  final completedBookings = bookings.where((b) => 
                    b.status == 'completed' || b.status == 'checked_out').toList();
                  
                  if (completedBookings.isEmpty) {
                    return const Center(
                      child: Text('لا توجد حجوزات مكتملة لإنشاء ديون منها'),
                    );
                  }
                  
                  return Column(
                    children: [
                      // قائمة الحجوزات
                      Expanded(
                        flex: 2,
                        child: ListView.builder(
                          itemCount: completedBookings.length,
                          itemBuilder: (context, index) {
                            final booking = completedBookings[index];
                            final isSelected = _selectedBooking?.id == booking.id;
                            
                            return Card(
                              color: isSelected ? Colors.blue.shade50 : null,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isSelected ? Colors.blue : Colors.grey,
                                  child: Text(booking.roomNumber),
                                ),
                                title: Text(booking.guestName),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('غرفة ${booking.roomNumber}'),
                                    Text('${_formatDate(booking.checkinDate)} - ${_formatDate(booking.checkoutDate ?? "")}'),
                                  ],
                                ),
                                trailing: isSelected ? 
                                  Icon(Icons.check_circle, color: Colors.blue.shade600) : null,
                                onTap: () => _selectBooking(booking),
                              ),
                            );
                          },
                        ),
                      ),
                      
                      // تفاصيل الحساب
                      if (_selectedBooking != null)
                        Expanded(
                          flex: 1,
                          child: _buildCalculationSection(),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _selectedBooking != null ? Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 4)],
        ),
        child: ElevatedButton(
          onPressed: _createDebt,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade600,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
          ),
          child: Text('إنشاء دين بقيمة ${(_totalCost - _paidAmount).toStringAsFixed(0)}'),
        ),
      ) : null,
    );
  }

  Widget _buildCalculationSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تفاصيل الحساب - ${_selectedBooking!.guestName}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'عدد الليالي الفعلية',
                    border: OutlineInputBorder(),
                    suffixText: 'ليلة',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    setState(() {
                      _actualNights = int.tryParse(value) ?? 0;
                      _calculateCost();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'سعر الغرفة/الليلة',
                    border: OutlineInputBorder(),
                    // suffixText: 'ر.س',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    setState(() {
                      _roomRate = double.tryParse(value) ?? 0;
                      _calculateCost();
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          TextField(
            decoration: const InputDecoration(
              labelText: 'المبلغ المدفوع',
              border: OutlineInputBorder(),
              // suffixText: 'ر.س',
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              setState(() {
                _paidAmount = double.tryParse(value) ?? 0;
              });
            },
          ),
          const SizedBox(height: 12),
          
          TextField(
            controller: TextEditingController(text: _debtReason),
            decoration: const InputDecoration(
              labelText: 'سبب الدين',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => _debtReason = value,
          ),
          const SizedBox(height: 16),
          
          // نتيجة الحساب
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.shade300),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('إجمالي التكلفة:'),
                    Text('${_totalCost.toStringAsFixed(0)}', 
                         style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('المبلغ المدفوع:'),
                    Text('${_paidAmount.toStringAsFixed(0)}', 
                         style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('الدين المتبقي:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('${(_totalCost - _paidAmount).toStringAsFixed(0)}', 
                         style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700, fontSize: 16)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectBooking(Booking booking) {
    setState(() {
      _selectedBooking = booking;
      
      // محاولة حساب عدد الليالي تلقائياً باستخدام منطق 14:00
      if (booking.checkinDate.isNotEmpty && booking.checkoutDate?.isNotEmpty == true) {
        final checkin = DateTime.tryParse(booking.checkinDate);
        final checkout = DateTime.tryParse(booking.checkoutDate!);
        if (checkin != null && checkout != null) {
          _actualNights = Time.nightsWithCutoff(checkin, checkout: checkout);
        }
      } else {
        _actualNights = booking.calculatedNights;
      }
      
      _calculateCost();
    });
  }

  void _calculateCost() {
    _totalCost = _actualNights * _roomRate;
  }

  String _formatDate(String value) {
    return Time.safeIsoToDateString(value);
  }

  Future<void> _createDebt() async {
    if (_selectedBooking == null) return;
    
    final debtAmount = _totalCost - _paidAmount;
    if (debtAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد دين للإنشاء - المبلغ المدفوع أكبر من أو يساوي التكلفة')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد إنشاء الدين'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('النزيل: ${_selectedBooking!.guestName}'),
            Text('الغرفة: ${_selectedBooking!.roomNumber}'),
            Text('عدد الليالي: $_actualNights'),
            Text('إجمالي التكلفة: ${_totalCost.toStringAsFixed(0)}'),
            Text('المدفوع: ${_paidAmount.toStringAsFixed(0)}'),
            Text('الدين: ${debtAmount.toStringAsFixed(0)}', 
                 style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إنشاء الدين'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final repo = ref.read(debtsRepoProvider);
    await repo.create(
      bookingLocalId: _selectedBooking!.id,
      guestName: _selectedBooking!.guestName,
      checkinDate: _selectedBooking!.checkinDate,
      checkoutDate: _selectedBooking!.checkoutDate ?? Time.nowDateString(),
      dateRecorded: Time.nowDateString(),
      debtReason: _debtReason,
      totalAmount: _totalCost,
      paidAmount: _paidAmount,
      paymentDate: Time.nowDateString(),
      isSettled: false,
      note: 'تم الإنشاء من حجز رقم ${_selectedBooking!.id} - '
            'مكث $_actualNights ليلة بدلاً من ${_selectedBooking!.expectedNights}',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء الدين بنجاح')),
      );
      Navigator.pop(context); // العودة للشاشة السابقة
    }
  }
}