import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/local_db.dart';
import '../../utils/time.dart';
import '../../utils/status_utils.dart';

class RunawayGuestFlowScreen extends ConsumerStatefulWidget {
  const RunawayGuestFlowScreen({super.key});

  @override
  ConsumerState<RunawayGuestFlowScreen> createState() => _RunawayGuestFlowScreenState();
}

class _RunawayGuestFlowScreenState extends ConsumerState<RunawayGuestFlowScreen> {
  Booking? _selectedBooking;
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _guaranteeCtrl = TextEditingController();
  final List<String> _guarantees = [];
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    final bookingsRepo = ref.watch(bookingsRepoProvider);
    return AppScaffold(
      title: 'تسجيل هروب نزيل',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder<List<Booking>>(
              stream: bookingsRepo.watchList(status: null),
              builder: (context, snap) {
                final list = (snap.data ?? const <Booking>[]) 
                    .where((b) => StatusUtils.isBookingActive(b))
                    .toList();
                return DropdownButtonFormField<Booking>(
                  value: _selectedBooking != null && list.any((b) => b.id == _selectedBooking!.id) ? _selectedBooking : null,
                  items: list.map((b) => DropdownMenuItem(
                    value: b,
                    child: Text('${b.roomNumber} - ${b.guestName}'),
                  )).toList(),
                  onChanged: (b) => setState(() => _selectedBooking = b),
                  decoration: const InputDecoration(
                    labelText: 'اختر الحجز',
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ المتبقي',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _guaranteeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'إضافة رهن (بطاقة/هوية/متعلقات)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final v = _guaranteeCtrl.text.trim();
                    if (v.isEmpty) return;
                    setState(() {
                      _guarantees.add(v);
                      _guaranteeCtrl.clear();
                    });
                  },
                  child: const Text('إضافة'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _guarantees.map((g) => Chip(
                label: Text(g),
                onDeleted: () => setState(() => _guarantees.remove(g)),
              )).toList(),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _processing ? null : _submit,
                icon: const Icon(Icons.warning_amber),
                label: const Text('تسجيل هروب وإقفال الحجز'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_selectedBooking == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار الحجز')));
      return;
    }
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال مبلغ متبقي صحيح')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد تسجيل الهروب'),
          content: Text('سيتم إقفال الحجز وتسجيل دين بمبلغ ${amount.toStringAsFixed(2)} وإبقاء ${_guarantees.length} رهون.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _processing = true);
    try {
      final repo = ref.read(debtsRepoProvider);
      await repo.processEvasiveGuestDebt(
        bookingLocalId: _selectedBooking!.id,
        amountDue: amount,
        guaranteeItems: _guarantees,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل الهروب وإنشاء الدين')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التنفيذ: $e')));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }
}
