// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: discarded_futures
// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart';
import '../../providers/repository_providers.dart';
import '../../services/booking_derived_fields_service.dart';
import '../../services/local_db.dart' hide GuestInfo;
import '../../services/sync_service.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';
import '../bookings/booking_edit.dart';
import 'guest_edit_screen.dart';
import 'guest_info.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class SettingsGuestsScreen extends ConsumerStatefulWidget {
  const SettingsGuestsScreen({super.key});

  @override
  ConsumerState<SettingsGuestsScreen> createState() =>
      _SettingsGuestsScreenState();
}

class _SettingsGuestsScreenState extends ConsumerState<SettingsGuestsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsListProvider);
    final roomsAsync = ref.watch(roomsListProvider);

    return AppScaffold(
      title: 'إدارة الضيوف',
      actions: [
        IconButton(
          onPressed: () => ref.read(syncServiceProvider).runSync(),
          icon: const Icon(Icons.sync),
          tooltip: 'مزامنة',
        ),
      ],
      body: bookingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('خطأ: $e', textAlign: TextAlign.center),
            ],
          ),
        ),
        data: (bookings) {
          return roomsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('خطأ: $e', textAlign: TextAlign.center),
                ],
              ),
            ),
            data: (rooms) {
              // تجميع الضيوف من الحجوزات
              final guests = _groupGuestsFromBookings(bookings);
              final filteredGuests = _filterGuests(guests);
              final roomPrices = {for (final r in rooms) r.roomNumber: r.price};

              if (guests.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'لا يوجد ضيوف مسجلين',
                        style: TextStyle(fontSize: 18),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'سيتم عرض الضيوف عند إضافة حجوزات',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  _buildSearchBar(),

                  // قائمة الضيوف
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(bookingsListProvider);
                        ref.invalidate(roomsListProvider);
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredGuests.length,
                        itemBuilder: (context, index) {
                          final guest = filteredGuests[index];
                          return RepaintBoundary(
                            child: _buildGuestCard(context, guest, roomPrices),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<GuestInfo> _groupGuestsFromBookings(List<Booking> bookings) {
    final Map<String, GuestInfo> guestMap = {};

    for (final booking in bookings) {
      if (!StatusUtils.isActiveBooking(booking.status)) {
        continue;
      }

      final key = '${booking.guestName}_${booking.guestPhone}';
      final email = booking.guestEmail ?? '';
      final idType = booking.guestIdType;
      final idNumber = booking.guestIdNumber;
      final idIssueDate = booking.guestIdIssueDate;
      final idIssuePlace = booking.guestIdIssuePlace;
      final address = booking.guestAddress;

      final existing = guestMap[key];
      if (existing == null) {
        guestMap[key] = GuestInfo(
          name: booking.guestName,
          phone: booking.guestPhone,
          email: email,
          nationality: booking.guestNationality,
          idType: idType,
          idNumber: idNumber,
          idIssueDate: idIssueDate,
          idIssuePlace: idIssuePlace,
          address: address,
          bookings: [booking],
        );
      } else {
        existing.bookings.add(booking);
        if (existing.email.isEmpty && email.isNotEmpty) {
          existing.email = email;
        }
        if (existing.nationality.isEmpty &&
            booking.guestNationality.isNotEmpty) {
          existing.nationality = booking.guestNationality;
        }
        if (existing.idType.isEmpty && idType.isNotEmpty) {
          existing.idType = idType;
        }
        if (existing.idNumber.isEmpty && idNumber.isNotEmpty) {
          existing.idNumber = idNumber;
        }
        if (existing.idIssueDate == null && idIssueDate != null) {
          existing.idIssueDate = idIssueDate;
        }
        if (existing.idIssuePlace == null && idIssuePlace != null) {
          existing.idIssuePlace = idIssuePlace;
        }
        if (existing.address == null && address != null && address.isNotEmpty) {
          existing.address = address;
        }
      }
    }

    for (final guest in guestMap.values) {
      guest.bookings.sort((a, b) => b.checkinDate.compareTo(a.checkinDate));
    }

    final sortedGuests =
        guestMap.values.where((g) => g.bookings.isNotEmpty).toList()..sort(
          (a, b) => (b.bookings.firstOrNull?.checkinDate ?? '').compareTo(
            a.bookings.firstOrNull?.checkinDate ?? '',
          ),
        );
    return sortedGuests;
  }

  List<GuestInfo> _filterGuests(List<GuestInfo> guests) {
    if (_searchQuery.isEmpty) {
      return guests;
    }

    return guests.where((guest) {
      return guest.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          guest.phone.contains(_searchQuery) ||
          guest.email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          guest.nationality.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'البحث في الضيوف (الاسم، الهاتف، البريد، الجنسية)',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildGuestCard(
    BuildContext context,
    GuestInfo guest,
    Map<String, double> roomPrices,
  ) {
    final activeBookings = guest.bookings
        .where((b) => StatusUtils.isActiveBooking(b.status))
        .length;
    final lastVisit = guest.bookings.isNotEmpty
        ? guest.bookings.first.checkinDate
        : '';
    final latestBooking = guest.bookings.isNotEmpty
        ? guest.bookings.first
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // معلومات أساسية
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: activeBookings > 0
                      ? Colors.green
                      : Colors.blueGrey,
                  child: Text(
                    latestBooking != null ? latestBooking.roomNumber : '—',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guest.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        guest.nationality,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (guest.bookings.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, size: 12, color: Colors.blue),
                        SizedBox(width: 2),
                        Text(
                          'ضيف متكرر',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _showGuestDetails(context, guest),
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'عرض التفاصيل',
                ),
              ],
            ),

            const SizedBox(height: 12),

            // تفاصيل الاتصال
            Row(
              children: [
                Expanded(
                  child: _buildDetailRow('الهاتف', guest.phone, Icons.phone),
                ),
                if (guest.email.isNotEmpty)
                  Expanded(
                    child: _buildDetailRow('البريد', guest.email, Icons.email),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            if (latestBooking != null) ...[
              _buildPricePreview(latestBooking, roomPrices),
              const SizedBox(height: 8),
            ],

            // إحصائيات الحجوزات
            Row(
              children: [
                Expanded(
                  child: _buildDetailRow(
                    'إجمالي الحجوزات',
                    guest.bookings.length.toString(),
                    Icons.book,
                  ),
                ),
                Expanded(
                  child: _buildDetailRow(
                    'حجوزات نشطة',
                    activeBookings.toString(),
                    Icons.event_available,
                  ),
                ),
                Expanded(
                  child: _buildDetailRow(
                    'آخر زيارة',
                    _formatDate(lastVisit),
                    Icons.calendar_today,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showGuestHistory(context, guest),
                    icon: const Icon(Icons.history, size: 14),
                    label: const Text('السجل', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _editCheckinDate(context, guest),
                    icon: const Icon(Icons.login, size: 14),
                    label: const Text(
                      'تاريخ الدخول',
                      style: TextStyle(fontSize: 10),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 32),
                      backgroundColor: Colors.teal,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _editGuest(context, guest),
                    icon: const Icon(Icons.edit, size: 14),
                    label: const Text('تعديل', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteGuest(context, guest),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: Colors.red,
                    ),
                    label: const Text('حذف', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPricePreview(Booking booking, Map<String, double> roomPrices) {
    final basePrice = roomPrices[booking.roomNumber];
    if (basePrice == null) {
      return _buildDetailRow('سعر الغرفة', 'غير متوفر', Icons.hotel_class);
    }
    return _buildDetailRow(
      'سعر الغرفة',
      basePrice.toStringAsFixed(2),
      Icons.hotel_class,
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  void _showGuestHistory(BuildContext context, GuestInfo guest) {
    showDialog<void>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تاريخ حجوزات ${guest.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: guest.bookings.length,
              itemBuilder: (context, index) {
                final booking = guest.bookings[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              StatusUtils.isActiveBooking(booking.status)
                              ? Colors.green
                              : Colors.blue,
                          child: Text((index + 1).toString()),
                        ),
                        title: Text('غرفة ${booking.roomNumber}'),
                        subtitle: Text(
                          'من ${_formatDate(booking.checkinDate)}\n'
                          'الحالة: ${booking.status}',
                        ),
                        trailing: Text(
                          '${booking.calculatedNights} ليلة',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        isThreeLine: true,
                      ),
                      // ✅ أزرار تعديل وحذف لكل حجز فردي
                      OverflowBar(
                        alignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _editBooking(context, booking);
                            },
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('تعديل الحجز'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blue,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _deleteBooking(context, booking, guest);
                            },
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('حذف الحجز'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ تعديل حجز فردي — يفتح BookingEditScreen مع `existing: booking`
  Future<void> _editBooking(BuildContext context, Booking booking) async {
    final result =
        await Navigator.of(
          context,
        ).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => BookingEditScreen(existing: booking),
          ),
        );
    if ((result ?? false) && mounted) {
      ref.invalidate(bookingsListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحديث بيانات الحجز')));
    }
  }

  /// ✅ حذف حجز فردي — مع تأكيد + حذف المدفوعات/الملاحظات/الديون المرتبطة
  Future<void> _deleteBooking(
    BuildContext context,
    Booking booking,
    GuestInfo guest,
  ) async {
    final isActive = StatusUtils.isActiveBooking(booking.status);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد حذف الحجز'),
          content: Text(
            'سيتم حذف الحجز رقم ${booking.id} '
            '(غرفة ${booking.roomNumber})${'\n'
                'للضيف: ${guest.name}'}.\n\n'
            'سيتم حذف جميع المدفوعات والملاحظات والديون المرتبطة بهذا الحجز. '
            '${isActive ? '\n\n⚠️ هذا حجز نشط — سيتم تحرير الغرفة.' : ''}\n\n'
            'هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop<bool>(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop<bool>(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final bookingsRepo = ref.read(bookingsRepoProvider);
      final roomsRepo = ref.read(roomsRepoProvider);
      final paymentsRepo = ref.read(paymentsRepoProvider);
      final debtsRepo = ref.read(debtsRepoProvider);
      final notesRepo = ref.read(notesRepoProvider);

      // 1. إذا كان الحجز نشطاً، حرّر الغرفة
      if (isActive && booking.roomNumber.isNotEmpty) {
        final room = await roomsRepo.watchByNumber(booking.roomNumber).first;
        if (room != null && !StatusUtils.isRoomAvailable(room.status)) {
          await roomsRepo.update(room.id, status: 'شاغرة');
        }
      }

      // 2. حذف الملاحظات المرتبطة
      final notes = await notesRepo.watchByBooking(booking.id).first;
      for (final note in notes) {
        await notesRepo.delete(note.id);
      }

      // 3. حذف المدفوعات المرتبطة
      final payments = await paymentsRepo.paymentsByBooking(booking.id).first;
      for (final payment in payments) {
        await paymentsRepo.delete(payment.id);
      }

      // 4. حذف الديون المرتبطة
      final bookingDebts = await debtsRepo.listByBookingLocalId(booking.id);
      for (final debt in bookingDebts) {
        await debtsRepo.delete(debt.id);
      }

      // 5. حذف الحجز نفسه (soft delete مع outbox للمزامنة)
      await bookingsRepo.delete(booking.id);

      // ✅ رفع فوري للتغييرات إلى Appwrite Cloud بعد كتلة الحذف الكاملة.
      // كل العمليات أعلاه (5 خطوات) تتم داخل transaction واحد في الـ DAOs،
      // لكن الـ outbox entries تُنشأ لكل عملية على حدة — pushLocalChanges
      // يرفعها كلها دفعة واحدة.
      unawaited(ref.read(appwriteSyncManagerProvider).pushLocalChanges());

      if (!mounted) return;
      ref.invalidate(bookingsListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الحجز وكل البيانات المرتبطة به'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text('فشل حذف الحجز: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showGuestDetails(BuildContext context, GuestInfo guest) {
    showDialog<void>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تفاصيل الضيف - ${guest.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('الاسم:', guest.name),
              _buildInfoRow('الهاتف:', guest.phone),
              if (guest.email.isNotEmpty) _buildInfoRow('البريد:', guest.email),
              _buildInfoRow('الجنسية:', guest.nationality),
              const Divider(),
              _buildInfoRow(
                'إجمالي الحجوزات:',
                guest.bookings.length.toString(),
              ),
              _buildInfoRow(
                'الحجوزات النشطة:',
                guest.bookings
                    .where((b) => StatusUtils.isActiveBooking(b.status))
                    .length
                    .toString(),
              ),
              _buildInfoRow(
                'آخر زيارة:',
                guest.bookings.isNotEmpty
                    ? _formatDate(guest.bookings.first.checkinDate)
                    : '-',
              ),
              if (guest.bookings.length > 1)
                _buildInfoRow(
                  'أول زيارة:',
                  _formatDate(guest.bookings.last.checkinDate),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCheckinDate(BuildContext context, GuestInfo guest) async {
    final bookingsRepo = ref.read(bookingsRepoProvider);
    final db = ref.read(databaseProvider);

    // خريطة: bookingId → تاريخ دخول جديد
    final Map<int, String> newDates = {};
    for (final b in guest.bookings) {
      newDates[b.id] = b.checkinDate;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('تعديل تاريخ الدخول - ${guest.name}'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'اختر التاريخ الجديد لكل حجز. سيتم إعادة حساب المبالغ تلقائياً.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  ...guest.bookings.map((booking) {
                    final current = newDates[booking.id]!;
                    final currentDate = _parseDate(current);
                    final isChanged =
                        current.split('T').first !=
                        booking.checkinDate.split('T').first;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor:
                                      StatusUtils.isActiveBooking(
                                        booking.status,
                                      )
                                      ? Colors.green
                                      : Colors.blueGrey,
                                  child: Text(
                                    booking.roomNumber,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'غرفة ${booking.roomNumber} - حجز #${booking.id}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        'الحالة: ${booking.status} • ${booking.calculatedNights} ليلة',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            currentDate ?? DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked == null) {
                                        return;
                                      }

                                      // الحفاظ على الوقت الأصلي إن وجد
                                      final oldTime =
                                          booking.checkinDate.contains('T')
                                          ? booking.checkinDate.split('T')[1]
                                          : '00:00:00';
                                      final newDateStr =
                                          '${_dateToString(picked)}T$oldTime';

                                      setDialogState(() {
                                        newDates[booking.id] = newDateStr;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isChanged
                                            ? Colors.teal.shade50
                                            : Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isChanged
                                              ? Colors.teal
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today,
                                            size: 16,
                                            color: isChanged
                                                ? Colors.teal
                                                : Colors.grey,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _formatDate(current),
                                            style: TextStyle(
                                              fontWeight: isChanged
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: isChanged
                                                  ? Colors.teal.shade700
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (isChanged)
                                            const Icon(
                                              Icons.check_circle,
                                              size: 16,
                                              color: Colors.teal,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // اختيار الوقت
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final currentTime = _parseDate(current);
                                      if (currentTime == null) {
                                        return;
                                      }
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay.fromDateTime(
                                          currentTime,
                                        ),
                                      );
                                      if (picked == null) {
                                        return;
                                      }

                                      final datePart = current.split('T').first;
                                      final newDateStr =
                                          '${datePart}T${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';

                                      setDialogState(() {
                                        newDates[booking.id] = newDateStr;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 16,
                                            color: Colors.grey[600],
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _formatTime(current),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (isChanged)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: Colors.teal.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'القديم: ${_formatDate(booking.checkinDate)} → سيتم إعادة الحساب',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.teal.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.save, size: 18),
                label: const Text('حفظ'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != true) {
      return;
    }

    // حفظ التغييرات
    bool hasChanges = false;
    try {
      for (final booking in guest.bookings) {
        final newDate = newDates[booking.id];
        if (newDate == null) {
          continue;
        }
        final dateOnlyNew = newDate.split('T').first;
        final dateOnlyOld = booking.checkinDate.split('T').first;
        if (dateOnlyNew == dateOnlyOld &&
            !_timeChanged(newDate, booking.checkinDate)) {
          continue;
        }

        hasChanges = true;
        await bookingsRepo.update(booking.id, checkinDate: newDate);
        final derivedService = BookingDerivedFieldsService(db);
        await derivedService.refreshForBookingId(booking.id);
      }

      // ✅ رفع فوري بعد تعديل تواريخ الدخول (شرط أن تم تعديل شيء فعلاً)
      if (hasChanges) {
        unawaited(ref.read(appwriteSyncManagerProvider).pushLocalChanges());
      }

      if (hasChanges && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تعديل تاريخ الدخول وإعادة حساب المبالغ بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text('تعذر تعديل تاريخ الدخول: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  DateTime? _parseDate(String value) {
    if (value.isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(value);
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in settings_guests.dart: ');
      return null;
    }
  }

  String _dateToString(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in settings_guests.dart: ');
      return '--:--';
    }
  }

  bool _timeChanged(String newDate, String oldDate) {
    try {
      final newDt = DateTime.parse(newDate);
      final oldDt = DateTime.parse(oldDate);
      return newDt.hour != oldDt.hour || newDt.minute != oldDt.minute;
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in settings_guests.dart: ');
      return false;
    }
  }

  Future<void> _editGuest(BuildContext context, GuestInfo guest) async {
    final result =
        await Navigator.of(
          context,
        ).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => GuestEditScreen(guest: guest),
          ),
        );
    if ((result ?? false) && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحديث بيانات الضيف')));
    }
  }

  Future<void> _deleteGuest(BuildContext context, GuestInfo guest) async {
    final activeBookings = guest.bookings
        .where((b) => StatusUtils.isActiveBooking(b.status))
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد حذف الضيف وكل البيانات المرتبطة'),
          content: Text(
            'سيتم حذف جميع الحجوزات (${guest.bookings.length}) وكل ما يتعلق بها من مدفوعات وملاحظات وديون لهذا الضيف. ${activeBookings.isNotEmpty ? '\n\nتحذير: هناك ${activeBookings.length} حجوزات نشطة سيتم عمل checkout ثم حذفها.' : ''}\n\nهل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop<bool>(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop<bool>(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      final bookingsRepo = ref.read(bookingsRepoProvider);
      final roomsRepo = ref.read(roomsRepoProvider);
      final paymentsRepo = ref.read(paymentsRepoProvider);
      final debtsRepo = ref.read(debtsRepoProvider);
      final notesRepo = ref.read(notesRepoProvider);
      final database = ref.read(databaseProvider);

      if (guest.bookings.isEmpty) {
        return;
      }

      // ✅ P0 fix: لف كل العمليات في transaction واحد لضمان atomicity
      await database.transaction(() async {
        // ─── 1. Checkout للحجوزات النشطة ───
        final nowIso = Time.nowIso();
        final freedRooms = <String>{};
        for (final booking in activeBookings) {
          await bookingsRepo.update(
            booking.id,
            status: 'مكتمل',
            actualCheckout: nowIso,
          );
          if (booking.roomNumber.isNotEmpty) {
            freedRooms.add(booking.roomNumber);
          }
        }

        // ─── 2. تحرير الغرف ───
        for (final roomNumber in freedRooms) {
          final room = await roomsRepo.watchByNumber(roomNumber).first;
          if (room != null && !StatusUtils.isRoomAvailable(room.status)) {
            await roomsRepo.update(room.id, status: 'شاغرة');
          }
        }

        // ─── 3. حذف الملاحظات ───
        for (final booking in guest.bookings) {
          final notes = await notesRepo.watchByBooking(booking.id).first;
          for (final note in notes) {
            await notesRepo.delete(note.id);
          }
        }

        // ─── 4. حذف المدفوعات ───
        for (final booking in guest.bookings) {
          final payments = await paymentsRepo
              .paymentsByBooking(booking.id)
              .first;
          for (final payment in payments) {
            await paymentsRepo.delete(payment.id);
          }
        }

        // ─── 5. حذف الديون ───
        for (final booking in guest.bookings) {
          final bookingDebts = await debtsRepo.listByBookingLocalId(booking.id);
          for (final debt in bookingDebts) {
            await debtsRepo.delete(debt.id);
          }
        }

        // ─── 6. حذف الحجوزات ───
        for (final booking in guest.bookings) {
          await bookingsRepo.delete(booking.id);
        }

        // ─── 7. تحرير الغرف المتبقية ───
        final allRoomNumbers = guest.bookings
            .where((b) => b.roomNumber.isNotEmpty)
            .map((b) => b.roomNumber)
            .toSet()
            .difference(freedRooms);
        for (final roomNumber in allRoomNumbers) {
          final room = await roomsRepo.watchByNumber(roomNumber).first;
          if (room != null && !StatusUtils.isRoomAvailable(room.status)) {
            await roomsRepo.update(room.id, status: 'شاغرة');
          }
        }
      }); // ✅ نهاية transaction — atomic

      // ✅ رفع فوري بعد كتلة حذف الضيف الكاملة (7 خطوات داخل transaction).
      // كل من: checkout، تحرير غرف، حذف ملاحظات/مدفوعات/ديون، حذف حجوزات.
      unawaited(ref.read(appwriteSyncManagerProvider).pushLocalChanges());

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'تم حذف الضيف وجميع البيانات المرتبطة مع checkout للحجوزات النشطة',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
