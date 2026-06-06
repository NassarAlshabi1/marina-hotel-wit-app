import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
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
  final _dateFormat = DateFormat('yyyy-MM-dd');
  static const _titleStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.bold,
  );
  static const _labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.bold,
  );
  static const _fieldStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.bold,
  );

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) => _dateFormat.format(date);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _showDiscardDialog(context);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('إنشاء دين من حجز')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBookingSelector(),
            if (_selectedBooking != null) ...[
              const SizedBox(height: 16),
              _buildBookingInfo(),
              const SizedBox(height: 16),
              _buildDateRangeSelector(),
              const SizedBox(height: 16),
              _buildComputeButton(),
              if (_debtData != null) ...[
                const SizedBox(height: 16),
                _buildDebtSummary(),
                const SizedBox(height: 16),
                _buildAmountField(),
                const SizedBox(height: 16),
                _buildNotesField(),
                const SizedBox(height: 24),
                _buildCreateButton(),
              ],
            ],
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildBookingSelector() {
    final bookingsRepo = ref.watch(bookingsRepoProvider);
    return StreamBuilder<List<Booking>>(
      stream: bookingsRepo.watchList(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final bookings = snapshot.data!
            .where((b) => b.status != 'checked_out' && b.status != 'cancelled')
            .toList();
        if (bookings.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا توجد حجوزات نشطة'),
            ),
          );
        }
        final dropdownColor = Theme.of(context).textTheme.bodyMedium?.color;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('اختر الحجز', style: _titleStyle),
                const SizedBox(height: 8),
                DropdownButtonFormField<Booking>(
                  value: bookings.contains(_selectedBooking) ? _selectedBooking : null,
                  isExpanded: true,
                  style: _fieldStyle.copyWith(color: dropdownColor),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: bookings.map((booking) {
                    return DropdownMenuItem(
                      value: booking,
                      child: Text(
                        '${booking.roomNumber} - ${booking.guestName}',
                        overflow: TextOverflow.ellipsis,
                        style: _fieldStyle.copyWith(color: dropdownColor),
                      ),
                    );
                  }).toList(),
                  onChanged: (booking) {
                    setState(() {
                      _selectedBooking = booking;
                      _debtData = null;
                      if (booking != null) {
                        final checkin = DateTime.tryParse(booking.checkinDate);
                        if (checkin != null) {
                          _fromDate = checkin;
                          _toDate = _resolveCheckout(booking);
                        }
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBookingInfo() {
    final booking = _selectedBooking!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('معلومات الحجز', style: _titleStyle),
            const SizedBox(height: 8),
            _buildInfoRow('الغرفة', booking.roomNumber),
            _buildInfoRow('الضيف', booking.guestName),
            _buildInfoRow('الهوية', booking.guestIdNumber),
            _buildInfoRow('تاريخ الدخول', booking.checkinDate.split(' ')[0]),
            if (booking.checkoutDate != null)
              _buildInfoRow(
                'تاريخ الخروج',
                booking.checkoutDate!.split(' ')[0],
              ),
            _buildInfoRow('الحالة', booking.status),
            _buildInfoRow(
              'الإجمالي المستحق',
              CurrencyFormatter.formatAmount(booking.totalDueCached),
            ),
            _buildInfoRow(
              'المدفوع',
              CurrencyFormatter.formatAmount(booking.totalPaidCached),
            ),
            _buildInfoRow(
              'المتبقي',
              CurrencyFormatter.formatAmount(booking.remainingBalanceCached),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(child: Text(value, style: _fieldStyle)),
        ],
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('فترة الدين', style: _titleStyle),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildDateField(
                    'من',
                    _fromDate,
                    (date) => setState(() => _fromDate = date),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildDateField(
                    'إلى',
                    _toDate,
                    (date) => setState(() => _toDate = date),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField(
    String label,
    DateTime date,
    ValueChanged<DateTime> onChanged,
  ) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: _labelStyle,
          floatingLabelStyle: _labelStyle,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(_formatDate(date), style: _fieldStyle),
      ),
    );
  }

  Widget _buildComputeButton() {
    return ElevatedButton.icon(
      onPressed: _isComputing ? null : _computeDebt,
      icon: _isComputing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.calculate),
      label: Text(_isComputing ? 'جاري الحساب...' : 'احسب الدين'),
    );
  }

  Future<void> _computeDebt() async {
    if (_selectedBooking == null) {
      return;
    }

    setState(() => _isComputing = true);

    try {
      final booking = _selectedBooking!;
      final nights = _toDate.difference(_fromDate).inDays;
      if (nights <= 0) {
        _showError('فترة غير صالحة');
        return;
      }

      final nightlyRate = booking.totalNightsCached > 0
          ? booking.totalDueCached / booking.totalNightsCached
          : 0.0;

      final total = nightlyRate * nights;
      final paid = booking.totalPaidCached;

      setState(() {
        _debtData = _DebtData(
          nights: nights,
          roomRate: nightlyRate,
          total: total,
          paid: paid,
        );
        _amountController.text = CurrencyFormatter.formatAmount(
          _debtData!.remaining,
        );
      });
    } finally {
      setState(() => _isComputing = false);
    }
  }

  Widget _buildDebtSummary() {
    final data = _debtData!;
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ملخص الدين', style: _titleStyle),
            const SizedBox(height: 8),
            _buildInfoRow('عدد الليالي', '${data.nights}'),
            _buildInfoRow(
              'سعر الليلة',
              CurrencyFormatter.formatAmount(data.roomRate),
            ),
            _buildInfoRow(
              'الإجمالي',
              CurrencyFormatter.formatAmount(data.total),
            ),
            _buildInfoRow('المدفوع', CurrencyFormatter.formatAmount(data.paid)),
            const Divider(),
            _buildInfoRow(
              'المتبقي (الدين)',
              CurrencyFormatter.formatAmount(data.remaining),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    return TextFormField(
      controller: _amountController,
      keyboardType: TextInputType.number,
      style: _fieldStyle,
      decoration: const InputDecoration(
        labelText: 'مبلغ الدين',
        labelStyle: _labelStyle,
        floatingLabelStyle: _labelStyle,
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.attach_money),
      ),
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      maxLines: 3,
      style: _fieldStyle,
      decoration: const InputDecoration(
        labelText: 'ملاحظات',
        labelStyle: _labelStyle,
        floatingLabelStyle: _labelStyle,
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.note),
      ),
    );
  }

  Widget _buildCreateButton() {
    return ElevatedButton.icon(
      onPressed: _isProcessing ? null : _createDebt,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      icon: _isProcessing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.add),
      label: Text(_isProcessing ? 'جاري الإنشاء...' : 'إنشاء الدين'),
    );
  }

  Future<void> _createDebt() async {
    if (_selectedBooking == null || _debtData == null) {
      return;
    }

    final amount = CurrencyFormatter.parseAmount(_amountController.text);
    if (amount == null || amount <= 0) {
      _showError('يرجى إدخال مبلغ صحيح');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final booking = _selectedBooking!;
      final debtsRepo = ref.read(debtsRepoProvider);
      final now = DateTime.now();

      await debtsRepo.create(
        bookingLocalId: booking.id,
        guestName: booking.guestName,
        checkinDate: _formatDate(_fromDate),
        checkoutDate: _formatDate(_toDate),
        dateRecorded: _formatDate(now),
        debtReason:
            'دين من حجز الغرفة ${booking.roomNumber} للفترة ${_formatDate(_fromDate)} - ${_formatDate(_toDate)}',
        totalAmount: amount,
        paidAmount: 0,
        paymentDate: _formatDate(now),
        note: _notesController.text.isNotEmpty ? _notesController.text : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إنشاء الدين بمبلغ ${CurrencyFormatter.formatAmount(amount)}',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('حدث خطأ: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  DateTime _resolveCheckout(Booking booking) {
    if (booking.actualCheckout != null && booking.actualCheckout!.isNotEmpty) {
      final actual = DateTime.tryParse(booking.actualCheckout!);
      if (actual != null) {
        return actual;
      }
    }
    if (booking.checkoutDate != null && booking.checkoutDate!.isNotEmpty) {
      final checkout = DateTime.tryParse(booking.checkoutDate!);
      if (checkout != null) {
        return checkout;
      }
    }
    return DateTime.now();
  }

  bool get _hasUnsavedChanges =>
      _selectedBooking != null ||
      _debtData != null ||
      _amountController.text.isNotEmpty ||
      _notesController.text.isNotEmpty;

  void _showDiscardDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد'),
          content: const Text('هل تريد المغادرة بدون حفظ التغييرات؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('لا'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).pop();
              },
              child: const Text('نعم'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtData {

  const _DebtData({
    required this.nights,
    required this.roomRate,
    required this.total,
    required this.paid,
  });
  final int nights;
  final double roomRate;
  final double total;
  final double paid;

  double get remaining => (total - paid).clamp(0, total).toDouble();
}
