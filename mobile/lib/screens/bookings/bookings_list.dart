import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../utils/time.dart';
import '../../components/widgets/empty_state.dart';
import 'booking_edit.dart';
import '../payments/booking_payment_screen.dart';
import '../payments/booking_checkout_screen.dart';
import '../payments/payments_main_screen.dart';

class BookingsListScreen extends ConsumerStatefulWidget {
  const BookingsListScreen({super.key});
  @override
  ConsumerState<BookingsListScreen> createState() => _BookingsListScreenState();
}

class _BookingsListScreenState extends ConsumerState<BookingsListScreen> {
  bool _hideEnded = true;
  String _search = '';
  final _currencyFmt = NumberFormat.decimalPattern('ar');

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsListProvider);
    final roomsAsync = ref.watch(roomsListProvider);
    final activeNotes = ref.watch(activeNotesProvider);

    return AppScaffold(
      title: 'الحجوزات',
      actions: [
        IconButton(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentsMainScreen()));
          },
          icon: const Icon(Icons.payments),
          tooltip: 'إدارة المدفوعات',
        ),
        IconButton(
          onPressed: _showSearchDialog,
          icon: const Icon(Icons.search),
          tooltip: 'بحث',
        ),
        IconButton(
          onPressed: () => setState(() => _hideEnded = !_hideEnded),
          icon: Icon(_hideEnded ? Icons.visibility_off : Icons.visibility),
          tooltip: _hideEnded ? 'إخفاء المكتملة' : 'إظهار الكل',
        ),
        IconButton(
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingEditScreen()));
          },
          icon: const Icon(Icons.add),
          tooltip: 'حجز جديد',
        ),
      ],
      fab: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingEditScreen()));
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _ActiveAlertsBar(activeNotes),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: _buildFiltersSummary(),
          ),
          Expanded(
            child: bookingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (bookings) {
                final roomsList = roomsAsync.maybeWhen(data: (r) => r, orElse: () => <Room>[]);
                final roomsMap = {for (final r in roomsList) r.roomNumber: r};

                final query = _search.trim().toLowerCase();
                bool matches(String? source) => source != null && source.toLowerCase().contains(query);
                var filtered = bookings
                    .where((b) {
                      if (_hideEnded) {
                        final status = b.status.toLowerCase();
                        if (status == 'مكتمل' || status == 'completed' || status == 'غادر' || status == 'departed') {
                          return false;
                        }
                      }
                      if (query.isEmpty) return true;
                      return matches(b.guestName) ||
                          matches(b.guestPhone) ||
                          matches(b.roomNumber) ||
                          matches(b.guestIdNumber) ||
                          matches(b.guestNationality) ||
                          matches(b.guestEmail);
                    })
                    .toList();

                filtered.sort((a, b) => (b.checkinDate).compareTo(a.checkinDate));

                if (filtered.isEmpty) {
                  return const EmptyState(
                    title: 'لا توجد حجوزات',
                    message: 'استخدم البحث أو أضف حجزاً جديداً',
                    icon: Icons.hotel_outlined,
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(syncServiceProvider).runSync();
                  },
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 1100),
                      child: ListView.builder(
                        itemCount: filtered.length + 1,
                        shrinkWrap: true,
                        itemBuilder: (context, index) {
                          if (index == 0) return _buildHeaderRow(context);
                          final booking = filtered[index - 1];
                          final room = roomsMap[booking.roomNumber];
                          final checkin = DateTime.tryParse(booking.checkinDate);
                          final plannedCheckout = booking.checkoutDate != null ? DateTime.tryParse(booking.checkoutDate!) : null;
                          final actualCheckout = booking.actualCheckout != null ? DateTime.tryParse(booking.actualCheckout!) : null;
                          final price = room?.price ?? 0;
                          final expectedNights = booking.expectedNights > 0
                              ? booking.expectedNights
                              : (checkin == null ? 1 : Time.nightsWithCutoff(checkin, checkout: plannedCheckout));
                          final actualNights = checkin == null
                              ? expectedNights
                              : Time.nightsWithCutoff(checkin, checkout: actualCheckout ?? plannedCheckout);
                          final totalAmount = (expectedNights * price).toDouble();
                          return _BookingRow(
                            index: index,
                            booking: booking,
                            expectedNights: expectedNights,
                            actualNights: actualNights,
                            pricePerNight: price,
                            totalAmount: totalAmount,
                            currencyFmt: _currencyFmt,
                            plannedCheckout: plannedCheckout,
                            actualCheckout: actualCheckout,
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersSummary() {
    final chips = <Widget>[];
    if (_hideEnded) {
      chips.add(const Chip(label: Text('إخفاء المكتملة')));
    }
    if (_search.isNotEmpty) {
      chips.add(Chip(label: Text('بحث: $_search')));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, children: chips);
  }

  void _showSearchDialog() async {
    final controller = TextEditingController(text: _search);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('بحث في الحجوزات'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'اسم النزيل / الهاتف / رقم الغرفة',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تطبيق')),
          ],
        ),
      ),
    );
    if (ok == true) setState(() => _search = controller.text.trim());
  }
}

class _ActiveAlertsBar extends StatelessWidget {
  const _ActiveAlertsBar(this.activeNotes);
  final AsyncValue<List<BookingNote>> activeNotes;
  @override
  Widget build(BuildContext context) {
    return activeNotes.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (notes) {
        if (notes.isEmpty) return const SizedBox.shrink();
        final high = notes.where((n) => n.alertType == 'high').length;
        final med = notes.where((n) => n.alertType == 'medium').length;
        final low = notes.where((n) => n.alertType == 'low').length;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.orange.shade50, Colors.orange.shade100]),
            border: Border.all(color: Colors.orange.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.orange),
              const SizedBox(width: 8),
              const Text('تنبيهات نشطة'),
              const Spacer(),
              _badge('عالي', high, Colors.red),
              const SizedBox(width: 8),
              _badge('متوسط', med, Colors.orange),
              const SizedBox(width: 8),
              _badge('منخفض', low, Colors.green),
            ],
          ),
        );
      },
    );
  }

  Widget _badge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text('$label: $count', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

Widget _buildHeaderRow(BuildContext context) {
  final style = Theme.of(context).textTheme.labelMedium;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
    child: Row(
      children: const [
        SizedBox(width: 40, child: Text('#')),
        _HeaderCell('بيانات النزيل', flex: 2),
        _HeaderCell('الغرفة'),
        _HeaderCell('سعر الليلة'),
        _HeaderCell('الفترة', flex: 2),
        _HeaderCell('الليالي'),
        _HeaderCell('المدفوع'),
        _HeaderCell('المتبقي'),
        _HeaderCell('حالة الدفعة'),
        _HeaderCell('حالة الحجز'),
        _HeaderCell('تنبيهات'),
        SizedBox(width: 200, child: Text('عمليات')),
      ],
    ),
  );
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {this.flex = 1});
  final String text;
  final int flex;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text, textAlign: TextAlign.center),
    );
  }
}

class _BookingRow extends ConsumerWidget {
  const _BookingRow({
    required this.index,
    required this.booking,
    required this.expectedNights,
    required this.actualNights,
    required this.pricePerNight,
    required this.totalAmount,
    required this.currencyFmt,
    this.plannedCheckout,
    this.actualCheckout,
  });
  final int index;
  final Booking booking;
  final int expectedNights;
  final int actualNights;
  final double pricePerNight;
  final double totalAmount;
  final NumberFormat currencyFmt;
  final DateTime? plannedCheckout;
  final DateTime? actualCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsRepo = ref.watch(paymentsRepoProvider);
    final notesRepo = ref.watch(notesRepoProvider);
    final theme = Theme.of(context);
    final nightsLabel = actualNights != expectedNights
        ? '$expectedNights (${actualNights} فعلي)'
        : expectedNights.toString();
    final plannedText = plannedCheckout != null ? _formatDate(plannedCheckout!.toIso8601String()) : null;
    final actualText = actualCheckout != null ? _formatDate(actualCheckout!.toIso8601String()) : null;
    final guestTooltipLines = [
      'الاسم: ${booking.guestName}',
      if (booking.guestPhone.isNotEmpty) 'الهاتف: ${booking.guestPhone}',
      if (booking.guestIdNumber.isNotEmpty) 'الهوية: ${booking.guestIdType} ${booking.guestIdNumber}',
      if (booking.guestNationality.isNotEmpty) 'الجنسية: ${booking.guestNationality}',
      if (booking.guestEmail != null && booking.guestEmail!.isNotEmpty) 'البريد: ${booking.guestEmail}',
      if (booking.guestAddress != null && booking.guestAddress!.isNotEmpty) 'العنوان: ${booking.guestAddress}',
    ];
    final guestTooltip = guestTooltipLines.join('\n');

    return StreamBuilder<List<Payment>>(
      stream: paymentsRepo.paymentsByBooking(booking.id),
      builder: (context, snapshot) {
        final paid = snapshot.hasData ? snapshot.data!.fold<double>(0, (s, p) => s + p.amount) : 0.0;
        final remaining = (totalAmount - paid).clamp(0, totalAmount);
        final Color statusColor = remaining <= 0
            ? Colors.green
            : (paid > 0 ? Colors.orange : Colors.red);
        final String statusText = remaining <= 0
            ? 'مسددة'
            : (paid > 0 ? 'جزئياً' : 'غير مسددة');

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0)))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 40, child: Text(index.toString(), textAlign: TextAlign.center)),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Tooltip(
                    message: guestTooltip,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          booking.guestName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (booking.guestPhone.isNotEmpty)
                          Text(booking.guestPhone, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 2),
                        Text(
                          booking.guestIdNumber.isEmpty
                              ? booking.guestIdType
                              : '${booking.guestIdType} • ${booking.guestIdNumber}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        if (booking.guestNationality.isNotEmpty)
                          Text(
                            booking.guestNationality,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: Center(child: Text(booking.roomNumber))),
              Expanded(
                child: Center(
                  child: Text(currencyFmt.format(pricePerNight)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_formatDate(booking.checkinDate)),
                      if (plannedText != null)
                        Text('حتى $plannedText', style: theme.textTheme.bodySmall),
                      if (actualText != null)
                        Text(
                          'خروج فعلي $actualText',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade700),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(nightsLabel, style: theme.textTheme.bodyMedium),
                ),
              ),
              Expanded(child: Center(child: Text(currencyFmt.format(paid)))),
              Expanded(child: Center(child: Text(currencyFmt.format(remaining)))),
              Expanded(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ),
              Expanded(child: Center(child: _buildBookingStatusChip(context, booking.status))),
              SizedBox(
                width: 60,
                child: StreamBuilder<List<BookingNote>>(
                  stream: notesRepo.watchByBooking(booking.id),
                  builder: (context, notesSnap) {
                    final notes = notesSnap.data ?? const <BookingNote>[];
                    final active = notes.where((n) => n.isActive == 1).toList();
                    final count = active.length;
                    final hasHigh = active.any((n) => n.alertType == 'high');
                    final iconColor = hasHigh
                        ? Colors.red
                        : (count > 0 ? Colors.orange : theme.colorScheme.onSurfaceVariant);
                    return IconButton(
                      onPressed: () => _showNotesDialog(context, ref, booking),
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(Icons.notifications, color: iconColor),
                          if (count > 0)
                            Positioned(
                              right: -6,
                              top: -6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
                                child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10)),
                              ),
                            )
                        ],
                      ),
                      tooltip: 'التنبيهات',
                    );
                  },
                ),
              ),
              SizedBox(
                width: 200,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => BookingPaymentScreen(booking: booking)));
                        },
                        icon: const Icon(Icons.payment, size: 16),
                        label: const Text('دفع'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: remaining <= 0 && (booking.status == 'محجوزة' || booking.status.toLowerCase() == 'active')
                            ? () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => BookingCheckoutScreen(booking: booking)));
                              }
                            : null,
                        icon: const Icon(Icons.logout, size: 16),
                        label: const Text('خروج'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'تعديل',
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => BookingEditScreen(existing: booking)));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(String s) {
    try {
      final d = DateTime.parse(s);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return s;
    }
  }

  Widget _buildBookingStatusChip(BuildContext context, String status) {
    Color bg;
    Color fg;
    String txt;
    switch (status.toLowerCase()) {
      case 'active':
      case 'محجوزة':
      case 'نشط':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        txt = 'محجوزة';
        break;
      case 'completed':
      case 'مكتمل':
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade800;
        txt = 'مكتمل';
        break;
      case 'cancelled':
      case 'ملغي':
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
        txt = 'ملغي';
        break;
      default:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade800;
        txt = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Text(txt, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }

  void _showNotesDialog(BuildContext context, WidgetRef ref, Booking booking) {
    final notesRepo = ref.read(notesRepoProvider);
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StreamBuilder<List<BookingNote>>(
          stream: notesRepo.watchByBooking(booking.id),
          builder: (context, snap) {
            final items = snap.data ?? const <BookingNote>[];
            final controller = TextEditingController();
            String priority = 'low';
            return StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: Row(
                  children: [
                    const Icon(Icons.notifications),
                    const SizedBox(width: 8),
                    Text('تنبيهات ${booking.guestName}')
                  ],
                ),
                content: SizedBox(
                  width: 500,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('لا توجد تنبيهات'),
                          )
                        else
                          ...items.map((n) => ListTile(
                                leading: Icon(Icons.circle, color: _priorityColor(n.alertType), size: 12),
                                title: Text(n.noteText),
                                subtitle: Text(n.alertUntil ?? ''),
                                trailing: Switch(
                                  value: n.isActive == 1,
                                  onChanged: (v) => notesRepo.update(n.id, isActive: v),
                                ),
                              )),
                        const Divider(),
                        TextField(
                          controller: controller,
                          decoration: const InputDecoration(labelText: 'ملاحظة جديدة', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('الأولوية:'),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: priority,
                              items: const [
                                DropdownMenuItem(value: 'high', child: Text('عالي')),
                                DropdownMenuItem(value: 'medium', child: Text('متوسط')),
                                DropdownMenuItem(value: 'low', child: Text('منخفض')),
                              ],
                              onChanged: (v) => setState(() => priority = v ?? 'low'),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed: () async {
                                if (controller.text.trim().isEmpty) return;
                                await notesRepo.create(
                                  bookingId: booking.id,
                                  noteText: controller.text.trim(),
                                  alertType: priority,
                                  alertUntil: null,
                                  isActive: true,
                                );
                                controller.clear();
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('إضافة'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Color _priorityColor(String type) {
    switch (type) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }
}
