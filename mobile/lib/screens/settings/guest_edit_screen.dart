import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../services/repositories/payments_repository.dart';
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
  final Map<int, TextEditingController> _checkinDateControllers = {};

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final _idNumberFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'[0-9]'),
  );

  bool _saving = false;
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
      text: widget.guest.nationality,
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

    for (final booking in widget.guest.bookings) {
      _roomSelections[booking.id] = booking.roomNumber;
      _originalRooms[booking.id] = booking.roomNumber;
      _discountControllers[booking.id] = TextEditingController(
        text: booking.discount > 0 ? booking.discount.toStringAsFixed(0) : '',
      );
      _discountStartDateControllers[booking.id] = TextEditingController(
        text: booking.discountStartDate ?? '',
      );
      _checkinDateControllers[booking.id] = TextEditingController(
        text: booking.checkinDate.split('T').first,
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _nationalityController.dispose();
    _idNumberController.dispose();
    _idIssueDateController.dispose();
    _idIssuePlaceController.dispose();
    _addressController.dispose();
    for (final controller in _discountControllers.values) {
      controller.dispose();
    }
    for (final controller in _discountStartDateControllers.values) {
      controller.dispose();
    }
    for (final controller in _checkinDateControllers.values) {
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
        final discountText = _discountControllers[booking.id]?.text.trim() ?? '';
        final discount = double.tryParse(discountText) ?? 0;
        final discountStartDateText =
            _discountStartDateControllers[booking.id]?.text.trim() ?? '';
        final discountStartDate =
            discountStartDateText.isNotEmpty ? discountStartDateText : null;
        final checkinDateText =
            _checkinDateControllers[booking.id]?.text.trim() ?? '';
        final checkinDateChanged = checkinDateText.isNotEmpty &&
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
          discountStartDate: discountStartDate,
          checkinDate: checkinDateChanged ? checkinDateText : null,
        );

        if (roomChanged) {
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
        }
      }

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
        Navigator.pop(context, true);
      }
    } catch (error) {
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
    final payments = await (db.select(db.payments)
          ..where((tbl) => tbl.bookingLocalId.equals(bookingId))
          ..where((tbl) => tbl.deletedAt.isNull()))
        .get();

    for (final payment in payments) {
      await paymentsRepo.update(payment.id, roomNumber: newRoomNumber);
    }
  }

  Future<bool?> _showRoomChangeConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد تغيير الغرفة'),
        content: const Text(
          'سيتم نقل جميع البيانات المالية (المدفوعات والديون) إلى الغرفة الجديدة.\n\nهل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
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

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                        value: _idType,
                        items: _idTypes
                            .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _idType = value ?? _idType),
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
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _saveChanges,
                icon: const Icon(Icons.save),
                label: const Text('حفظ التعديلات'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                final availableRooms = rooms
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
                      value: currentValue,
                      items: items,
                      onChanged: (value) {
                        setState(() {
                          _roomSelections[booking.id] = value ?? currentValue;
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
                        suffixIcon: _checkinDateControllers[booking.id]!.text !=
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
                    TextFormField(
                      controller: discountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'مبلغ التخفيض (لكل ليلة)',
                        prefixIcon: Icon(Icons.discount),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: discountStartDateController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'تاريخ بدء التخفيض',
                        prefixIcon: Icon(Icons.calendar_today),
                        hintText: 'اضغط لاختيار التاريخ',
                        border: OutlineInputBorder(),
                      ),
                      onTap: () => _pickDate(discountStartDateController),
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
}
