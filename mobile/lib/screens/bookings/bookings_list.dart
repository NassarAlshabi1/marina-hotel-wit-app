import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';
import '../payments/booking_payment_screen.dart';
import '../payments/payments_main_screen.dart';
import 'booking_edit.dart';

class BookingsListScreen extends ConsumerStatefulWidget {
  const BookingsListScreen({super.key});

  @override
  ConsumerState<BookingsListScreen> createState() => _BookingsListScreenState();
}

class _BookingsListScreenState extends ConsumerState<BookingsListScreen>
    with SyncOnExitMixin {
  @override
  String get screenId => 'bookings_list';
  final _currencyFmt = NumberFormat('#,##0', 'en_US');

  Future<void> _navigateToAddBooking() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const BookingEditScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsListProvider);
    final roomsAsync = ref.watch(roomsListProvider);

    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'الحجوزات',
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => const PaymentsMainScreen()),
              );
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
          error: (e, _) => Center(
            child: Text('خطأ: $e', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black)),
          ),
          data: (bookings) {
            final roomsList = roomsAsync.maybeWhen(
              data: (r) => r,
              orElse: () => <Room>[],
            );
            final roomsMap = {for (final r in roomsList) r.roomNumber: r};

            final filtered = bookings.where((b) {
              final status = b.status.toLowerCase();
              if (status == 'مكتمل' ||
                  status == 'completed' ||
                  status == 'غادر' ||
                  status == 'departed') {
                return false;
              }
              return true;
            }).toList()..sort((a, b) => b.checkinDate.compareTo(a.checkinDate));

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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  if (isWide) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 1100),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _buildHeaderRow(context);
                            }
                            final booking = filtered[index - 1];
                            final room = roomsMap[booking.roomNumber];
                            final checkin = DateTime.tryParse(
                              booking.checkinDate,
                            );
                            final plannedCheckout = booking.checkoutDate != null
                                ? DateTime.tryParse(booking.checkoutDate!)
                                : null;
                            final actualCheckout =
                                booking.actualCheckout != null
                                ? DateTime.tryParse(booking.actualCheckout!)
                                : null;
                            final price = room?.price ?? 0;
                            // إذا لم يُسجَّل خروج → احتساب ديناميكي من الآن
                            final hasNoCheckout = plannedCheckout == null &&
                                actualCheckout == null;
                            final dynamicNights =
                                hasNoCheckout && checkin != null
                                    ? Time.nightsWithCutoff(checkin)
                                    : null;
                            final expectedNights = dynamicNights ??
                                (booking.expectedNights > 0
                                    ? booking.expectedNights
                                    : (checkin == null
                                          ? 1
                                          : Time.nightsWithCutoff(
                                              checkin,
                                              checkout: plannedCheckout,
                                            )));
                            final actualNights = dynamicNights ??
                                (checkin == null
                                    ? expectedNights
                                    : Time.nightsWithCutoff(
                                        checkin,
                                        checkout:
                                            actualCheckout ?? plannedCheckout,
                                      ));
                            final totalAmount = actualNights * price
                                ;
                            return RepaintBoundary(
                              child: _BookingRow(
                                index: index,
                                booking: booking,
                                expectedNights: expectedNights,
                                actualNights: actualNights,
                                pricePerNight: price,
                                totalAmount: totalAmount,
                                currencyFmt: _currencyFmt,
                                plannedCheckout: plannedCheckout,
                                actualCheckout: actualCheckout,
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final booking = filtered[index];
                      final room = roomsMap[booking.roomNumber];
                      final checkin = DateTime.tryParse(booking.checkinDate);
                      final plannedCheckout = booking.checkoutDate != null
                          ? DateTime.tryParse(booking.checkoutDate!)
                          : null;
                      final actualCheckout = booking.actualCheckout != null
                          ? DateTime.tryParse(booking.actualCheckout!)
                          : null;
                      final price = room?.price ?? 0;
                      // إذا لم يُسجَّل خروج → احتساب ديناميكي من الآن
                      final hasNoCheckout = plannedCheckout == null &&
                          actualCheckout == null;
                      final dynamicNights =
                          hasNoCheckout && checkin != null
                              ? Time.nightsWithCutoff(checkin)
                              : null;
                      final expectedNights = dynamicNights ??
                          (booking.expectedNights > 0
                              ? booking.expectedNights
                              : (checkin == null
                                    ? 1
                                    : Time.nightsWithCutoff(
                                        checkin,
                                        checkout: plannedCheckout,
                                      )));
                      final actualNights = dynamicNights ??
                          (checkin == null
                              ? expectedNights
                              : Time.nightsWithCutoff(
                                  checkin,
                                  checkout:
                                      actualCheckout ?? plannedCheckout,
                                ));
                      final totalAmount = actualNights * price;
                      return RepaintBoundary(
                        child: _BookingRow(
                          index: index + 1,
                          booking: booking,
                          expectedNights: expectedNights,
                          actualNights: actualNights,
                          pricePerNight: price,
                          totalAmount: totalAmount,
                          currencyFmt: _currencyFmt,
                          plannedCheckout: plannedCheckout,
                          actualCheckout: actualCheckout,
                          compact: true,
                        ),
                      );
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CompactBookingCard extends StatelessWidget {
  const _CompactBookingCard({
    required this.booking,
    required this.index,
    required this.nightsLabel,
    required this.paid,
    required this.remaining,
    required this.statusColor,
    required this.statusText,
    required this.plannedText,
    required this.actualText,
    required this.currencyFmt,
    required this.pricePerNight,
    required this.totalAmount,
  });

  final Booking booking;
  final int index;
  final String nightsLabel;
  final double paid;
  final double remaining;
  final Color statusColor;
  final String statusText;
  final String? plannedText;
  final String? actualText;
  final NumberFormat currencyFmt;
  final double pricePerNight;
  final double totalAmount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(builder: (_) => BookingPaymentScreen(booking: booking),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    radius: 14,
                    child: Text(
                      index.toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الغرفة ${booking.roomNumber}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          booking.guestName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (booking.guestPhone.isNotEmpty)
                          Text(
                            booking.guestPhone,
                            style: const TextStyle(fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _formatDate(booking.checkinDate) +
                          (plannedText != null ? ' • حتى $plannedText' : ''),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (actualText != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.logout, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'خروج فعلي $actualText',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
              // تم إزالة فاصل المسافة SizedBox(height: 12) والـ Wrap بالكامل
              // الذي كان يحتوي على شرائح المعلومات (الليالي، السعر، المدفوع، المتبقي، الإجمالي)
              // Wrap(
              //   spacing: 8,
              //   runSpacing: 8,
              //   children: [
              //     _buildInfoChip(theme, Icons.king_bed, 'الليالي', nightsLabel),
              //     _buildInfoChip(theme, Icons.attach_money, 'سعر الليلة', currencyFmt.format(pricePerNight)),
              //     _buildInfoChip(theme, Icons.payments, 'المدفوع', currencyFmt.format(paid)),
              //     _buildInfoChip(theme, Icons.receipt_long, 'المتبقي', currencyFmt.format(remaining)),
              //     _buildInfoChip(theme, Icons.summarize, 'الإجمالي', currencyFmt.format(totalAmount)),
              //   ],
              // ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildHeaderRow(BuildContext context) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
    child: const Row(
      children: [
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
    this.compact = false,
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
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paidAsync = ref.watch(bookingPaidAmountProvider(booking.id));
    final baseTextStyle = TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black);
    final smallTextStyle = baseTextStyle.copyWith(fontSize: 12);
    final boldTextStyle = baseTextStyle.copyWith(fontWeight: FontWeight.w600);
    final nightsLabel = actualNights != expectedNights
        ? '$expectedNights ($actualNights فعلي)'
        : expectedNights.toString();
    final plannedText = plannedCheckout != null
        ? _formatDate(plannedCheckout!.toIso8601String())
        : null;
    final actualText = actualCheckout != null
        ? _formatDate(actualCheckout!.toIso8601String())
        : null;

    final guestTooltipLines = [
      'الاسم: ${booking.guestName}',
      if (booking.guestPhone.isNotEmpty) 'الهاتف: ${booking.guestPhone}',
      if (booking.guestIdNumber.isNotEmpty)
        'الهوية: ${booking.guestIdType} ${booking.guestIdNumber}',
      if (booking.guestNationality.isNotEmpty)
        'الجنسية: ${booking.guestNationality}',
      if (booking.guestEmail != null && booking.guestEmail!.isNotEmpty)
        'البريد: ${booking.guestEmail}',
      if (booking.guestAddress != null && booking.guestAddress!.isNotEmpty)
        'العنوان: ${booking.guestAddress}',
    ];
    final guestTooltip = guestTooltipLines.join('\n');

    final paid = paidAsync.maybeWhen(
      data: (total) => total,
      orElse: () => 0.0,
    );
    final remaining = (totalAmount - paid)
        .clamp(0.0, totalAmount);
    final Color statusColor = remaining <= 0.0
        ? Colors.green
        : (paid > 0 ? Colors.orange : Colors.red);
    final String statusText = remaining <= 0.0
        ? 'مسددة'
        : (paid > 0 ? 'جزئياً' : 'غير مسددة');

    return compact
        ? _CompactBookingCard(
            booking: booking,
            index: index,
            nightsLabel: nightsLabel,
            paid: paid,
            remaining: remaining,
            statusColor: statusColor,
            statusText: statusText,
            plannedText: plannedText,
            actualText: actualText,
            currencyFmt: currencyFmt,
            pricePerNight: pricePerNight,
            totalAmount: totalAmount,
          )
        : InkWell(
            onTap: () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => BookingPaymentScreen(booking: booking),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE0E0E0)),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      index.toString(),
                      textAlign: TextAlign.center,
                      style: baseTextStyle,
                    ),
                  ),
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
                              Text(
                                booking.guestPhone,
                                style: smallTextStyle,
                              ),
                            const SizedBox(height: 2),
                            Text(
                              booking.guestIdNumber.isEmpty
                                  ? booking.guestIdType
                                  : '${booking.guestIdType} • ${booking.guestIdNumber}',
                              style: smallTextStyle,
                            ),
                            if (booking.guestNationality.isNotEmpty)
                              Text(
                                booking.guestNationality,
                                style: smallTextStyle,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(booking.roomNumber, style: baseTextStyle),
                    ),
                  ),
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
                          Text(
                            _formatDate(booking.checkinDate),
                            style: baseTextStyle,
                          ),
                          if (plannedText != null)
                            Text('حتى $plannedText', style: smallTextStyle),
                          if (actualText != null)
                            Text(
                              'خروج فعلي $actualText',
                              style: smallTextStyle,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(nightsLabel, style: baseTextStyle),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        currencyFmt.format(paid),
                        style: baseTextStyle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        currencyFmt.format(remaining),
                        style: baseTextStyle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(
                          statusText,
                          style: baseTextStyle.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _buildBookingStatusChip(
                        booking.status,
                        baseTextStyle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
  }
}

Widget _buildBookingStatusChip(String status, TextStyle baseTextStyle) {
  Color bg;
  String txt;

  if (StatusUtils.isProvisional(status)) {
    bg = Colors.orange.shade100;
    txt = 'مؤقت';
  } else if (StatusUtils.isActiveBooking(status)) {
    bg = Colors.green.shade100;
    txt = 'محجوزة';
  } else {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'مكتمل':
        bg = Colors.blue.shade100;
        txt = 'مكتمل';
      case 'cancelled':
      case 'ملغي':
        bg = Colors.red.shade100;
        txt = 'ملغي';
      default:
        bg = Colors.grey.shade100;
        txt = status;
    }
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      txt,
      style: baseTextStyle.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
    ),
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
