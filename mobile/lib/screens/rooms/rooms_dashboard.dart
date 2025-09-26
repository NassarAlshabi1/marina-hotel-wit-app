import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../components/widgets/room_widgets.dart';
import '../bookings/booking_edit.dart';

class RoomsDashboard extends ConsumerWidget {
  const RoomsDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(roomsListProvider);

    return AppScaffold(
      title: 'حالة الغرف',
      actions: [
        IconButton(
          onPressed: () => ref.read(syncServiceProvider).runSync(),
          icon: const Icon(Icons.sync),
          tooltip: 'مزامنة',
        ),
      ],
      body: roomsAsync.when(
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
          if (rooms.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hotel, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('لا توجد غرف مسجلة', style: TextStyle(fontSize: 18)),
                ],
              ),
            );
          }

          return _buildFloorsView(context, ref, rooms);
        },
      ),
    );
  }

  Widget _buildFloorsView(BuildContext context, WidgetRef ref, List<Room> rooms) {
    // تنظيم الغرف حسب الطوابق
    final Map<String, List<Room>> floorMap = {};
    
    for (final room in rooms) {
      // استخراج رقم الطابق من رقم الغرفة (الرقم الأول)
      String floorNumber;
      if (room.roomNumber.isNotEmpty) {
        floorNumber = room.roomNumber[0];
      } else {
        floorNumber = '0'; // طابق افتراضي للغرف بدون رقم واضح
      }
      
      if (!floorMap.containsKey(floorNumber)) {
        floorMap[floorNumber] = [];
      }
      floorMap[floorNumber]!.add(room);
    }
    
    // ترتيب الطوابق والغرف
    final sortedFloors = floorMap.keys.toList()..sort();
    for (final floor in sortedFloors) {
      floorMap[floor]!.sort((a, b) => _compareRoomNumbers(a.roomNumber, b.roomNumber));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedFloors.length,
      itemBuilder: (context, index) {
        final floorNumber = sortedFloors[index];
        final floorRooms = floorMap[floorNumber]!;
        
        return FloorSection(
          floorNumber: floorNumber,
          rooms: floorRooms,
          onRoomTap: (room) => _handleRoomTap(context, ref, room),
          isCollapsible: true,
          initiallyExpanded: index < 2, // فتح أول طابقين بشكل افتراضي
        );
      },
    );
  }











  void _handleRoomTap(BuildContext context, WidgetRef ref, Room room) {
    showDialog(
      context: context,
      builder: (context) => RoomDetailsDialog(
        room: room,
        onBookRoom: room.status == 'شاغرة' ? () => _navigateToBooking(context, room.roomNumber) : null,
        onViewBookings: room.status != 'شاغرة' ? () => _showRoomBookings(context, ref, room.roomNumber) : null,
      ),
    );
  }





  void _navigateToBooking(BuildContext context, String roomNumber) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BookingEditScreen(roomNumber: roomNumber),
      ),
    );
  }

  void _showRoomBookings(BuildContext context, WidgetRef ref, String roomNumber) {
    // إظهار رسالة أو التنقل لعرض حجوزات الغرفة
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('عرض حجوزات غرفة $roomNumber'),
        action: SnackBarAction(
          label: 'إغلاق',
          onPressed: () {},
        ),
      ),
    );
  }

  int _compareRoomNumbers(String a, String b) {
    // محاولة مقارنة رقمية إذا كانت الأرقام
    final aNum = int.tryParse(a);
    final bNum = int.tryParse(b);
    
    if (aNum != null && bNum != null) {
      return aNum.compareTo(bNum);
    }
    
    // مقارنة أبجدية إذا لم تكن أرقام
    return a.compareTo(b);
  }
}