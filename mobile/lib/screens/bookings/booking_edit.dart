import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/providers.dart';
import '../../services/local_db.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';

class BookingEditScreen extends ConsumerStatefulWidget {
  const BookingEditScreen({super.key, this.existing});
  final Booking? existing;
  @override
  ConsumerState<BookingEditScreen> createState() => _BookingEditScreenState();
}

class _BookingEditScreenState extends ConsumerState<BookingEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _guestName = TextEditingController();
  final _guestPhone = TextEditingController();
  final _guestNationality = TextEditingController(text: 'يمني');
  final _guestAddress = TextEditingController();
  final _guestIdNumber = TextEditingController();
  final _guestIdIssueDate = TextEditingController();
  final _guestIdIssuePlace = TextEditingController();
  final _roomNumber = TextEditingController();
  final _checkin = TextEditingController();
  final _checkout = TextEditingController();
  final _expectedNights = TextEditingController(text: '1');
  final _notes = TextEditingController();

  String _status = 'محجوزة';
  String _idType = 'بطاقة شخصية';
  bool _roomInitialized = false;

  static const _idTypes = ['بطاقة شخصية', 'رخصة قيادة', 'جواز سفر'];
  static const _statusOptions = ['محجوزة', 'شاغرة', 'مكتمل', 'ملغي'];

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _guestName.text = b.guestName;
      _guestPhone.text = b.guestPhone;
      _guestNationality.text = b.guestNationality.isEmpty ? 'يمني' : b.guestNationality;
      _guestAddress.text = b.guestAddress ?? '';
      _guestIdNumber.text = b.guestIdNumber;
      _guestIdIssueDate.text = b.guestIdIssueDate ?? '';
      _guestIdIssuePlace.text = b.guestIdIssuePlace ?? '';
      _roomNumber.text = b.roomNumber;
      _checkin.text = b.checkinDate;
      _checkout.text = b.checkoutDate ?? '';
      _expectedNights.text = b.expectedNights.toString();
      _notes.text = b.notes ?? '';
      _status = b.status;
      _idType = b.guestIdType;
      _roomInitialized = true;
    } else {
      _checkin.text = _formatDateTime(DateTime.now());
    }
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
    final repo = ref.watch(bookingsRepoProvider);
    final roomsAsync = ref.watch(roomsListProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.existing == null ? 'إضافة حجز' : 'تعديل حجز')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                        onChanged: (_) => _recalculateExpectedNights(),
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
                      if (widget.existing?.actualCheckout != null) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: widget.existing?.actualCheckout,
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
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  final name = _guestName.text.trim();
                  final phone = _normalizePhone(_guestPhone.text);
                  final nationality = _guestNationality.text.trim().isEmpty ? 'غير معروف' : _guestNationality.text.trim();
                  final address = _optionalText(_guestAddress.text);
                  final idNumber = _guestIdNumber.text.trim();
                  final idIssueDate = _optionalText(_guestIdIssueDate.text);
                  final idIssuePlace = _optionalText(_guestIdIssuePlace.text);
                  final roomNumber = _roomNumber.text.trim();
                  final checkin = _checkin.text.trim();
                  final checkout = _optionalText(_checkout.text);
                  final expectedNights = int.tryParse(_expectedNights.text.trim()) ?? 1;
                  final checkinDt = _parseDateTime(checkin);
                  final checkoutDt = checkout != null ? _parseDateTime(checkout) : null;
                  final calculatedNights = checkinDt == null
                      ? expectedNights
                      : Time.nightsWithCutoff(checkinDt, checkout: checkoutDt);
                  final notes = _optionalText(_notes.text);
                  const String? email = null;

                  if (widget.existing == null) {
                    await repo.create(
                      roomNumber: roomNumber,
                      guestName: name,
                      guestPhone: phone,
                      guestIdType: _idType,
                      guestIdNumber: idNumber,
                      guestIdIssueDate: idIssueDate,
                      guestIdIssuePlace: idIssuePlace,
                      guestNationality: nationality,
                      guestEmail: email,
                      guestAddress: address,
                      checkinDate: checkin,
                      checkoutDate: checkout,
                      actualCheckout: null,
                      status: _status,
                      notes: notes,
                      expectedNights: expectedNights,
                      calculatedNights: calculatedNights,
                    );
                  } else {
                    await repo.update(
                      widget.existing!.id,
                      roomNumber: roomNumber,
                      guestName: name,
                      guestPhone: phone,
                      guestIdType: _idType,
                      guestIdNumber: idNumber,
                      guestIdIssueDate: idIssueDate,
                      guestIdIssuePlace: idIssuePlace,
                      guestNationality: nationality,
                      guestEmail: email,
                      guestAddress: address,
                      checkinDate: checkin,
                      checkoutDate: checkout,
                      status: _status,
                      notes: notes,
                      expectedNights: expectedNights,
                      calculatedNights: calculatedNights,
                    );
                  }

                  await _refreshRoomOccupancy(ref);

                  if (mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.save),
                label: const Text('حفظ الحجز'),
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
          helperText: 'تعذر تحميل قائمة الغرف، أدخل الرقم يدوياً',
        ),
        validator: _req,
      ),
      data: (rooms) {
        final availableRooms = rooms.where((room) => StatusUtils.isRoomAvailable(room.status)).toList()
          ..sort((a, b) => a.roomNumber.compareTo(b.roomNumber));

        final currentValue = _roomNumber.text.trim();
        if (!_roomInitialized && widget.existing == null && availableRooms.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _roomNumber.text = availableRooms.first.roomNumber;
                _roomInitialized = true;
              });
            }
          });
        } else if (!_roomInitialized && widget.existing != null) {
          _roomInitialized = true;
        }

        final items = <DropdownMenuItem<String>>[];
        if (currentValue.isNotEmpty && !availableRooms.any((room) => room.roomNumber == currentValue)) {
          items.add(DropdownMenuItem(value: currentValue, child: Text('$currentValue (الحالي)')));
        }
        items.addAll(
          availableRooms.map((room) => DropdownMenuItem(
                value: room.roomNumber,
                child: Text('${room.roomNumber} • ${room.type}'),
              )),
        );

        if (items.isEmpty) {
          return TextFormField(
            controller: _roomNumber,
            readOnly: widget.existing == null,
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
            });
          },
          decoration: const InputDecoration(labelText: 'رقم الغرفة *'),
          validator: (value) => value == null || value.trim().isEmpty ? 'مطلوب' : null,
        );
      },
    );
  }

  Future<void> _refreshRoomOccupancy(WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final roomsRepo = ref.read(roomsRepoProvider);
    final bookings = await (db.select(db.bookings)..where((tbl) => tbl.deletedAt.isNull())).get();
    final occupiedRooms = <String>{};
    for (final booking in bookings) {
      if (StatusUtils.isActiveBooking(booking.status)) {
        occupiedRooms.add(booking.roomNumber);
      }
    }

    final rooms = await (db.select(db.rooms)..where((tbl) => tbl.deletedAt.isNull())).get();
    for (final room in rooms) {
      final shouldBeOccupied = occupiedRooms.contains(room.roomNumber);
      final isCurrentlyOccupied = StatusUtils.isRoomOccupied(room.status);
      final isCurrentlyAvailable = StatusUtils.isRoomAvailable(room.status);
      final target = StatusUtils.roomStatusForOccupancy(shouldBeOccupied);
      if (shouldBeOccupied && !isCurrentlyOccupied) {
        await roomsRepo.updateByRoomNumber(room.roomNumber, status: target);
      } else if (!shouldBeOccupied && !isCurrentlyAvailable) {
        await roomsRepo.updateByRoomNumber(room.roomNumber, status: target);
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
