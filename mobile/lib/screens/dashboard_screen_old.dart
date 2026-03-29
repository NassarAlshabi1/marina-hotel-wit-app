import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_db.dart';
import '../providers/repository_providers.dart';
import '../services/sync_service.dart';
import '../utils/status_utils.dart';
import '../widgets/smart_sync_widgets.dart';

const List<String> _dashboardRoomNumbers = [
  '101',
  '102',
  '103',
  '104',
  '201',
  '202',
  '203',
  '204',
  '301',
  '302',
  '303',
  '304',
  '401',
  '402',
  '403',
  '404',
  '501',
  '502',
];

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with sync button
          Row(
            children: [
              const Text(
                'لوحة التحكم - نظام إدارة الفندق',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () async {
                  await ref.read(syncServiceProvider).runSync();
                },
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('مزامنة'),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Smart Sync Status Card
          const SmartSyncDashboardCard(),

          const SizedBox(height: 16),

          // Statistics Cards
          Consumer(
            builder: (context, ref, _) {
              final roomsAsync = ref.watch(roomsListProvider);

              return roomsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('خطأ: $e')),
                data: (rooms) {
                  final totalRooms = rooms.length;
                  final availableRooms = rooms
                      .where((r) => StatusUtils.isRoomAvailable(r.status))
                      .length;
                  final occupiedRooms = rooms
                      .where((r) => StatusUtils.isRoomOccupied(r.status))
                      .length;
                  final occupancyRate = totalRooms > 0
                      ? ((occupiedRooms / totalRooms) * 100).round()
                      : 0;

                  final screenWidth = MediaQuery.sizeOf(context).width;
                  final crossAxisCount = screenWidth < 360
                      ? 1
                      : screenWidth < 600
                      ? 2
                      : 3;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GridView.count(
                        crossAxisCount: crossAxisCount,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 1.5,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        children: [
                          StatCard(
                            title: 'إجمالي الغرف',
                            value: totalRooms.toString(),
                            icon: Icons.hotel,
                            color: Colors.blue,
                          ),
                          StatCard(
                            title: 'الغرف المتاحة',
                            value: availableRooms.toString(),
                            icon: Icons.hotel_outlined,
                            color: Colors.green,
                          ),
                          StatCard(
                            title: 'الغرف المحجوزة',
                            value: occupiedRooms.toString(),
                            icon: Icons.bed,
                            color: Colors.red,
                          ),
                          StatCard(
                            title: 'نسبة الإشغال',
                            value: '$occupancyRate%',
                            icon: Icons.pie_chart,
                            color: Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildRoomsStatusSection(context, rooms),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRoomsStatusSection(BuildContext context, List<Room> rooms) {
    final Map<String, Room> roomsMap = {
      for (final room in rooms) room.roomNumber: room,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'حالة الغرف',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _dashboardRoomNumbers.map((roomNumber) {
                final room = roomsMap[roomNumber];
                final bool isOccupied =
                    room != null && StatusUtils.isRoomOccupied(room.status);
                final bool isAvailable =
                    room != null && StatusUtils.isRoomAvailable(room.status);
                final Color backgroundColor = isOccupied
                    ? Colors.red.shade600
                    : (isAvailable
                          ? Colors.green.shade600
                          : Colors.grey.shade500);
                final bool useDarkText =
                    backgroundColor.computeLuminance() > 0.5;
                final Color foregroundColor = useDarkText
                    ? Colors.black
                    : Colors.white;
                final String tooltipText = room != null
                    ? room.status
                    : 'غير مسجل في النظام';

                return Tooltip(
                  message: tooltipText,
                  child: SizedBox(
                    width: 80,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: backgroundColor,
                        foregroundColor: foregroundColor,
                        minimumSize: const Size(80, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      child: Text(roomNumber),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
