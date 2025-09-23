import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as d;
import 'package:uuid/uuid.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/local_db.dart';

class BookingEditScreen extends ConsumerStatefulWidget {
  const BookingEditScreen({super.key, this.existing});
  final BookingsData? existing;
  @override
  ConsumerState<BookingEditScreen> createState() => _BookingEditScreenState();
}

class _BookingEditScreenState extends ConsumerState<BookingEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _guestName = TextEditingController();
  final _guestPhone = TextEditingController();
  final _roomNumber = TextEditingController();
  final _checkin = TextEditingController();
  final _checkout = TextEditingController();
  String _status = 'محجوزة';

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _guestName.text = b.guestName;
      _guestPhone.text = b.guestPhone ?? '';
      _roomNumber.text = b.roomNumber;
      _checkin.text = b.checkinDate;
      _checkout.text = b.checkoutDate ?? '';
      _status = b.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(coreProviders.dbProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.existing == null ? 'إضافة حجز' : 'تعديل حجز')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(controller: _guestName, decoration: const InputDecoration(labelText: 'اسم النزيل'), validator: _req),
              TextFormField(controller: _guestPhone, decoration: const InputDecoration(labelText: 'هاتف')),
              TextFormField(controller: _roomNumber, decoration: const InputDecoration(labelText: 'رقم الغرفة'), validator: _req),
              TextFormField(controller: _checkin, decoration: const InputDecoration(labelText: 'تاريخ الدخول YYYY-MM-DD HH:MM:SS'), validator: _req),
              TextFormField(controller: _checkout, decoration: const InputDecoration(labelText: 'تاريخ الخروج (اختياري) YYYY-MM-DD HH:MM:SS')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _status,
                items: const [DropdownMenuItem(value: 'محجوزة', child: Text('محجوزة')), DropdownMenuItem(value: 'شاغرة', child: Text('شاغرة'))],
                onChanged: (v) => setState(() => _status = v ?? _status),
                decoration: const InputDecoration(labelText: 'الحالة'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
                  final uuid = const Uuid().v4();
                  final comp = BookingsCompanion(
                    localUuid: d.Value(uuid),
                    serverId: d.Value(widget.existing?.serverId),
                    lastModified: d.Value(now),
                    deletedAt: const d.Value(null),
                    version: const d.Value(1),
                    origin: const d.Value('local'),
                    bookingId: d.Value(widget.existing?.bookingId),
                    guestName: d.Value(_guestName.text.trim()),
                    guestPhone: d.Value(_guestPhone.text.trim()),
                    roomNumber: d.Value(_roomNumber.text.trim()),
                    checkinDate: d.Value(_checkin.text.trim()),
                    checkoutDate: d.Value(_checkout.text.trim().isEmpty ? null : _checkout.text.trim()),
                    status: d.Value(_status),
                  );

                  if (widget.existing == null) {
                    await db.into(db.bookings).insert(comp);
                    await ref.read(coreProviders.syncProvider).queueChange(
                          entity: 'bookings',
                          op: 'create',
                          localUuid: uuid,
                          data: {
                            'guest_name': _guestName.text.trim(),
                            'guest_phone': _guestPhone.text.trim(),
                            'room_number': _roomNumber.text.trim(),
                            'checkin_date': _checkin.text.trim(),
                            'checkout_date': _checkout.text.trim().isEmpty ? null : _checkout.text.trim(),
                            'status': _status,
                          },
                        );
                  } else {
                    await (db.update(db.bookings)..where((t) => t.localUuid.equals(widget.existing!.localUuid))).write(comp);
                    await ref.read(coreProviders.syncProvider).queueChange(
                          entity: 'bookings',
                          op: 'update',
                          localUuid: widget.existing!.localUuid,
                          data: {
                            'booking_id': widget.existing!.bookingId,
                            'guest_name': _guestName.text.trim(),
                            'guest_phone': _guestPhone.text.trim(),
                            'room_number': _roomNumber.text.trim(),
                            'checkin_date': _checkin.text.trim(),
                            'checkout_date': _checkout.text.trim().isEmpty ? null : _checkout.text.trim(),
                            'status': _status,
                          },
                        );
                  }

                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('حفظ'),
              )
            ],
          ),
        ),
      ),
    );
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null;
}
