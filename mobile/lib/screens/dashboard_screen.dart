import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_db.dart';
import '../services/providers.dart';
import '../services/sync_service.dart';
import '../utils/status_utils.dart';
import '../widgets/smart_sync_widgets.dart';

const List<String> _dashboardRoomNumbers = [
  '101', '102', '103', '104',
  '201', '202', '203', '204',
  '301', '302', '303', '304',
  '401', '402', '403', '404',
  '501', '502',
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
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
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
          
          // Statistics Cards - بطاقات أصغر مع إحصائيات مفيدة أكثر
          _buildStatisticsCards(ref),
          
          const SizedBox(height: 24),
          
          // Rooms Status Section
          Consumer(
            builder: (context, ref, _) {
              final roomsAsync = ref.watch(roomsListProvider);

              return roomsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('خطأ: $e')),
                data: (rooms) => _buildRoomsStatusSection(context, rooms),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCards(WidgetRef ref) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.0, // تصغير البطاقات
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        // نسبة الإشغال
        Consumer(
          builder: (context, ref, _) {
            final roomsAsync = ref.watch(roomsListProvider);
            return roomsAsync.when(
              loading: () => const _LoadingStatCard(
                title: 'نسبة الإشغال',
                icon: Icons.pie_chart,
                color: Colors.orange,
              ),
              error: (e, _) => _StatCard(
                title: 'نسبة الإشغال',
                value: 'خطأ',
                icon: Icons.pie_chart,
                color: Colors.orange,
              ),
              data: (rooms) {
                final totalRooms = rooms.length;
                final occupiedRooms = rooms.where((r) => StatusUtils.isRoomOccupied(r.status)).length;
                final occupancyRate = totalRooms > 0 ? ((occupiedRooms / totalRooms) * 100).round() : 0;
                return _StatCard(
                  title: 'نسبة الإشغال',
                  value: '$occupancyRate%',
                  icon: Icons.pie_chart,
                  color: Colors.orange,
                );
              },
            );
          },
        ),

        // المدفوعات اليومية
        Consumer(
          builder: (context, ref, _) {
            final paymentsAsync = ref.watch(todayPaymentsProvider);
            return paymentsAsync.when(
              loading: () => const _LoadingStatCard(
                title: 'مدفوعات اليوم',
                icon: Icons.payments,
                color: Colors.green,
              ),
              error: (e, _) => const _StatCard(
                title: 'مدفوعات اليوم',
                value: 'خطأ',
                icon: Icons.payments,
                color: Colors.green,
              ),
              data: (total) => _StatCard(
                title: 'مدفوعات اليوم',
                value: '${total.toStringAsFixed(0)}',
                icon: Icons.payments,
                color: Colors.green,
              ),
            );
          },
        ),

        // المصروفات اليومية
        Consumer(
          builder: (context, ref, _) {
            final expensesAsync = ref.watch(todayExpensesProvider);
            return expensesAsync.when(
              loading: () => const _LoadingStatCard(
                title: 'مصروفات اليوم',
                icon: Icons.money_off,
                color: Colors.red,
              ),
              error: (e, _) => const _StatCard(
                title: 'مصروفات اليوم',
                value: 'خطأ',
                icon: Icons.money_off,
                color: Colors.red,
              ),
              data: (total) => _StatCard(
                title: 'مصروفات اليوم',
                value: '${total.toStringAsFixed(0)}',
                icon: Icons.money_off,
                color: Colors.red,
              ),
            );
          },
        ),

        // الغرف المحجوزة
        Consumer(
          builder: (context, ref, _) {
            final roomsAsync = ref.watch(roomsListProvider);
            return roomsAsync.when(
              loading: () => const _LoadingStatCard(
                title: 'الغرف المحجوزة',
                icon: Icons.bed,
                color: Colors.blue,
              ),
              error: (e, _) => const _StatCard(
                title: 'الغرف المحجوزة',
                value: 'خطأ',
                icon: Icons.bed,
                color: Colors.blue,
              ),
              data: (rooms) {
                final occupiedRooms = rooms.where((r) => StatusUtils.isRoomOccupied(r.status)).length;
                return _StatCard(
                  title: 'الغرف المحجوزة',
                  value: occupiedRooms.toString(),
                  icon: Icons.bed,
                  color: Colors.blue,
                );
              },
            );
          },
        ),
      ],
    );
  }
  
  Widget _buildRoomsStatusSection(BuildContext context, List<Room> rooms) {
    final Map<String, Room> roomsMap = {for (final room in rooms) room.roomNumber: room};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'حالة الغرف',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8, // تقليل المسافات
              runSpacing: 8,
              children: _dashboardRoomNumbers.map((roomNumber) {
                final room = roomsMap[roomNumber];
                final bool isOccupied = room != null && StatusUtils.isRoomOccupied(room.status);
                final bool isAvailable = room != null && StatusUtils.isRoomAvailable(room.status);
                final Color backgroundColor = isOccupied
                    ? Colors.red.shade600
                    : (isAvailable ? Colors.green.shade600 : Colors.grey.shade500);
                final bool useDarkText = backgroundColor.computeLuminance() > 0.5;
                final Color foregroundColor = useDarkText ? Colors.black : Colors.white;
                final String tooltipText = room != null ? room.status : 'غير مسجل في النظام';

                return Tooltip(
                  message: tooltipText,
                  child: SizedBox(
                    width: 60, // تصغير الأزرار
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: backgroundColor,
                        foregroundColor: foregroundColor,
                        minimumSize: const Size(60, 40), // تصغير الحجم
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14, // تصغير الخط
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

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12), // تقليل padding
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color), // تصغير الأيقونة
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16, // تصغير الخط
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12, // تصغير الخط
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingStatCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  
  const _LoadingStatCard({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}