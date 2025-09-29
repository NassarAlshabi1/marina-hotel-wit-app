import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/providers.dart';
import '../services/sync_service.dart';
import '../utils/theme.dart';

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
          
          // Statistics Cards
          Consumer(
            builder: (context, ref, _) {
              final roomsAsync = ref.watch(roomsListProvider);
              final bookingsAsync = ref.watch(bookingsListProvider);
              
              return roomsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('خطأ: $e')),
                data: (rooms) {
                  final totalRooms = rooms.length;
                  final availableRooms = rooms.where((r) => r.status == 'شاغرة').length;
                  final occupiedRooms = rooms.where((r) => r.status == 'محجوزة').length;
                  final occupancyRate = totalRooms > 0 ? ((occupiedRooms / totalRooms) * 100).round() : 0;
                  
                  final currentGuests = bookingsAsync.asData?.value
                      .where((b) => b.status == 'نشط').length ?? 0;
                  
                  return Column(
                    children: [
                      // Statistics Grid
                      GridView.count(
                        crossAxisCount: 2,
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
                    ],
                  );
                },
              );
            },
          ),
          
          const SizedBox(height: 32),
          
          // Recent activity section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'النشاط الحديث',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRecentActivityItem(
                    'حجوزات جديدة',
                    'تم إضافة 3 حجوزات جديدة اليوم',
                    Icons.assignment,
                    Colors.green,
                  ),
                  const Divider(),
                  _buildRecentActivityItem(
                    'مدفوعات مستلمة',
                    'تم استلام دفعات بقيمة 15000 ريال',
                    Icons.payment,
                    Colors.blue,
                  ),
                  const Divider(),
                  _buildRecentActivityItem(
                    'غرف تم تسجيل المغادرة',
                    'تم تسجيل مغادرة 2 حجز اليوم',
                    Icons.logout,
                    Colors.orange,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Quick actions section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إجراءات سريعة',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _buildQuickActionButton(
                        'حجز جديد',
                        Icons.add,
                        Colors.green,
                        () => {},
                      ),
                      _buildQuickActionButton(
                        'إدارة الغرف',
                        Icons.bed,
                        Colors.blue,
                      ),
                      _buildQuickActionButton(
                        'إدارة المدفوعات',
                        Icons.payment,
                        Colors.orange,
                      ),
                      _buildQuickActionButton(
                        'التقارير',
                        Icons.bar_chart,
                        Colors.purple,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRecentActivityItem(
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      contentPadding: EdgeInsets.zero,
    );
  }
  
  Widget _buildQuickActionButton(
    String title,
    IconData icon,
    Color color,
    [VoidCallback? onTap]
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
          color: color.withOpacity(0.05),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

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
              style: const TextStyle(
                fontSize: 14,
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