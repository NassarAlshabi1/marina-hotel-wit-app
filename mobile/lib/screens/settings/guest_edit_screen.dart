import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/repository_providers.dart';
import '../../services/booking_derived_fields_service.dart';
import '../../services/booking_price_adjustment_service.dart';
import '../../services/local_db.dart' hide GuestInfo;
import '../../services/repositories/payments_repository.dart';
import '../../utils/id.dart';
import '../../utils/status_utils.dart';
import 'guest_info.dart';

class GuestEditScreen extends ConsumerStatefulWidget {
  const GuestEditScreen({super.key, required this.guest});

  final GuestInfo guest;

  @override
  ConsumerState<GuestEditScreen> createState() => _GuestEditScreenState();
}

class _GuestEditScreenState extends ConsumerState<GuestEditScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _nationalityController;
  late final TextEditingController _idNumberController;
  late final TextEditingController _idIssueDateController;
  late final TextEditingController _idIssuePlaceController;
  late final TextEditingController _addressController;

  final Map<int, TextEditingController> _discountControllers = {};
  final Map<int, TextEditingController> _discountStartDateControllers = {};
  final Map<int, String> _discountTypeSelections = {};
  final Map<int, TextEditingController> _checkinDateControllers = {};
  final Map<int, AdjustmentType> _adjustmentTypeSelections = {};
  final Map<int, AdjustmentMode> _adjustmentModeSelections = {};

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final _idNumberFormatter = FilteringTextInputFormatter.allow(
    RegExp('[0-9]'),
  );

  bool _saving = false;
  bool _hasUnsavedChanges = false;
  String _idType = 'بطاقة شخصية';

  final Map<int, String> _roomSelections = {};
  final Map<int, String> _originalRooms = {};

  static const _idTypes = [
    'بطاقة شخصية',
    'جواز سفر',
    'رخصة قيادة',
    'بطاقة عسكرية',
    'استبيان',
    'شهادة ميلاد',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.guest.name);
    _phoneController = TextEditingController(text: widget.guest.phone);
    _emailController = TextEditingController(text: widget.guest.email);
    _nationalityController = TextEditingController(
      text: widget.guest.nationality.isNotEmpty
          ? widget.guest.nationality
          : 'يمني',
    );
    _idType = widget.guest.idType;
    _idNumberController = TextEditingController(text: widget.guest.idNumber);
    _idIssueDateController = TextEditingController(
      text: widget.guest.idIssueDate ?? '',
    );
    _idIssuePlaceController = TextEditingController(
      text: widget.guest.idIssuePlace ?? '',
    );
    _addressController = TextEditingController(
      text: widget.guest.address ?? '',
    );

    _nameController.addListener(_markUnsaved);
    _phoneController.addListener(_markUnsaved);
    _emailController.addListener(_markUnsaved);
    _nationalityController.addListener(_markUnsaved);
    _idNumberController.addListener(_markUnsaved);
    _idIssueDateController.addListener(_markUnsaved);
    _idIssuePlaceController.addListener(_markUnsaved);
    _addressController.addListener(_markUnsaved);

    for (final booking in widget.guest.bookings) {
      _roomSelections[booking.id] = booking.roomNumber;
      _originalRooms[booking.id] = booking.roomNumber;
      _discountControllers[booking.id] = TextEditingController(
        text: booking.discount > 0 ? booking.discount.toStringAsFixed(0) : '',
      );
      _discountTypeSelections[booking.id] = booking.discountType;
      _discountStartDateControllers[booking.id] = TextEditingController(
        text: booking.discountStartDate ?? '',
      );
      _checkinDateControllers[booking.id] = TextEditingController(
        text: booking.checkinDate.split('T').first,
      );
      _adjustmentTypeSelections[booking.id] = AdjustmentType.discount;
      _adjustmentModeSelections[booking.id] = AdjustmentMode.perNight;
      _discountControllers[booking.id]!.addListener(_markUnsaved);
      _discountStartDateControllers[booking.id]!.addListener(_markUnsaved);
      _checkinDateControllers[booking.id]!.addListener(_markUnsaved);
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_markUnsaved);
    _phoneController.removeListener(_markUnsaved);
    _emailController.removeListener(_markUnsaved);
    _nationalityController.removeListener(_markUnsaved);
    _idNumberController.removeListener(_markUnsaved);
    _idIssueDateController.removeListener(_markUnsaved);
    _idIssuePlaceController.removeListener(_markUnsaved);
    _addressController.removeListener(_markUnsaved);
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _nationalityController.dispose();
    _idNumberController.dispose();
    _idIssueDateController.dispose();
    _idIssuePlaceController.dispose();
    _addressController.dispose();
    for (final controller in _discountControllers.values) {
      controller.removeListener(_markUnsaved);
      controller.dispose();
    }
    for (final controller in _discountStartDateControllers.values) {
      controller.removeListener(_markUnsaved);
      controller.dispose();
    }
    for (final controller in _checkinDateControllers.values) {
      controller.removeListener(_markUnsaved);
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final hasRoomChanges = _roomSelections.entries.any(
      (entry) => entry.value != _originalRooms[entry.key],
    );

    if (hasRoomChanges) {
      final confirmed = await _showRoomChangeConfirmation();
      if (confirmed != true) {
        return;
      }
    }

    setState(() {
      _saving = true;
    });

    final bookingsRepo = ref.read(bookingsRepoProvider);
    final paymentsRepo = ref.read(paymentsRepoProvider);
    final roomsRepo = ref.read(roomsRepoProvider);
    final db = ref.read(databaseProvider);

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final nationality = _nationalityController.text.trim();
    final idNumber = _idNumberController.text.trim();
    final idIssueDate = _idIssueDateController.text.trim();
    final idIssuePlace = _idIssuePlaceController.text.trim();
    final address = _addressController.text.trim();

    try {
      for (final booking in widget.guest.bookings) {
        final oldRoomNumber = _originalRooms[booking.id]!;
        final newRoomNumber = _roomSelections[booking.id]!;
        final roomChanged = oldRoomNumber != newRoomNumber;
        final discountText =
            _discountControllers[booking.id]?.text.trim() ?? '';
        final discount = _parseAmount(discountText);
        final discountType = _discountTypeSelections[booking.id] ?? 'per_night';
        final discountStartDateText =
            _discountStartDateControllers[booking.id]?.text.trim() ?? '';
        final discountStartDate = discountStartDateText.isNotEmpty
            ? discountStartDateText
            : null;
        final checkinDateText =
            _checkinDateControllers[booking.id]?.text.trim() ?? '';
        final checkinDateChanged =
            checkinDateText.isNotEmpty &&
            checkinDateText != booking.checkinDate.split('T').first;

        await bookingsRepo.update(
          booking.id,
          guestName: name,
          guestPhone: phone,
          guestEmail: email.isNotEmpty ? email : null,
          guestNationality: nationality.isNotEmpty ? nationality : null,
          guestIdType: _idType,
          guestIdNumber: idNumber,
          guestIdIssueDate: idIssueDate.isNotEmpty ? idIssueDate : null,
          guestIdIssuePlace: idIssuePlace.isNotEmpty ? idIssuePlace : null,
          guestAddress: address.isNotEmpty ? address : null,
          roomNumber: newRoomNumber,
          discount: discount,
          discountType: discountType,
          discountStartDate: discountStartDate,
          checkinDate: checkinDateChanged ? checkinDateText : null,
        );

        if (roomChanged) {
          // ─── نقل آمن داخل معاملة واحدة (Transaction) ───
          // يضمن عدم تلف البيانات عند حدوث خطأ أو انقطاع
          await db.transaction(() async {
            await _transferFinancialData(
              db: db,
              paymentsRepo: paymentsRepo,
              bookingId: booking.id,
              newRoomNumber: newRoomNumber,
            );

            if (StatusUtils.isActiveBooking(booking.status)) {
              await roomsRepo.updateByRoomNumber(oldRoomNumber, status: 'شاغرة');
              await roomsRepo.updateByRoomNumber(newRoomNumber, status: 'محجوزة');
            }
          });

          // ─── سجل تدقيق للنقل ───
          await _logRoomTransfer(
            db: db,
            bookingId: booking.id,
            guestName: name,
            oldRoomNumber: oldRoomNumber,
            newRoomNumber: newRoomNumber,
          );
        }

        final derivedService = BookingDerivedFieldsService(db);
        await derivedService.refreshForBookingId(booking.id);
      }

      _hasUnsavedChanges = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasRoomChanges
                  ? 'تم تحديث بيانات الضيف ونقل البيانات المالية بنجاح'
                  : 'تم تحديث بيانات الضيف بنجاح',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop<void>(context, true);
      }
    } catch (Object error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حفظ التغييرات: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _transferFinancialData({
    required AppDatabase db,
    required PaymentsRepository paymentsRepo,
    required int bookingId,
    required String newRoomNumber,
  }) async {
    // 1. نقل المدفوعات — تحديث roomNumber في كل دفعة مرتبطة بالحجز
    final payments =
        await (db.select(db.payments)
              ..where((tbl) => tbl.bookingLocalId.equals(bookingId))
              ..where((tbl) => tbl.deletedAt.isNull()))
            .get();

    for (final payment in payments) {
      await paymentsRepo.update(payment.id, roomNumber: newRoomNumber);
    }

    // 2. نقل تعديلات السعر (التخفيضات والزيادات)
    //    يُحدّث roomNumber + timestamps + outbox entries للمزامنة
    //    ملاحظة: الديون لا تحتاج نقل — مرتبطة بالحجز عبر bookingLocalId فقط
    final adjustmentService = BookingPriceAdjustmentService(db);
    await adjustmentService.transferAdjustmentsToRoom(
      bookingId: bookingId,
      newRoomNumber: newRoomNumber,
    );
  }

  /// سجل تدقيق لنقل الغرفة — يُخزّن في جدول CashTransactions
  Future<void> _logRoomTransfer({
    required AppDatabase db,
    required int bookingId,
    required String guestName,
    required String oldRoomNumber,
    required String newRoomNumber,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      final nowIso = now.toIso8601String();
      final nowEpoch = now.millisecondsSinceEpoch;
      final localUuid = IdGen.uuid();
      final description = 'نقل غرفة الضيف "$guestName" (حجز #$bookingId) '
          'من "$oldRoomNumber" إلى "$newRoomNumber"';

      await db.into(db.cashTransactions).insert(
        CashTransactionsCompanion.insert(
          localUuid: localUuid,
          createdAt: nowEpoch,
          updatedAt: nowEpoch,
          lastModified: nowEpoch,
          transactionType: 'room_transfer',
          amount: 0,
          transactionTime: nowIso,
          description: Value(description),
          referenceType: const Value('booking'),
          referenceId: Value(bookingId),
          createdAtIso: Value(nowIso),
          updatedAtIso: Value(nowIso),
        ),
      );
    } catch (_) {
      // سجل التدقيق غير حرج — لا نوقف العملية إذا فشل
    }
  }

  Future<bool?> _showRoomChangeConfirmation() async {
    // ─── جمع بيانات النقل لعرض تحذير ذكي ───
    final db = ref.read(databaseProvider);
    final changedRooms = <Map<String, String>>[];
    int totalAdjustments = 0;
    int totalPayments = 0;
    String? priceWarning;

    for (final booking in widget.guest.bookings) {
      final oldRoom = _originalRooms[booking.id]!;
      final newRoom = _roomSelections[booking.id]!;
      if (oldRoom == newRoom) continue;

      changedRooms.add({'old': oldRoom, 'new': newRoom});

      // عد التعديلات النشطة
      final adjustments = await (db.select(db.bookingPriceAdjustments)
            ..where((a) => a.bookingLocalId.equals(booking.id))
            ..where((a) => a.isActive.equals(true))
            ..where((a) => a.deletedAt.isNull()))
          .get();
      totalAdjustments += adjustments.length;

      // عد المدفوعات
      final payments = await (db.select(db.payments)
            ..where((p) => p.bookingLocalId.equals(booking.id))
            ..where((p) => p.deletedAt.isNull()))
          .get();
      totalPayments += payments.length;

      // مقارنة أسعار الغرف
      if (priceWarning == null) {
        final oldRoomData = await (db.select(db.rooms)
              ..where((r) => r.roomNumber.equals(oldRoom))
              ..where((r) => r.deletedAt.isNull()))
            .getSingleOrNull();
        final newRoomData = await (db.select(db.rooms)
              ..where((r) => r.roomNumber.equals(newRoom))
              ..where((r) => r.deletedAt.isNull()))
            .getSingleOrNull();

        if (oldRoomData != null && newRoomData != null) {
          final oldPrice = oldRoomData.price.toInt();
          final newPrice = newRoomData.price.toInt();
          if (oldPrice != newPrice) {
            final diff = newPrice - oldPrice;
            final sign = diff > 0 ? '+' : '';
            priceWarning = 'سعر الغرفة يتغير: $oldPrice → $newPrice ريال ($sign$diff)';
          }
        }
      }
    }

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد تغيير الغرفة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيتم نقل البيانات المالية إلى الغرفة (الغرف) الجديدة:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '• المدفوعات: $totalPayments عملية دفع',
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              '• التعديلات النشطة (تخفيضات/زيادات): $totalAdjustments',
              style: const TextStyle(fontSize: 13),
            ),
            const Text(
              '• الديون: مرتبطة بالحجز تلقائياً',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            if (changedRooms.length == 1) ...[
              const SizedBox(height: 8),
              Text(
                'من: ${changedRooms.first['old']} → إلى: ${changedRooms.first['new']}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
            if (priceWarning != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        priceWarning,
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'هل تريد المتابعة؟',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<void>(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop<void>(context, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final initialDate = _parseDate(controller.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    setState(() {
      controller.text = _formatDate(date);
    });
  }

  DateTime? _parseDate(String value) {
    if (value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  double _parseAmount(String value) {
    final normalized = _normalizeNumericInput(value);
    return double.tryParse(normalized) ?? 0;
  }

  String _normalizeNumericInput(String value) {
    var output = value.trim();
    const arabicDigits = <String, String>{
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
    };
    arabicDigits.forEach((arabic, latin) {
      output = output.replaceAll(arabic, latin);
    });
    output = output
        .replaceAll('،', '')
        .replaceAll(',', '')
        .replaceAll(' ', '');
    return output;
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showDiscardDialog(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تعديل بيانات الضيف'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _saveChanges,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(widget.guest.name),
                  subtitle: Text(
                    'عدد الحجوزات: ${widget.guest.bookings.length}',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('البيانات الأساسية'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildTextField(
                        controller: _nameController,
                        label: 'اسم الضيف',
                        icon: Icons.person,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'الاسم مطلوب'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _phoneController,
                        label: 'رقم الهاتف (اختياري)',
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _emailController,
                        label: 'البريد الإلكتروني (اختياري)',
                        icon: Icons.email,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) return null;
                          final emailRegex = RegExp(r'^.+@.+\..+$');
                          if (!emailRegex.hasMatch(value)) {
                            return 'صيغة بريد غير صحيحة';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _nationalityController,
                        label: 'الجنسية',
                        icon: Icons.flag,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'الجنسية مطلوبة'
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('تفاصيل الهوية'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _idType,
                        items: _idTypes
                            .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() {
                              _idType = value ?? _idType;
                              _hasUnsavedChanges = true;
                            }),
                        decoration: const InputDecoration(
                          labelText: 'نوع الهوية',
                          prefixIcon: Icon(Icons.badge),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _idNumberController,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهوية',
                          prefixIcon: Icon(Icons.numbers),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [_idNumberFormatter],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          if (!RegExp(r'^[0-9]+$').hasMatch(value.trim())) {
                            return 'أرقام فقط';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _idIssueDateController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'تاريخ إصدار الهوية',
                                suffixIcon: Icon(Icons.calendar_today),
                                border: OutlineInputBorder(),
                              ),
                              onTap: () => _pickDate(_idIssueDateController),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _idIssuePlaceController,
                              decoration: const InputDecoration(
                                labelText: 'جهة الإصدار',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('معلومات إضافية'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildTextField(
                    controller: _addressController,
                    label: 'العنوان (اختياري)',
                    icon: Icons.location_on,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('الحجوزات والغرف'),
              ...widget.guest.bookings.map(_buildBookingRoomCard),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _saveChanges,
                icon: const Icon(Icons.save),
                label: const Text('حفظ التعديلات'),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  void _markUnsaved() {
    if (!_hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = true);
    }
  }

  void _showDiscardDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تغييرات غير محفوظة'),
          content: const Text('هل تريد المغادرة بدون حفظ التغييرات؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop<void>(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop<void>(ctx);
                Navigator.of(context).pop<void>();
              },
              child: const Text('مغادرة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildBookingRoomCard(Booking booking) {
    final roomsAsync = ref.watch(roomsListProvider);
    final discountController = _discountControllers[booking.id]!;
    final discountStartDateController =
        _discountStartDateControllers[booking.id]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hotel, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'حجز رقم ${booking.id}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'حالة: ${booking.status} • دخول: ${booking.checkinDate}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            roomsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
              error: (err, stack) => TextFormField(
                initialValue: _roomSelections[booking.id],
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'رقم الغرفة *',
                  helperText: 'تعذر تحميل قائمة الغرف',
                  border: OutlineInputBorder(),
                ),
              ),
              data: (rooms) {
                final availableRooms =
                    rooms
                        .where(
                          (room) => StatusUtils.isRoomAvailable(room.status),
                        )
                        .toList()
                      ..sort((a, b) => a.roomNumber.compareTo(b.roomNumber));

                final currentValue = _roomSelections[booking.id]!;
                final items = <DropdownMenuItem<String>>[];

                if (!availableRooms.any(
                  (room) => room.roomNumber == currentValue,
                )) {
                  items.add(
                    DropdownMenuItem(
                      value: currentValue,
                      child: Text('$currentValue (الحالي)'),
                    ),
                  );
                }

                items.addAll(
                  availableRooms.map(
                    (room) => DropdownMenuItem(
                      value: room.roomNumber,
                      child: Text('${room.roomNumber} • ${room.type}'),
                    ),
                  ),
                );

                final originalRoom = _originalRooms[booking.id];
                final isChanged = currentValue != originalRoom;

                return Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: currentValue,
                      items: items,
                      onChanged: (value) {
                        setState(() {
                          _roomSelections[booking.id] = value ?? currentValue;
                          _hasUnsavedChanges = true;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'رقم الغرفة *',
                        border: const OutlineInputBorder(),
                        suffixIcon: isChanged
                            ? const Icon(Icons.edit, color: Colors.orange)
                            : null,
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'مطلوب'
                          : null,
                    ),
                    if (isChanged)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'سيتم نقل الغرفة من $originalRoom إلى $currentValue',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _checkinDateControllers[booking.id],
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'تاريخ الدخول',
                        prefixIcon: const Icon(Icons.login),
                        hintText: 'اضغط لتعديل تاريخ الدخول',
                        border: const OutlineInputBorder(),
                        suffixIcon:
                            _checkinDateControllers[booking.id]!.text !=
                                booking.checkinDate.split('T').first
                            ? const Icon(Icons.edit, color: Colors.orange)
                            : null,
                      ),
                      onTap: () async {
                        final controller = _checkinDateControllers[booking.id]!;
                        await _pickDate(controller);
                        setState(() {});
                      },
                    ),
                    if (_checkinDateControllers[booking.id]!.text !=
                        booking.checkinDate.split('T').first)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'سيتم تغيير تاريخ الدخول وإعادة حساب المبالغ تلقائياً',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<BookingPriceAdjustment>>(
                      future: BookingPriceAdjustmentService(ref.read(databaseProvider))
                          .getActiveAdjustments(booking.localUuid),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        // ─── حماية: تصفية التعديلات الوهمية/اليتيمة ───
                        final bookingDiscount = booking.discount;
                        final adjustments = snapshot.data!.where((adj) {
                          // استبعاد سجلات legacy_discount دائماً (لا تُعرض في UI)
                          // هي سجلات داخلية يديرها النظام ولا علاقة لها بالمستخدم
                          if (adj.reason == 'legacy_discount') {
                            return false;
                          }
                          // تخطي سجلات التخفيض بدون سبب إذا لم يكن هناك تخفيض
                          if (bookingDiscount <= 0 &&
                              adj.adjustmentType == 0 &&
                              adj.reason == null) {
                            return false;
                          }
                          return true;
                        }).toList();

                        if (adjustments.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.amber.shade700),
                                  const SizedBox(width: 8),
                                  Text(
                                    'التعديلات الحالية (${adjustments.length})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...adjustments.map((adj) {
                                final isDiscount = adj.adjustmentType == 0;
                                final typeName = isDiscount ? 'تخفيض' : 'زيادة';
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isDiscount ? Icons.discount : Icons.trending_up,
                                        size: 20,
                                        color: isDiscount ? Colors.green : Colors.orange,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '$typeName: ${adj.amount} ريال',
                                              style: const TextStyle(fontWeight: FontWeight.w600),
                                            ),
                                            Text(
                                              'من ${adj.effectiveHotelDay}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      ElevatedButton.icon(
                                        onPressed: () => _endPriceAdjustment(adj.localUuid, typeName),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red.shade400,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        ),
                                        icon: const Icon(Icons.stop_circle, size: 18),
                                        label: Text('إنهاء $typeName'),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _adjustmentTypeSelections[booking.id] == AdjustmentType.discount
                                    ? Icons.discount
                                    : Icons.trending_up,
                                color: _adjustmentTypeSelections[booking.id] == AdjustmentType.discount
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'تعديل السعر (زيادة / تخفيض)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<AdjustmentType>(
                            initialValue: _adjustmentTypeSelections[booking.id],
                            decoration: const InputDecoration(
                              labelText: 'نوع التعديل',
                              prefixIcon: Icon(Icons.swap_vert),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: AdjustmentType.discount,
                                child: Text('تخفيض'),
                              ),
                              DropdownMenuItem(
                                value: AdjustmentType.surcharge,
                                child: Text('زيادة'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _adjustmentTypeSelections[booking.id] = value!;
                                _hasUnsavedChanges = true;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<AdjustmentMode>(
                            initialValue: _adjustmentModeSelections[booking.id],
                            decoration: const InputDecoration(
                              labelText: 'طريقة الحساب',
                              prefixIcon: Icon(Icons.calculate),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: AdjustmentMode.perNight,
                                child: Text('لكل ليلة'),
                              ),
                              DropdownMenuItem(
                                value: AdjustmentMode.total,
                                child: Text('على الإجمالي'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _adjustmentModeSelections[booking.id] = value!;
                                _hasUnsavedChanges = true;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: discountController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp('[0-9٠-٩.,،]'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'المبلغ',
                              prefixIcon: Icon(Icons.attach_money),
                              border: OutlineInputBorder(),
                              isDense: true,
                              hintText: 'مثال: 5000',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: discountStartDateController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'ابتداءً من تاريخ',
                              prefixIcon: Icon(Icons.event),
                              border: OutlineInputBorder(),
                              isDense: true,
                              helperText: 'يستمر حتى الإلغاء',
                            ),
                            onTap: () => _pickDate(discountStartDateController),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _adjustmentTypeSelections[booking.id] == AdjustmentType.discount
                                    ? Colors.green
                                    : Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.add_circle_outline),
                              label: Text(
                                _adjustmentTypeSelections[booking.id] == AdjustmentType.discount
                                    ? 'تطبيق التخفيض'
                                    : 'تطبيق الزيادة',
                              ),
                              onPressed: () => _applyPriceAdjustment(booking),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyPriceAdjustment(Booking booking) async {
    final discountController = _discountControllers[booking.id];
    final startDateController = _discountStartDateControllers[booking.id];
    
    if (discountController == null || startDateController == null) return;
    
    final amountText = discountController.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال المبلغ')),
      );
      return;
    }
    
    final amount = _parseAmount(amountText).round();
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال مبلغ صالح')),
      );
      return;
    }
    
    var startDate = startDateController.text.trim();
    if (startDate.isEmpty) {
      startDate = _formatDate(DateTime.now());
      startDateController.text = startDate;
    }
    
    final type = _adjustmentTypeSelections[booking.id] ?? AdjustmentType.discount;
    final mode = _adjustmentModeSelections[booking.id] ?? AdjustmentMode.perNight;
    
    try {
      setState(() => _saving = true);
      
      final db = ref.read(databaseProvider);
      await BookingPriceAdjustmentService(db).applyTemporaryAdjustment(
        bookingLocalUuid: booking.localUuid,
        amount: amount,
        type: type,
        mode: mode,
        effectiveHotelDay: startDate,
        reason: '${type == AdjustmentType.discount ? 'تخفيض' : 'زيادة'} من شاشة تعديل الضيف',
        appliedBy: 'admin',
      );
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type == AdjustmentType.discount
                ? 'تم تطبيق التخفيض بنجاح'
                : 'تم تطبيق الزيادة بنجاح',
          ),
          backgroundColor: Colors.green,
        ),
      );
      
      discountController.clear();
      startDateController.clear();
      
    } catch (Object e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _endPriceAdjustment(String adjustmentUuid, String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الإنهاء'),
        content: Text('هل تريد إنهاء $type من اليوم؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<void>(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop<void>(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إنهاء'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      setState(() => _saving = true);
      final db = ref.read(databaseProvider);
      await BookingPriceAdjustmentService(db).cancelAdjustment(
        adjustmentUuid: adjustmentUuid,
        cancelledBy: 'admin',
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إنهاء $type بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (Object e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
