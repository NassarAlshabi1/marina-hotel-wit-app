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
  DateTime _autoDebtDate = DateTime.now();

  final _manualFormKey = GlobalKey<FormState>();
  late TextEditingController _manualGuestNameController;
  late TextEditingController _manualCheckinController;
  late TextEditingController _manualCheckoutController;
  late TextEditingController _manualTotalController;
  late TextEditingController _manualPaidController;
  late TextEditingController _manualReasonController;
  late TextEditingController _manualNoteController;
  late TextEditingController _manualDebtDateController;

  @override
  void initState() {
    super.initState();
    final today = Time.nowDateString();
    _manualGuestNameController = TextEditingController();
    _manualCheckinController = TextEditingController(text: today);
    _manualCheckoutController = TextEditingController(text: today);
    _manualTotalController = TextEditingController();
    _manualPaidController = TextEditingController();
    _manualReasonController = TextEditingController(text: 'دين سابق');
    _manualNoteController = TextEditingController();
    _manualDebtDateController = TextEditingController(text: today);
  }

  @override
  void dispose() {
    _manualGuestNameController.dispose();
    _manualCheckinController.dispose();
    _manualCheckoutController.dispose();
    _manualTotalController.dispose();
    _manualPaidController.dispose();
    _manualReasonController.dispose();
    _manualNoteController.dispose();
    _manualDebtDateController.dispose();
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
                    'اختر الوضع:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• تلقائي: من حجز موجود\n• يدوي: إدخال بيانات الدين',
                    style: TextStyle(fontSize: 11, height: 1.3, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildModeToggle(),
            const SizedBox(height: 12),
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _autoMode = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _autoMode ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _autoMode
                      ? [BoxShadow(color: Colors.black12, blurRadius: 4)]
                      : null,
                ),
                child: Text(
                  'تلقائي',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _autoMode ? FontWeight.bold : FontWeight.normal,
                    color: _autoMode ? Colors.blue.shade700 : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _autoMode = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !_autoMode ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: !_autoMode
                      ? [BoxShadow(color: Colors.black12, blurRadius: 4)]
                      : null,
                ),
                child: Text(
                  'يدوي',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: !_autoMode ? FontWeight.bold : FontWeight.normal,
                    color: !_autoMode ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
              child: Text('لا توجد حجوزات محجوزة أو مكتملة لإنشاء دين منها'));
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
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue.shade50 : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? Colors.blue.shade300 : Colors.grey.shade200,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blue : Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            booking.roomNumber,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      title: Text(booking.guestName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${_formatDate(booking.checkinDate)} - ${_formatDate(booking.checkoutDate ?? '')}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: Colors.blue.shade600, size: 20)
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'دين ${booking.guestName}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildInfoBox('الليالي', data.nights.toString(), Colors.blue),
              const SizedBox(width: 8),
              _buildInfoBox('سعر الليلة', _formatCurrency(data.roomRate), Colors.teal),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildInfoBox('الإجمالي', _formatCurrency(data.total), Colors.indigo),
              const SizedBox(width: 8),
              _buildInfoBox('المدفوع', _formatCurrency(data.paid), Colors.green),
              const SizedBox(width: 8),
              _buildInfoBox('المتبقي', _formatCurrency(data.remaining), Colors.red),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _pickAutoDebtDate(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 18, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('تاريخ تسجيل الدين', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        Text(
                          '${_autoDebtDate.year}-${_autoDebtDate.month.toString().padLeft(2, '0')}-${_autoDebtDate.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.edit, size: 16, color: Colors.blue.shade600),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'سيتم إنشاء الدين وتحرير الغرفة ${booking.roomNumber}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isAutoProcessing ? null : _createAutoDebtFromBooking,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _isAutoProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('حفظ وتحرير الغرفة', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: color)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
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
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'اسم النزيل *',
                labelStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'أدخل اسم النزيل'
                  : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _manualCheckinController,
                    readOnly: true,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'تاريخ الوصول *',
                      labelStyle: const TextStyle(fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      suffixIcon: const Icon(Icons.calendar_today, size: 16),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'أدخل تاريخ الوصول'
                        : null,
                    onTap: () => _pickDate(_manualCheckinController),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _manualCheckoutController,
                    readOnly: true,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'تاريخ المغادرة',
                      labelStyle: const TextStyle(fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      suffixIcon: const Icon(Icons.calendar_today, size: 16),
                    ),
                    onTap: () => _pickDate(_manualCheckoutController),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _manualTotalController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'إجمالي المبلغ *',
                      labelStyle: const TextStyle(fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'أدخل المبلغ'
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _manualPaidController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'المبلغ المدفوع',
                      labelStyle: const TextStyle(fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _manualReasonController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'سبب الدين',
                labelStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _manualDebtDateController,
              readOnly: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'تاريخ تسجيل الدين',
                labelStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: const Icon(Icons.calendar_today, size: 18),
              ),
              onTap: () => _pickManualDebtDate(),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _manualNoteController,
              maxLines: 2,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'ملاحظات',
                labelStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isManualProcessing ? null : _saveManualDebt,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isManualProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('حفظ الدين', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _resetManualForm,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('مسح', style: TextStyle(fontSize: 13)),
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
      // تعيين تاريخ الدين من تاريخ المغادرة أو الوصول
      final checkoutDate = booking.checkoutDate != null && booking.checkoutDate!.isNotEmpty
          ? DateTime.tryParse(booking.checkoutDate!)
          : null;
      final checkinDate = DateTime.tryParse(booking.checkinDate);
      _autoDebtDate = checkoutDate ?? checkinDate ?? DateTime.now();
    });
    _prepareAutoDebtData(booking);
  }

  Future<void> _pickAutoDebtDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _autoDebtDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _autoDebtDate = picked);
    }
  }

  Future<void> _pickManualDebtDate() async {
    final initial = DateTime.tryParse(_manualDebtDateController.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _manualDebtDateController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _prepareAutoDebtData(Booking booking) async {
    try {
      final roomsRepo = ref.read(roomsRepoProvider);
      final paymentsRepo = ref.read(paymentsRepoProvider);
      final room = await roomsRepo.watchByNumber(booking.roomNumber).first;
      final payments = await paymentsRepo.paymentsByBooking(booking.id).first;
      final paidAmount =
          payments.fold<double>(0, (sum, payment) => sum + payment.amount);

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
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _createAutoDebtFromBooking() async {
    if (_selectedBooking == null || _autoDebtData == null) return;

    setState(() => _isAutoProcessing = true);
    final booking = _selectedBooking!;
    final data = _autoDebtData!;
    final nowIso = Time.nowIso();
    final selectedDateIso = _autoDebtDate.toIso8601String();
    final selectedDateOnly = '${_autoDebtDate.year}-${_autoDebtDate.month.toString().padLeft(2, '0')}-${_autoDebtDate.day.toString().padLeft(2, '0')}';

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
          checkoutDate: selectedDateIso,
          dateRecorded: selectedDateOnly,
          debtReason: 'مغادرة مع مبلغ متبقي',
          note: 'تحديث تلقائي من شاشة الديون - غرفة ${booking.roomNumber}',
        );
      } else {
        await debtsRepo.create(
          bookingLocalId: booking.id,
          guestName: booking.guestName,
          checkinDate: booking.checkinDate,
          checkoutDate: selectedDateIso,
          dateRecorded: selectedDateOnly,
          debtReason: 'مغادرة مع مبلغ متبقي',
          totalAmount: data.total,
          paidAmount: data.paid,
          paymentDate: selectedDateOnly,
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
              'تم إنشاء الدين (${_formatCurrency(data.remaining)}) وتحرير الغرفة ${booking.roomNumber}'),
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
            content: Text('فشل حفظ الدين: $e'), backgroundColor: Colors.red),
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
    final debtDate = _manualDebtDateController.text.trim().isEmpty
        ? Time.nowDateString()
        : _manualDebtDateController.text.trim();

    setState(() => _isManualProcessing = true);

    try {
      final debtsRepo = ref.read(debtsRepoProvider);
      await debtsRepo.create(
        guestName: _manualGuestNameController.text.trim(),
        checkinDate: _manualCheckinController.text.trim(),
        checkoutDate: checkout,
        dateRecorded: debtDate,
        debtReason: _manualReasonController.text.trim(),
        totalAmount: total,
        paidAmount: paid,
        paymentDate: debtDate,
        isSettled: paid >= total,
        note: _manualNoteController.text.trim().isEmpty
            ? null
            : _manualNoteController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تم حفظ الدين اليدوي بنجاح'),
            backgroundColor: Colors.green),
      );
      _resetManualForm();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('فشل حفظ الدين اليدوي: $e'),
            backgroundColor: Colors.red),
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
    _manualDebtDateController.text = today;
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
