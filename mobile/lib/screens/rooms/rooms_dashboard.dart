import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/room_widgets.dart';
import '../../models/db_types.dart';
import '../../providers/repository_providers.dart';
import '../../providers/room_payment_status_provider.dart'; // استيراد البروفايدر الجديد
import '../../services/sync_service.dart';
import '../../utils/status_utils.dart';
import '../bookings/booking_edit.dart';
import '../payments/booking_payment_screen.dart';

class RoomsDashboard extends ConsumerStatefulWidget {
  const RoomsDashboard({super.key});

  @override
  ConsumerState<RoomsDashboard> createState() => _RoomsDashboardState();
}

class _RoomsDashboardState extends ConsumerState<RoomsDashboard> {
  // ✅ ValueNotifier — يمنع إعادة بناء AppScaffold مع كل تغيير
  // يستخدم ref.listen (بدون StreamSubscription) للأداء الأقصى
  final ValueNotifier<AsyncValue<List<RoomWithPaymentStatus>>> _roomsNotifier =
      ValueNotifier<AsyncValue<List<RoomWithPaymentStatus>>>(const AsyncValue<List<RoomWithPaymentStatus>>.loading());

  @override
  void dispose() {
    _roomsNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(roomsWithPaymentStatusProvider, (prev, next) {
      _roomsNotifier.value = next;
    });
    return AppScaffold(
      title: 'حالة الغرف',
      actions: [
        IconButton(
          onPressed: () => ref.read(syncServiceProvider).runSync(),
          icon: const Icon(Icons.sync),
          tooltip: 'مزامنة',
        ),
      ],
      // ✅ P0: ValueListenableBuilder — فقط الـ body يُعاد بناؤه، الـ Scaffold لا يتأثر
      body: ValueListenableBuilder<AsyncValue<List<RoomWithPaymentStatus>>>(
        valueListenable: _roomsNotifier,
        builder: (context, roomsWithStatusAsync, _) {
          return roomsWithStatusAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) {
              debugPrint('❌ RoomsDashboard error: $e\n$st');
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, size: 64, color: Colors.red),
                    SizedBox(height: 16),
                    Text('حدث خطأ أثناء تحميل الغرف', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
                    SizedBox(height: 8),
                    Text(
                      'تحقّق من اتصال الشبكة وحاول مرة أخرى.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              );
            },
            data: (roomsWithStatus) {
              if (roomsWithStatus.isEmpty) {
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
              return _buildFloorsView(context, ref, roomsWithStatus);
            },
          );
        },
      ),
    );
  }

  Widget _buildFloorsView(BuildContext context, WidgetRef ref, List<RoomWithPaymentStatus> roomsWithStatus) {
    // تنظيم الغرف حسب الطوابق
    final Map<String, List<RoomWithPaymentStatus>> floorMap = {};

    for (final roomData in roomsWithStatus) {
      final room = roomData.room;
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
      floorMap[floorNumber]!.add(roomData);
    }

    // ترتيب الطوابق والغرف
    final sortedFloors = floorMap.keys.toList()..sort();
    for (final floor in sortedFloors) {
      floorMap[floor]!.sort((a, b) => _compareRoomNumbers(a.room.roomNumber, b.room.roomNumber));
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(roomsWithPaymentStatusProvider);
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedFloors.length,
        itemBuilder: (context, index) {
          final floorNumber = sortedFloors[index];
          final floorRooms = floorMap[floorNumber]!;

          return RepaintBoundary(
            child: FloorSection(
              floorNumber: floorNumber,
              rooms: floorRooms,
              onRoomTap: (room) => _handleRoomTap(context, ref, room),
              isCollapsible: true,
              initiallyExpanded: index < 2,
            ),
          );
        },
      ),
    );
  }

  void _handleRoomTap(BuildContext context, WidgetRef ref, Room room) {
    final isAvailable = StatusUtils.isRoomAvailable(room.status);
    final isOccupied = StatusUtils.isRoomOccupied(room.status);

    if (isAvailable) {
      // الانتقال مباشرة إلى شاشة إضافة حجز جديد عند النقر على غرفة شاغرة
      _navigateToBooking(context, room.roomNumber);
    } else if (isOccupied) {
      // الانتقال مباشرة إلى شاشة الدفع/عرض الحجز عند النقر على غرفة محجوزة
      _showRoomBookings(context, ref, room.roomNumber);
    } else {
      // للحالات الأخرى مثل الصيانة، نعرض التفاصيل
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('غرفة ${room.roomNumber}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('الحالة', room.status),
              if (room.type.isNotEmpty) _buildDetailRow('النوع', room.type),
              if (room.price > 0) _buildDetailRow('السعر', '${room.price.toStringAsFixed(0)} ريال'),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
        ),
      );
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  void _navigateToBooking(BuildContext context, String roomNumber) {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (context) => BookingEditScreen(initialRoomNumber: roomNumber)));
  }

  Future<void> _showRoomBookings(BuildContext context, WidgetRef ref, String roomNumber) async {
    try {
      final bookingsRepo = ref.read(bookingsRepoProvider);
      final activeBooking = await bookingsRepo.getActiveBookingForRoom(roomNumber);

      if (activeBooking == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('لا يوجد حجز محجوز للغرفة $roomNumber'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      if (!context.mounted) {
        return;
      }

      unawaited(
        Navigator.of(
          context,
        ).push<void>(MaterialPageRoute<void>(builder: (_) => BookingPaymentScreen(booking: activeBooking))),
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحميل الحجز: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
