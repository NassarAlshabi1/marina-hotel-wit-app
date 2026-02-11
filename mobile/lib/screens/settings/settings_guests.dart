import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../utils/status_utils.dart';
import 'guest_edit_screen.dart';
import 'guest_info.dart';

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
              final roomPrices = {
                for (final r in rooms) r.roomNumber: r.price,
              };

              if (guests.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('لا يوجد ضيوف مسجلين', style: TextStyle(fontSize: 18)),
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
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredGuests.length,
                      itemBuilder: (context, index) {
                        final guest = filteredGuests[index];
                        return _buildGuestCard(context, guest, roomPrices);
                      },
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
      if (!StatusUtils.isActiveBooking(booking.status)) continue;

      final key = '${booking.guestName}_${booking.roomNumber}';
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
          (a, b) => b.bookings.first.checkinDate.compareTo(
            a.bookings.first.checkinDate,
          ),
        );
    return sortedGuests;
  }

  List<GuestInfo> _filterGuests(List<GuestInfo> guests) {
    if (_searchQuery.isEmpty) return guests;

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
    final latestBooking = guest.bookings.isNotEmpty ? guest.bookings.first : null;

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
                  backgroundColor: activeBookings > 0
                      ? Colors.green
                      : Colors.blue,
                  child: Text(
                    guest.name.isNotEmpty ? guest.name[0].toUpperCase() : '؟',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
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
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
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

            // أزرار العمليات
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showGuestHistory(context, guest),
                    icon: const Icon(Icons.history, size: 16),
                    label: const Text('تاريخ الحجوزات'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _editGuest(context, guest),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('تعديل البيانات'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteGuest(context, guest),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: Colors.red,
                    ),
                    label: const Text('حذف الضيف وجميع البيانات'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
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

  Widget _buildPricePreview(
    Booking booking,
    Map<String, double> roomPrices,
  ) {
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
    showDialog(
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
                  child: ListTile(
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

  void _showGuestDetails(BuildContext context, GuestInfo guest) {
    showDialog(
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

  Future<void> _editGuest(BuildContext context, GuestInfo guest) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GuestEditScreen(guest: guest)),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحديث بيانات الضيف')));
    }
  }

  Future<void> _deleteGuest(BuildContext context, GuestInfo guest) async {
    final active = guest.bookings
        .where((b) => StatusUtils.isActiveBooking(b.status))
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد حذف الضيف وكل البيانات المرتبطة'),
          content: Text(
            'سيتم حذف جميع الحجوزات (${guest.bookings.length}) وكل ما يتعلق بها من مدفوعات وملاحظات وديون لهذا الضيف. ${active > 0 ? '\n\nتحذير: هناك حجوزات نشطة سيتم حذفها أيضاً.' : ''}\n\nهل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
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
      final paymentsRepo = ref.read(paymentsRepoProvider);
      final notesRepo = ref.read(notesRepoProvider);
      final debtsRepo = ref.read(debtsRepoProvider);
      final cashRepo = ref.read(cashRepoProvider);
      final roomsRepo = ref.read(roomsRepoProvider);

      for (final b in guest.bookings) {
        final bookingId = b.id;
        // حذف الملاحظات المرتبطة بالحجز
        final notes = await notesRepo.dao.list(bookingId: bookingId);
        for (final n in notes) {
          await notesRepo.delete(n.id);
        }
        // حذف المدفوعات المرتبطة بالحجز + المعاملات النقدية التابعة لها
        final pays = await paymentsRepo.dao.list(bookingLocalId: bookingId);
        for (final p in pays) {
          if (p.cashTransactionLocalId != null) {
            await cashRepo.delete(p.cashTransactionLocalId!);
          }
          await paymentsRepo.delete(p.id);
        }
        // حذف المعاملات النقدية المرتبطة بالحجز مباشرة عبر referenceType/referenceId
        final relatedCash = await cashRepo.listByReference(
          referenceType: 'booking',
          referenceId: bookingId,
        );
        for (final tx in relatedCash) {
          await cashRepo.delete(tx.id);
        }
        // حذف الديون المرتبطة بالحجز
        final debts = await debtsRepo.listByBookingLocalId(bookingId);
        for (final d in debts) {
          await debtsRepo.delete(d.id);
        }
        // تحرير الغرفة المرتبطة بالحجز إذا كانت ما زالت محجوزة
        if (b.roomNumber.isNotEmpty) {
          final room = await roomsRepo.watchByNumber(b.roomNumber).first;
          if (room != null && !StatusUtils.isRoomAvailable(room.status)) {
            await roomsRepo.update(room.id, status: 'شاغرة');
          }
        }
        // حذف الحجز نفسه
        await bookingsRepo.delete(bookingId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الضيف وجميع البيانات المرتبطة')),
      );
    } catch (e) {
      if (!mounted) return;
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
