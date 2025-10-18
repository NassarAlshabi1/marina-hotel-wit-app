import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../services/local_db.dart';
import '../../services/providers.dart';
import '../../services/sync_service.dart';
import '../../utils/time.dart';
import '../payments/booking_payment_screen.dart';
import 'booking_edit.dart';
import '../payments/payments_main_screen.dart';

class BookingsListScreen extends ConsumerStatefulWidget {
  const BookingsListScreen({super.key});

  @override
  ConsumerState<BookingsListScreen> createState() => _BookingsListScreenState();
}

class _BookingsListScreenState extends ConsumerState<BookingsListScreen> {
  final _currencyFmt = NumberFormat('#,##0.00', 'en_US');

  Future<void> _navigateToAddBooking() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BookingEditScreen(existing: null)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsListProvider);
    final roomsAsync = ref.watch(roomsListProvider);

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
          onPressed: _navigateToAddBooking,
          icon: const Icon(Icons.add),
          tooltip: 'حجز جديد',
        ),
      ],
      fab: FloatingActionButton(
        onPressed: _navigateToAddBooking,
        child: const Icon(Icons.add),
      ),
      body: bookingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e', style: const TextStyle(color: Colors.black))),
        data: (bookings) {
          final roomsList = roomsAsync.maybeWhen(data: (r) => r, orElse: () => <Room>[]);
          final roomsMap = {for (final r in roomsList) r.roomNumber: r};

          final filtered = bookings
              .where((b) {
                final status = b.status.toLowerCase();
                if (status == 'مكتمل' || status == 'completed' || status == 'غادر' || status == 'departed') {
                  return false;
                }
                return true;
              })
              .toList()
            ..sort((a, b) => b.checkinDate.compareTo(a.checkinDate));

          if (filtered.isEmpty) {
            return const EmptyState(
              title: 'لا توجد حجوزات',
              message: 'أضف حجزاً جديداً للبدء',
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
                  shrinkWrap: true,
                  itemCount: filtered.length + 1,
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
    );
  }
}

Widget _buildHeaderRow(BuildContext context) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
    child: Row(
      children: const [
        SizedBox(width: 40, child: Text('#', textAlign: TextAlign.center)),
        _HeaderCell('بيانات النزيل', flex: 2),
        _HeaderCell('الغرفة'),
        _HeaderCell('سعر الليلة'),
        _HeaderCell('الفترة', flex: 2),
        _HeaderCell('الليالي'),
        _HeaderCell('المدفوع'),
        _HeaderCell('المتبقي'),
        _HeaderCell('حالة الدفعة'),
        _HeaderCell('حالة الحجز'),
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
    final baseTextStyle = const TextStyle(color: Colors.black);
    final smallTextStyle = baseTextStyle.copyWith(fontSize: 12);
    final boldTextStyle = baseTextStyle.copyWith(fontWeight: FontWeight.w600);
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

        return InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BookingPaymentScreen(booking: booking)),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 40, child: Text(index.toString(), textAlign: TextAlign.center, style: baseTextStyle)),
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
                            style: boldTextStyle.copyWith(fontSize: 16),
                          ),
                          if (booking.guestPhone.isNotEmpty)
                            Text(booking.guestPhone, style: smallTextStyle),
                          const SizedBox(height: 2),
                          Text(
                            booking.guestIdNumber.isEmpty
                                ? booking.guestIdType
                                : '${booking.guestIdType} • ${booking.guestIdNumber}',
                            style: smallTextStyle,
                          ),
                          if (booking.guestNationality.isNotEmpty)
                            Text(booking.guestNationality, style: smallTextStyle),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(child: Center(child: Text(booking.roomNumber, style: baseTextStyle))),
                Expanded(
                  child: Center(
                    child: Text(
                      currencyFmt.format(pricePerNight),
                      style: baseTextStyle,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_formatDate(booking.checkinDate), style: baseTextStyle),
                        if (plannedText != null)
                          Text('حتى $plannedText', style: smallTextStyle),
                        if (actualText != null)
                          Text('خروج فعلي $actualText', style: smallTextStyle),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(nightsLabel, style: baseTextStyle),
                  ),
                ),
                Expanded(child: Center(child: Text(currencyFmt.format(paid), style: baseTextStyle))),
                Expanded(child: Center(child: Text(currencyFmt.format(remaining), style: baseTextStyle))),
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(statusText, style: baseTextStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ),
                Expanded(child: Center(child: _buildBookingStatusChip(booking.status, baseTextStyle))),
              ],
            ),
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
}

Widget _buildBookingStatusChip(String status, TextStyle baseTextStyle) {
  Color bg;
  String txt;
  switch (status.toLowerCase()) {
    case 'active':
    case 'محجوزة':
    case 'نشط':
      bg = Colors.green.shade100;
      txt = 'محجوزة';
      break;
    case 'completed':
    case 'مكتمل':
      bg = Colors.blue.shade100;
      txt = 'مكتمل';
      break;
    case 'cancelled':
    case 'ملغي':
      bg = Colors.red.shade100;
      txt = 'ملغي';
      break;
    default:
      bg = Colors.grey.shade100;
      txt = status;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
    child: Text(txt, style: baseTextStyle.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
  );
}
