import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/time.dart';
import '../../utils/currency_formatter.dart';

class CreateDebtFromBookingScreen extends ConsumerStatefulWidget {
  const CreateDebtFromBookingScreen({super.key});

  @override
  ConsumerState<CreateDebtFromBookingScreen> createState() =>
      _CreateDebtFromBookingScreenState();
}

class _CreateDebtFromBookingScreenState
    extends ConsumerState<CreateDebtFromBookingScreen> {
  Booking? _selectedBooking;
  bool _isComputing = false;
  bool _isProcessing = false;
  _DebtData? _debtData;

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('دين من حجز موجود', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _selectedBooking == null
            ? _buildGuestsList(bookingsAsync)
            : _buildDebtForm(),
      ),
    );
  }

  Widget _buildGuestsList(AsyncValue<List<Booking>> bookingsAsync) {
    return bookingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('خطأ: $e', style: const TextStyle(fontWeight: FontWeight.bold))),
      data: (bookings) {
        final bookedRooms = bookings.where((b) => b.status == 'محجوز').toList();

        if (bookedRooms.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'لا توجد غرف محجوزة حالياً',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'اختر النزيل لتسجيل دين عليه',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: bookedRooms.length,
                itemBuilder: (context, index) {
                  final booking = bookedRooms[index];
                  return _buildGuestCard(booking);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGuestCard(Booking booking) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () => _selectBooking(booking),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    booking.roomNumber,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.orange[800],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.guestName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'هوية: ${booking.idNumber}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (booking.roomRate != null)
                      Text(
                        'سعر الليلة: ${CurrencyFormatter.format(booking.roomRate!)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[500],
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectBooking(Booking booking) async {
    setState(() {
      _selectedBooking = booking;
      _isComputing = true;
    });

    await _computeDebtData(booking);

    setState(() {
      _isComputing = false;
    });
  }

  Future<void> _computeDebtData(Booking booking) async {
    final paymentsRepo = ref.read(paymentsRepoProvider);
    final checkIn = DateTime.tryParse(booking.checkinDate ?? '') ?? DateTime.now();
    final checkout = _resolveCheckout(booking);
    final nights = checkout.difference(checkIn).inDays.clamp(1, 365);
    final rate = booking.roomRate ?? 0.0;
    final total = nights * rate;

    final payments = await paymentsRepo.getForBooking(booking.id);
    final paid = payments.fold<double>(0, (sum, p) => sum + (p.amount ?? 0));

    setState(() {
      _debtData = _DebtData(
        nights: nights,
        roomRate: rate,
        total: total,
        paid: paid,
      );
      _amountController.text = _debtData!.remaining.toStringAsFixed(0);
      _fromDate = checkIn;
      _toDate = checkout;
    });
  }

  Widget _buildDebtForm() {
    if (_isComputing) {
      return const Center(child: CircularProgressIndicator());
    }

    final booking = _selectedBooking!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildInfoRow('النزيل', booking.guestName),
                  _buildInfoRow('الغرفة', booking.roomNumber),
                  _buildInfoRow('رقم الهوية', booking.idNumber),
                  if (_debtData != null) ...[
                    _buildInfoRow('الليالي', '${_debtData!.nights} ليلة'),
                    _buildInfoRow('سعر الليلة', CurrencyFormatter.format(_debtData!.roomRate)),
                    _buildInfoRow('الإجمالي', CurrencyFormatter.format(_debtData!.total)),
                    _buildInfoRow('المدفوع', CurrencyFormatter.format(_debtData!.paid)),
                    Divider(color: Colors.grey[300]),
                    _buildInfoRow(
                      'المتبقي',
                      CurrencyFormatter.format(_debtData!.remaining),
                      valueColor: Colors.red,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildFromDateField()),
              const SizedBox(width: 10),
              Expanded(child: _buildToDateField()),
            ],
          ),
          const SizedBox(height: 12),
          _buildAmountField(),
          const SizedBox(height: 12),
          _buildNotesField(),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _selectedBooking = null;
                      _debtData = null;
                      _amountController.clear();
                      _notesController.clear();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('رجوع', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _saveDebt,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'حفظ الدين',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFromDateField() {
    return InkWell(
      onTap: () => _pickDate(isFrom: true),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'من تاريخ',
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(
          formatDate(_fromDate),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildToDateField() {
    return InkWell(
      onTap: () => _pickDate(isFrom: false),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'إلى تاريخ',
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(
          formatDate(_toDate),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    return TextField(
      controller: _amountController,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      decoration: InputDecoration(
        labelText: 'مبلغ الدين',
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        suffixText: 'ر.ي',
        suffixStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildNotesField() {
    return TextField(
      controller: _notesController,
      maxLines: 4,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      decoration: InputDecoration(
        labelText: 'ملاحظات',
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        hintText: 'أدخل ملاحظات إضافية هنا...',
        hintStyle: TextStyle(fontWeight: FontWeight.normal, color: Colors.grey[400]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        alignLabelWithHint: true,
      ),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initialDate = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
          if (_fromDate.isAfter(_toDate)) {
            _toDate = _fromDate;
          }
        } else {
          _toDate = picked;
          if (_toDate.isBefore(_fromDate)) {
            _fromDate = _toDate;
          }
        }
        _recalculateAmount();
      });
    }
  }

  void _recalculateAmount() {
    if (_debtData == null || _selectedBooking == null) return;
    final nights = _toDate.difference(_fromDate).inDays.clamp(1, 365);
    final total = nights * _debtData!.roomRate;
    final remaining = (total - _debtData!.paid).clamp(0, total);
    _amountController.text = remaining.toStringAsFixed(0);
  }

  Future<void> _saveDebt() async {
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال مبلغ صحيح', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final booking = _selectedBooking!;
      final debtsRepo = ref.read(debtsRepoProvider);

      final debt = Debt(
        id: 0,
        date: _fromDate.toIso8601String().split('T')[0],
        guestName: booking.guestName,
        description: 'دين من حجز غرفة ${booking.roomNumber} (${formatDate(_fromDate)} - ${formatDate(_toDate)})',
        amount: amount,
        paidAmount: 0,
        status: 'غير مسدد',
        bookingId: booking.id,
        dueDate: _toDate.toIso8601String().split('T')[0],
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );

      await debtsRepo.insert(debt);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تسجيل دين بمبلغ ${CurrencyFormatter.format(amount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e', style: const TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  DateTime _resolveCheckout(Booking booking) {
    if (booking.actualCheckout != null && booking.actualCheckout!.isNotEmpty) {
      final actual = DateTime.tryParse(booking.actualCheckout!);
      if (actual != null) return actual;
    }
    if (booking.checkoutDate != null && booking.checkoutDate!.isNotEmpty) {
      final checkout = DateTime.tryParse(booking.checkoutDate!);
      if (checkout != null) return checkout;
    }
    return DateTime.now();
  }
}

class _DebtData {
  final int nights;
  final double roomRate;
  final double total;
  final double paid;

  const _DebtData({
    required this.nights,
    required this.roomRate,
    required this.total,
    required this.paid,
  });

  double get remaining => (total - paid).clamp(0, total);
}
