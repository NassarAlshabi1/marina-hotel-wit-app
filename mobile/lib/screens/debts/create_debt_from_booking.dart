import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/time.dart';
import '../../utils/currency_formatter.dart';

/// شاشة لإنشاء الدين بطريقة تلقائية من الحجز أو يدوية
class CreateDebtFromBookingScreen extends ConsumerStatefulWidget {
  const CreateDebtFromBookingScreen({super.key});

  @override
  ConsumerState<CreateDebtFromBookingScreen> createState() =>
      _CreateDebtFromBookingScreenState();
}

class _CreateDebtFromBookingScreenState
    extends ConsumerState<CreateDebtFromBookingScreen> {
  Booking? _selectedBooking;
  bool _autoMode = true;
  bool _isAutoComputing = false;
  bool _isAutoProcessing = false;
  bool _isManualProcessing = false;
  _AutoDebtData? _autoDebtData;

  late TextEditingController _autoDebtDateController;

  final _manualFormKey = GlobalKey<FormState>();
  late TextEditingController _manualGuestNameController;
  late TextEditingController _manualCheckinController;
  late TextEditingController _manualCheckoutController;
  late TextEditingController _manualTotalController;
  late TextEditingController _manualPaidController;
  late TextEditingController _manualReasonController;
  late TextEditingController _manualNoteController;

  @override
  void initState() {
    super.initState();
    final today = Time.nowDateString();
    _autoDebtDateController = TextEditingController(text: today);
    _manualGuestNameController = TextEditingController();
    _manualCheckinController = TextEditingController(text: today);
    _manualCheckoutController = TextEditingController(text: today);
    _manualTotalController = TextEditingController();
    _manualPaidController = TextEditingController();
    _manualReasonController = TextEditingController(text: 'دين سابق');
    _manualNoteController = TextEditingController();
  }

  @override
  void dispose() {
    _autoDebtDateController.dispose();
    _manualGuestNameController.dispose();
    _manualCheckinController.dispose();
    _manualCheckoutController.dispose();
    _manualTotalController.dispose();
    _manualPaidController.dispose();
    _manualReasonController.dispose();
    _manualNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء دين'),
        backgroundColor: Colors.orange.shade600,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'اختر الوضع المناسب لإنشاء الدين:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '• الوضع التلقائي: تحويل الحجز الحالي إلى دين مع حساب الليالي وسعر الغرفة والمبالغ المدفوعة تلقائياً وتحرير الغرفة.\n'
                    '• الوضع اليدوي: إدخال دين يدوي لأي حالة سابقة أو غير مرتبطة بحجز.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildModeToggle(),
            const SizedBox(height: 16),
            Expanded(
              child: _autoMode
                  ? _buildAutoMode(bookingsAsync)
                  : _buildManualMode(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Row(
      children: [
        Expanded(
          child: ChoiceChip(
            label: const Text('تلقائي (من حجز)'),
            selected: _autoMode,
            onSelected: (value) {
              if (!value) return;
              setState(() => _autoMode = true);
            },
            selectedColor: Colors.orange.shade200,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ChoiceChip(
            label: const Text('يدوي'),
            selected: !_autoMode,
            onSelected: (value) {
              if (!value) return;
              setState(() => _autoMode = false);
            },
            selectedColor: Colors.green.shade200,
          ),
        ),
      ],
    );
  }

  Widget _buildAutoMode(AsyncValue<List<Booking>> bookingsAsync) {
    return bookingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (bookings) {
        final eligibleBookings =
            bookings.where(_isDebtEligibleBooking).toList();

        if (eligibleBookings.isEmpty) {
          return const Center(
            child: Text('لا توجد حجوزات محجوزة أو مكتملة لإنشاء دين منها'),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: eligibleBookings.length,
                itemBuilder: (context, index) {
                  final booking = eligibleBookings[index];
                  final isSelected = booking.id == _selectedBooking?.id;
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
                          Text(
                            '${_formatDate(booking.checkinDate)} - ${_formatDate(booking.checkoutDate ?? '')}',
                          ),
                          Text('الحالة: ${booking.status}'),
                        ],
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle,
                              color: Colors.blue.shade600,
                            )
                          : null,
                      onTap: () => _selectBooking(booking),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            _buildAutoSummaryArea(),
          ],
        );
      },
    );
  }

  Widget _buildAutoSummaryArea() {
    if (_selectedBooking == null) {
      return const Text('اختر حجزاً لعرض تفاصيل الدين التلقائي.');
    }
    if (_isAutoComputing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_autoDebtData == null) {
      return const Text('تعذر حساب بيانات هذا الحجز تلقائياً.');
    }

    final booking = _selectedBooking!;
    final data = _autoDebtData!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'دين ${booking.guestName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildInfoChip(
                  Icons.nightlight,
                  'الليالي',
                  data.nights.toString(),
                ),
                _buildInfoChip(
                  Icons.attach_money,
                  'سعر الليلة',
                  _formatCurrency(data.roomRate),
                ),
                _buildInfoChip(
                  Icons.summarize,
                  'الإجمالي',
                  _formatCurrency(data.total),
                ),
                _buildInfoChip(
                  Icons.payments,
                  'المدفوع',
                  _formatCurrency(data.paid),
                ),
                _buildInfoChip(
                  Icons.warning,
                  'المتبقي',
                  _formatCurrency(data.remaining),
                  color: Colors.red.shade600,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _autoDebtDateController,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                labelText: 'تاريخ الدين',
                labelStyle: const TextStyle(fontSize: 11),
                hintText: 'مثال: 2026-02-01',
                hintStyle: const TextStyle(fontSize: 10),
                prefixIcon: const Icon(Icons.calendar_today, size: 16),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.edit_calendar, size: 18),
                  tooltip: 'اختيار تاريخ',
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.tryParse(_autoDebtDateController.text) ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      _autoDebtDateController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                    }
                  },
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'سيتم إنشاء الدين وتحديث حالة الحجز إلى "مكتمل" وتحرير الغرفة ${booking.roomNumber}.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _isAutoProcessing ? null : _createAutoDebtFromBooking,
                    icon: _isAutoProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _isAutoProcessing ? 'جاري الحفظ...' : 'حفظ وتحرير الغرفة',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
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

  Widget _buildInfoChip(
    IconData icon,
    String label,
    String value, {
    Color? color,
  }) {
    return Chip(
      avatar: Icon(icon, size: 18, color: color ?? Colors.blue),
      label: Text('$label: $value'),
      backgroundColor: (color ?? Colors.blue).withOpacity(0.08),
    );
  }

  Widget _buildManualMode() {
    return SingleChildScrollView(
      child: Form(
        key: _manualFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _manualGuestNameController,
              decoration: const InputDecoration(
                labelText: 'اسم النزيل *',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'أدخل اسم النزيل'
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _manualCheckinController,
                    decoration: const InputDecoration(
                      labelText: 'تاريخ الوصول *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'أدخل تاريخ الوصول'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _manualCheckoutController,
                    decoration: const InputDecoration(
                      labelText: 'تاريخ المغادرة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _manualTotalController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'إجمالي المبلغ *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'أدخل المبلغ'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _manualPaidController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'المبلغ المدفوع',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _manualReasonController,
              decoration: const InputDecoration(
                labelText: 'سبب الدين',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _manualNoteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ملاحظات',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isManualProcessing ? null : _saveManualDebt,
                    icon: _isManualProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _isManualProcessing
                          ? 'جاري الحفظ...'
                          : 'حفظ الدين اليدوي',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _resetManualForm,
                  child: const Text('إعادة تعيين'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _selectBooking(Booking booking) {
    setState(() {
      _selectedBooking = booking;
      _autoDebtData = null;
      _isAutoComputing = true;
      _autoDebtDateController.text = Time.nowDateString();
    });
    _prepareAutoDebtData(booking);
  }

  Future<void> _prepareAutoDebtData(Booking booking) async {
    try {
      final roomsRepo = ref.read(roomsRepoProvider);
      final paymentsRepo = ref.read(paymentsRepoProvider);
      final room = await roomsRepo.watchByNumber(booking.roomNumber).first;
      final payments = await paymentsRepo.paymentsByBooking(booking.id).first;
      final paidAmount = payments.fold<double>(
        0,
        (sum, payment) => sum + payment.amount,
      );

      final checkin = DateTime.tryParse(booking.checkinDate) ?? DateTime.now();
      final checkout = _resolveCheckoutForBooking(booking);
      int nights = Time.nightsWithCutoff(checkin, checkout: checkout);
      if (nights <= 0) {
        nights = 1;
      }

      double roomRate = room?.price ?? 0;
      if (roomRate <= 0 && booking.expectedNights > 0) {
        // استخدم المدفوع كأساس لحساب السعر
        final estimatedTotal = paidAmount > 0
            ? paidAmount
            : (room?.price ?? 0) * booking.expectedNights;
        roomRate = estimatedTotal / booking.expectedNights;
      }
      if (roomRate <= 0) {
        roomRate = paidAmount; // استخدم المدفوع كحل أخير
      }

      final total = nights * roomRate;
      final autoData = _AutoDebtData(
        nights: nights,
        roomRate: roomRate,
        total: total,
        paid: paidAmount,
      );

      if (!mounted) return;
      setState(() {
        _autoDebtData = autoData;
        _isAutoComputing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAutoComputing = false;
        _autoDebtData = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر حساب بيانات الحجز: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _createAutoDebtFromBooking() async {
    if (_selectedBooking == null || _autoDebtData == null) return;

    setState(() => _isAutoProcessing = true);
    final booking = _selectedBooking!;
    final data = _autoDebtData!;
    final nowIso = Time.nowIso();
    final dateOnly = _autoDebtDateController.text.trim().isNotEmpty
        ? _autoDebtDateController.text.trim()
        : Time.nowDateString();

    try {
      final debtsRepo = ref.read(debtsRepoProvider);
      final bookingsRepo = ref.read(bookingsRepoProvider);
      final roomsRepo = ref.read(roomsRepoProvider);

      final existingDebts = await debtsRepo.listByBookingLocalId(booking.id);
      Debt? openDebt;
      for (final debt in existingDebts) {
        if (debt.isSettled == 0 && debt.remainingAmount > 0) {
          openDebt = debt;
          break;
        }
      }

      if (openDebt != null) {
        await debtsRepo.update(
          id: openDebt.id,
          totalAmount: data.total,
          paidAmount: data.paid,
          checkoutDate: nowIso,
          dateRecorded: dateOnly,
          debtReason: 'مغادرة مع مبلغ متبقي',
          note: 'تحديث تلقائي من شاشة الديون - غرفة ${booking.roomNumber}',
        );
      } else {
        await debtsRepo.create(
          bookingLocalId: booking.id,
          guestName: booking.guestName,
          checkinDate: booking.checkinDate,
          checkoutDate: nowIso,
          dateRecorded: dateOnly,
          debtReason: 'مغادرة مع مبلغ متبقي',
          totalAmount: data.total,
          paidAmount: data.paid,
          paymentDate: dateOnly,
          isSettled: false,
          note:
              'تم الإنشاء تلقائياً من شاشة الديون (غرفة ${booking.roomNumber})',
        );
      }

      await bookingsRepo.update(
        booking.id,
        status: 'مكتمل',
        actualCheckout: nowIso,
        calculatedNights: data.nights,
      );

      final room = await roomsRepo.watchByNumber(booking.roomNumber).first;
      if (room != null) {
        await roomsRepo.update(room.id, status: 'شاغرة');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إنشاء الدين (${_formatCurrency(data.remaining)}) وتحرير الغرفة ${booking.roomNumber}',
          ),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      setState(() {
        _selectedBooking = null;
        _autoDebtData = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ الدين: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAutoProcessing = false);
      }
    }
  }

  Future<void> _saveManualDebt() async {
    if (!_manualFormKey.currentState!.validate()) {
      return;
    }

    final total =
        CurrencyFormatter.parseAmount(_manualTotalController.text) ?? 0;
    final paid = CurrencyFormatter.parseAmount(_manualPaidController.text) ?? 0;
    final checkout = _manualCheckoutController.text.trim().isEmpty
        ? _manualCheckinController.text.trim()
        : _manualCheckoutController.text.trim();

    setState(() => _isManualProcessing = true);

    try {
      final debtsRepo = ref.read(debtsRepoProvider);
      await debtsRepo.create(
        guestName: _manualGuestNameController.text.trim(),
        checkinDate: _manualCheckinController.text.trim(),
        checkoutDate: checkout,
        dateRecorded: Time.nowDateString(),
        debtReason: _manualReasonController.text.trim(),
        totalAmount: total,
        paidAmount: paid,
        paymentDate: Time.nowDateString(),
        isSettled: paid >= total,
        note: _manualNoteController.text.trim().isEmpty
            ? null
            : _manualNoteController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ الدين اليدوي بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
      _resetManualForm();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ الدين اليدوي: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isManualProcessing = false);
      }
    }
  }

  void _resetManualForm() {
    final today = Time.nowDateString();
    _manualFormKey.currentState?.reset();
    _manualGuestNameController.clear();
    _manualCheckinController.text = today;
    _manualCheckoutController.text = today;
    _manualTotalController.clear();
    _manualPaidController.clear();
    _manualReasonController.text = 'دين سابق';
    _manualNoteController.clear();
  }

  static bool _isDebtEligibleBooking(Booking booking) {
    final normalized = booking.status.trim().toLowerCase();
    const allowedStatuses = {
      'محجوزة',
      'محجوز',
      'booked',
      'reserved',
      'confirmed',
      'checked_out',
      'checked-out',
      'completed',
      'مكتمل',
    };
    if (allowedStatuses.contains(normalized)) {
      return true;
    }
    return normalized.contains('محجوز') ||
        normalized.contains('مكتمل') ||
        normalized.contains('checked') ||
        normalized.contains('completed');
  }

  String _formatDate(String value) {
    if (value.isEmpty) return '---';
    return Time.safeIsoToDateString(value);
  }

  String _formatCurrency(double value) {
    return CurrencyFormatter.formatAmount(value);
  }

  DateTime _resolveCheckoutForBooking(Booking booking) {
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

class _AutoDebtData {
  final int nights;
  final double roomRate;
  final double total;
  final double paid;

  const _AutoDebtData({
    required this.nights,
    required this.roomRate,
    required this.total,
    required this.paid,
  });

  double get remaining => (total - paid).clamp(0, total);
}
