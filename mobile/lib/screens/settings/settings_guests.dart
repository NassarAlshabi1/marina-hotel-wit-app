import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';

class SettingsGuestsScreen extends ConsumerStatefulWidget {
  const SettingsGuestsScreen({super.key});

  @override
  ConsumerState<SettingsGuestsScreen> createState() => _SettingsGuestsScreenState();
}

class _SettingsGuestsScreenState extends ConsumerState<SettingsGuestsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsListProvider);

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
          // تجميع الضيوف من الحجوزات
          final guests = _groupGuestsFromBookings(bookings);
          final filteredGuests = _filterGuests(guests);

          if (guests.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('لا يوجد ضيوف مسجلين', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 8),
                  Text('سيتم عرض الضيوف عند إضافة حجوزات', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return Column(
            children: [
              // شريط البحث
              _buildSearchBar(),
              
              // إحصائيات الضيوف
              _buildGuestStats(guests),
              
              const SizedBox(height: 16),
              
              // قائمة الضيوف
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredGuests.length,
                  itemBuilder: (context, index) {
                    final guest = filteredGuests[index];
                    return _buildGuestCard(context, guest);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<_GuestInfo> _groupGuestsFromBookings(List<Booking> bookings) {
    final Map<String, _GuestInfo> guestMap = {};

    for (final booking in bookings) {
      final key = '${booking.guestName}_${booking.guestPhone}';
      
      if (!guestMap.containsKey(key)) {
        guestMap[key] = _GuestInfo(
          name: booking.guestName,
          phone: booking.guestPhone,
          email: booking.guestEmail ?? '',
          nationality: booking.guestNationality,
          bookings: [],
        );
      }
      
      guestMap[key]!.bookings.add(booking);
    }

    // ترتيب الحجوزات حسب التاريخ
    for (final guest in guestMap.values) {
      guest.bookings.sort((a, b) => b.checkinDate.compareTo(a.checkinDate));
    }

    // ترتيب الضيوف حسب آخر زيارة
    return guestMap.values.toList()
      ..sort((a, b) => b.bookings.first.checkinDate.compareTo(a.bookings.first.checkinDate));
  }

  List<_GuestInfo> _filterGuests(List<_GuestInfo> guests) {
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
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildGuestStats(List<_GuestInfo> guests) {
    final totalGuests = guests.length;
    final activeGuests = guests.where((g) => 
      g.bookings.any((b) => b.status == 'محجوزة')).length;
    final repeatGuests = guests.where((g) => g.bookings.length > 1).length;
    final totalBookings = guests.fold<int>(0, (sum, g) => sum + g.bookings.length);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade50, Colors.purple.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics, color: Colors.purple, size: 24),
              SizedBox(width: 8),
              Text(
                'إحصائيات الضيوف',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatChip('إجمالي الضيوف', totalGuests, Colors.purple)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('ضيوف نشطون', activeGuests, Colors.green)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildStatChip('ضيوف متكررون', repeatGuests, Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('إجمالي الحجوزات', totalBookings, Colors.orange)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGuestCard(BuildContext context, _GuestInfo guest) {
    final activeBookings = guest.bookings.where((b) => b.status == 'محجوزة').length;
    final lastVisit = guest.bookings.first.checkinDate;
    
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
                  backgroundColor: activeBookings > 0 ? Colors.green : Colors.blue,
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
                          fontSize: 18,
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, size: 12, color: Colors.blue),
                        const SizedBox(width: 2),
                        Text(
                          'ضيف متكرر',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
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
            
            // إحصائيات الحجوزات
            Row(
              children: [
                Expanded(
                  child: _buildDetailRow('إجمالي الحجوزات', guest.bookings.length.toString(), Icons.book),
                ),
                Expanded(
                  child: _buildDetailRow('حجوزات نشطة', activeBookings.toString(), Icons.event_available),
                ),
                Expanded(
                  child: _buildDetailRow('آخر زيارة', _formatDate(lastVisit), Icons.calendar_today),
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
                    onPressed: () => _showGuestDetails(context, guest),
                    icon: const Icon(Icons.info, size: 16),
                    label: const Text('التفاصيل'),
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
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
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

  void _showGuestHistory(BuildContext context, _GuestInfo guest) {
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
                      backgroundColor: booking.status == 'محجوزة' ? Colors.green : Colors.blue,
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

  void _showGuestDetails(BuildContext context, _GuestInfo guest) {
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
              _buildInfoRow('إجمالي الحجوزات:', guest.bookings.length.toString()),
              _buildInfoRow('الحجوزات النشطة:', guest.bookings.where((b) => b.status == 'محجوزة').length.toString()),
              _buildInfoRow('آخر زيارة:', _formatDate(guest.bookings.first.checkinDate)),
              if (guest.bookings.length > 1)
                _buildInfoRow('أول زيارة:', _formatDate(guest.bookings.last.checkinDate)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // TODO: إضافة حجز جديد للضيف
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('إضافة حجز جديد (قيد التطوير)')),
                );
              },
              child: const Text('حجز جديد'),
            ),
          ],
        ),
      ),
    );
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

class _GuestInfo {
  final String name;
  final String phone;
  final String email;
  final String nationality;
  final List<Booking> bookings;

  _GuestInfo({
    required this.name,
    required this.phone,
    required this.email,
    required this.nationality,
    required this.bookings,
  });
}