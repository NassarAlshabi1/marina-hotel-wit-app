import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/providers.dart';
import '../../services/local_db.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';

class GuestEditScreen extends ConsumerStatefulWidget {
  const GuestEditScreen({super.key, required this.booking});
  final Booking booking;
  
  @override
  ConsumerState<GuestEditScreen> createState() => _GuestEditScreenState();
}

class _GuestEditScreenState extends ConsumerState<GuestEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _guestName = TextEditingController();
  final _guestPhone = TextEditingController();
  final _guestNationality = TextEditingController();
  final _guestAddress = TextEditingController();
  final _guestIdNumber = TextEditingController();
  final _idNumberFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9]'));
  final _guestIdIssueDate = TextEditingController();
  final _guestIdIssuePlace = TextEditingController();
  final _roomNumber = TextEditingController();
  final _checkin = TextEditingController();
  final _checkout = TextEditingController();
  final _expectedNights = TextEditingController();
  final _notes = TextEditingController();

  String _status = 'محجوزة';
  String _idType = 'بطاقة شخصية';
  String _oldRoomNumber = '';
  bool _roomChanged = false;
  
  static const _idTypes = ['بطاقة شخصية', 'جواز سفر', 'رخصة قيادة', 'بطاقة عسكرية', 'استبيان', 'شهادة ميلاد'];
  static const _statusOptions = ['محجوزة', 'شاغرة', 'مكتمل', 'ملغي'];

  @override
  void initState() {
    super.initState();
    final b = widget.booking;
    _guestName.text = b.guestName;
    _guestPhone.text = b.guestPhone;
    _guestNationality.text = b.guestNationality.isEmpty ? 'يمني' : b.guestNationality;
    _guestAddress.text = b.guestAddress ?? '';
    _guestIdNumber.text = b.guestIdNumber;
    _guestIdIssueDate.text = b.guestIdIssueDate ?? '';
    _guestIdIssuePlace.text = b.guestIdIssuePlace ?? '';
    _roomNumber.text = b.roomNumber;
    _oldRoomNumber = b.roomNumber;
    _checkin.text = b.checkinDate;
    _checkout.text = b.checkoutDate ?? '';
    _expectedNights.text = b.expectedNights.toString();
    _notes.text = b.notes ?? '';
    _status = b.status;
    _idType = b.guestIdType;
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _recalculateExpectedNights());
  }

  @override
  void dispose() {
    _guestName.dispose();
    _guestPhone.dispose();
    _guestNationality.dispose();
    _guestAddress.dispose();
    _guestIdNumber.dispose();
    _guestIdIssueDate.dispose();
    _guestIdIssuePlace.dispose();
    _roomNumber.dispose();
    _checkin.dispose();
    _checkout.dispose();
    _expectedNights.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(roomsListProvider);
    
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تعديل بيانات النزيل'),
          actions: [
            if (_status == 'مكتمل')
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                    SizedBox(width: 4),
                    Text('حجز مكتمل', style: TextStyle(fontSize: 12, color: Colors.orange)),
                  ],
                ),
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_status == 'مكتمل')
                Card(
                  color: Colors.orange.shade50,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'تحذير: هذا الحجز مكتمل. أي تعديلات قد تؤثر على البيانات المالية والتقارير.',
                            style: TextStyle(fontSize: 13, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_status == 'مكتمل') const SizedBox(height: 12),
              
              _buildSectionTitle('بيانات النزيل'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _guestName,
                        decoration: const InputDecoration(labelText: 'اسم النزيل *'),
                        validator: _req,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _guestPhone,
                        decoration: const InputDecoration(labelText: 'رقم الهاتف *'),
                        keyboardType: TextInputType.phone,
                        validator: _req,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _idType,
                        items: _idTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                        onChanged: (value) => setState(() => _idType = value ?? _idType),
                        decoration: const InputDecoration(labelText: 'نوع الهوية'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _guestIdNumber,
                        decoration: const InputDecoration(labelText: 'رقم الهوية'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [_idNumberFormatter],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _guestIdIssueDate,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'تاريخ إصدار الهوية',
                                suffixIcon: Icon(Icons.calendar_today),
                              ),
                              onTap: () => _pickDate(_guestIdIssueDate, onlyDate: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _guestIdIssuePlace,
                              decoration: const InputDecoration(labelText: 'جهة الإصدار'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _guestNationality,
                        decoration: const InputDecoration(labelText: 'الجنسية *'),
                        validator: _req,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _guestAddress,
                        decoration: const InputDecoration(labelText: 'العنوان'),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              _buildSectionTitle('تفاصيل الحجز'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildRoomSelector(roomsAsync),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _checkin,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'تاريخ الوصول *',
                          helperText: 'التنسيق: YYYY-MM-DD HH:MM:SS',
                          suffixIcon: Icon(Icons.event_available),
                        ),
                        validator: _req,
                        onTap: () => _pickDate(_checkin),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _checkout,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'تاريخ المغادرة المخطط',
                          helperText: 'التنسيق: YYYY-MM-DD HH:MM:SS',
                          suffixIcon: Icon(Icons.event_busy),
                        ),
                        onTap: () => _pickDate(_checkout),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _expectedNights,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'عدد الليالي المتوقع *'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'مطلوب';
                          final value = int.tryParse(v.trim());
                          if (value == null || value < 1) return 'عدد الليالي غير صحيح';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _status,
                        items: _statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (value) => setState(() => _status = value ?? _status),
                        decoration: const InputDecoration(labelText: 'حالة الحجز'),
                      ),
                      if (widget.booking.actualCheckout != null) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: widget.booking.actualCheckout,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'تاريخ المغادرة الفعلي',
                            suffixIcon: Icon(Icons.lock_clock),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              _buildSectionTitle('ملاحظات الحجز'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextFormField(
                    controller: _notes,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'ملاحظات إضافية'),
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saveChanges,
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

  Future<void> _pickDate(TextEditingController controller, {bool onlyDate = false}) async {
    final initial = _parseDateTime(controller.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    if (onlyDate) {
      controller.text = _formatDateTime(DateTime(date.year, date.month, date.day, 0, 0, 0)).substring(0, 10);
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final selected = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      controller.text = _formatDateTime(selected);
    });
    if (controller == _checkout || controller == _checkin) {
      _recalculateExpectedNights();
    }
  }

  void _recalculateExpectedNights() {
    final checkinDt = _parseDateTime(_checkin.text.trim());
    if (checkinDt == null) return;
    final checkoutDt = _parseDateTime(_checkout.text.trim());
    final nights = Time.nightsWithCutoff(checkinDt, checkout: checkoutDt);
    setState(() {
      _expectedNights.text = nights.toString();
    });
  }

  Widget _buildRoomSelector(AsyncValue<List<Room>> roomsAsync) {
    return roomsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      ),
      error: (err, stack) => TextFormField(
        controller: _roomNumber,
        readOnly: true,
        decoration: const InputDecoration(
          labelText: 'رقم الغرفة *',
          helperText: 'تعذر تحميل قائمة الغرف',
        ),
        validator: _req,
      ),
      data: (rooms) {
        final availableRooms = rooms.where((room) => 
          StatusUtils.isRoomAvailable(room.status) || room.roomNumber == _oldRoomNumber
        ).toList()
          ..sort((a, b) => a.roomNumber.compareTo(b.roomNumber));

        final currentValue = _roomNumber.text.trim();
        final items = <DropdownMenuItem<String>>[];
        
        if (currentValue.isNotEmpty && !availableRooms.any((room) => room.roomNumber == currentValue)) {
          items.add(DropdownMenuItem(value: currentValue, child: Text('$currentValue (الحالي)')));
        }
        
        items.addAll(
          availableRooms.map((room) => DropdownMenuItem(
                value: room.roomNumber,
                child: Text('${room.roomNumber} • ${room.type} • ${room.price} ر.س'),
              )),
        );

        if (items.isEmpty) {
          return TextFormField(
            controller: _roomNumber,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'رقم الغرفة *',
              helperText: 'لا توجد غرف شاغرة متاحة حالياً',
            ),
            validator: _req,
          );
        }

        return DropdownButtonFormField<String>(
          value: currentValue.isNotEmpty ? currentValue : null,
          items: items,
          onChanged: (value) {
            setState(() {
              _roomNumber.text = value ?? '';
              _roomChanged = (value != _oldRoomNumber);
            });
          },
          decoration: InputDecoration(
            labelText: 'رقم الغرفة *',
            helperText: _roomChanged 
              ? 'تحذير: سيتم تحديث البيانات المالية تلقائياً' 
              : null,
            helperStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          ),
          validator: (value) => value == null || value.trim().isEmpty ? 'مطلوب' : null,
        );
      },
    );
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final newRoomNumber = _roomNumber.text.trim();
    
    // إذا تم تغيير الغرفة، اعرض تأكيد
    if (_roomChanged && newRoomNumber != _oldRoomNumber) {
      final confirmed = await _showRoomChangeConfirmation();
      if (!confirmed) return;
    }

    // التحقق من توفر الغرفة الجديدة
    if (_roomChanged && newRoomNumber != _oldRoomNumber) {
      final roomsRepo = ref.read(roomsRepoProvider);
      final db = ref.read(databaseProvider);
      
      final newRoom = await (db.select(db.rooms)
        ..where((r) => r.roomNumber.equals(newRoomNumber))
        ..where((r) => r.deletedAt.isNull())
      ).getSingleOrNull();
      
      if (newRoom != null && !StatusUtils.isRoomAvailable(newRoom.status)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('الغرفة المختارة غير متاحة حالياً'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    try {
      await _updateGuestData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث بيانات النزيل بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ التعديلات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _showRoomChangeConfirmation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('تأكيد تغيير الغرفة'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('سيتم تغيير الغرفة من "${_oldRoomNumber}" إلى "${_roomNumber.text.trim()}"'),
              const SizedBox(height: 12),
              const Text('سيتم تحديث:'),
              const SizedBox(height: 8),
              const Text('• بيانات الحجز', style: TextStyle(fontSize: 13)),
              const Text('• جميع المدفوعات المرتبطة', style: TextStyle(fontSize: 13)),
              const Text('• حالة الغرفة القديمة (شاغرة)', style: TextStyle(fontSize: 13)),
              const Text('• حالة الغرفة الجديدة (محجوزة)', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Text(
                  'تحذير: هذا الإجراء سيؤثر على جميع البيانات المالية المرتبطة بهذا الحجز',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('تأكيد التغيير'),
            ),
          ],
        ),
      ),
    );
    
    return result ?? false;
  }

  Future<void> _updateGuestData() async {
    final bookingsRepo = ref.read(bookingsRepoProvider);
    final paymentsRepo = ref.read(paymentsRepoProvider);
    final roomsRepo = ref.read(roomsRepoProvider);
    final db = ref.read(databaseProvider);
    
    final name = _guestName.text.trim();
    final phone = _normalizePhone(_guestPhone.text);
    final nationality = _guestNationality.text.trim().isEmpty ? 'غير معروف' : _guestNationality.text.trim();
    final address = _optionalText(_guestAddress.text);
    final idNumber = _guestIdNumber.text.trim();
    final idIssueDate = _optionalText(_guestIdIssueDate.text);
    final idIssuePlace = _optionalText(_guestIdIssuePlace.text);
    final newRoomNumber = _roomNumber.text.trim();
    final checkin = _checkin.text.trim();
    final checkout = _optionalText(_checkout.text);
    final expectedNights = int.tryParse(_expectedNights.text.trim()) ?? 1;
    final notes = _optionalText(_notes.text);

    // حساب الليالي
    final checkinDt = _parseDateTime(checkin);
    final checkoutDt = checkout != null ? _parseDateTime(checkout) : null;
    final calculatedNights = checkinDt == null
        ? expectedNights
        : Time.nightsWithCutoff(checkinDt, checkout: checkoutDt);

    // 1. تحديث بيانات الحجز
    await bookingsRepo.update(
      widget.booking.id,
      roomNumber: newRoomNumber,
      guestName: name,
      guestPhone: phone,
      guestIdType: _idType,
      guestIdNumber: idNumber,
      guestIdIssueDate: idIssueDate,
      guestIdIssuePlace: idIssuePlace,
      guestNationality: nationality,
      guestAddress: address,
      checkinDate: checkin,
      checkoutDate: checkout,
      status: _status,
      notes: notes,
      expectedNights: expectedNights,
      calculatedNights: calculatedNights,
    );

    // 2. إذا تم تغيير الغرفة، قم بتحديث المدفوعات وحالة الغرف
    if (_roomChanged && newRoomNumber != _oldRoomNumber) {
      await _handleRoomChange(newRoomNumber);
    } else {
      // حتى لو لم يتم تغيير الغرفة، قم بتحديث حالة الغرف بناءً على الحالة
      await _refreshRoomOccupancy();
    }
  }

  Future<void> _handleRoomChange(String newRoomNumber) async {
    final paymentsRepo = ref.read(paymentsRepoProvider);
    final roomsRepo = ref.read(roomsRepoProvider);
    final db = ref.read(databaseProvider);

    // 1. تحديث جميع المدفوعات المرتبطة بهذا الحجز
    final payments = await (db.select(db.payments)
      ..where((p) => p.bookingLocalId.equals(widget.booking.id))
      ..where((p) => p.deletedAt.isNull())
    ).get();
    
    for (final payment in payments) {
      await paymentsRepo.update(
        payment.id,
        roomNumber: newRoomNumber,
      );
    }

    // 2. تحديث حالة الغرف
    await _refreshRoomOccupancy();
  }

  Future<void> _refreshRoomOccupancy() async {
    final roomsRepo = ref.read(roomsRepoProvider);
    final db = ref.read(databaseProvider);
    
    // جلب جميع الحجوزات النشطة
    final bookings = await (db.select(db.bookings)
      ..where((tbl) => tbl.deletedAt.isNull())
    ).get();
    
    final occupiedRooms = <String>{};
    for (final booking in bookings) {
      if (StatusUtils.isActiveBooking(booking.status)) {
        occupiedRooms.add(booking.roomNumber);
      }
    }

    // تحديث الغرفة القديمة (إذا تم تغيير الغرفة)
    if (_roomChanged && _oldRoomNumber.isNotEmpty) {
      final shouldOldBeOccupied = occupiedRooms.contains(_oldRoomNumber);
      if (!shouldOldBeOccupied) {
        await roomsRepo.updateByRoomNumber(_oldRoomNumber, status: 'شاغرة');
      }
    }

    // تحديث الغرفة الجديدة
    final newRoomNumber = _roomNumber.text.trim();
    if (StatusUtils.isActiveBooking(_status)) {
      await roomsRepo.updateByRoomNumber(newRoomNumber, status: 'محجوزة');
    } else {
      final shouldNewBeOccupied = occupiedRooms.contains(newRoomNumber);
      if (!shouldNewBeOccupied) {
        await roomsRepo.updateByRoomNumber(newRoomNumber, status: 'شاغرة');
      }
    }
  }

  DateTime? _parseDateTime(String value) {
    if (value.isEmpty) return null;
    final normalized = value.contains('T') ? value : value.replaceAll(' ', 'T');
    final withSeconds = normalized.length == 16 ? '${normalized}:00' : normalized;
    try {
      return DateTime.parse(withSeconds);
    } catch (_) {
      return null;
    }
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }

  String _normalizePhone(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return value.trim();
    }
    var normalized = digitsOnly;
    if (normalized.startsWith('00') && normalized.length > 2) {
      normalized = normalized.substring(2);
    }
    if (normalized.startsWith('0') && normalized.length == 10) {
      normalized = normalized.substring(1);
    }
    if (normalized.startsWith('967')) {
      return normalized;
    }
    return '967$normalized';
  }

  String? _optionalText(String text) => text.trim().isEmpty ? null : text.trim();
  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null;
}
