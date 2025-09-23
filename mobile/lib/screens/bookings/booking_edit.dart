import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as d;
import 'package:uuid/uuid.dart';
import '../../services/providers.dart';

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
    final repo = ref.watch(bookingsRepoProvider);
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
                  if (widget.existing == null) {
                    await repo.create(
                      roomNumber: _roomNumber.text.trim(),
                      guestName: _guestName.text.trim(),
                      guestPhone: _guestPhone.text.trim(),
                      guestNationality: 'يمني',
                      guestEmail: null,
                      guestAddress: null,
                      checkinDate: _checkin.text.trim(),
                      checkoutDate: _checkout.text.trim().isEmpty ? null : _checkout.text.trim(),
                      status: _status,
                      notes: null,
                    );
                  } else {
                    await repo.update(
                      widget.existing!.id,
                      roomNumber: _roomNumber.text.trim(),
                      guestName: _guestName.text.trim(),
                      guestPhone: _guestPhone.text.trim(),
                      guestNationality: 'يمني',
                      guestEmail: null,
                      guestAddress: null,
                      checkinDate: _checkin.text.trim(),
                      checkoutDate: _checkout.text.trim().isEmpty ? null : _checkout.text.trim(),
                      status: _status,
                      notes: null,
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
