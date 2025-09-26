import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/app_scaffold.dart';
import '../services/providers.dart';
import '../services/sync_service.dart';
import '../services/local_db.dart';
import 'rooms/rooms_dashboard.dart';
import 'notes/notes_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      title: 'لوحة التحكم',
      actions: [
        IconButton(
          onPressed: () async {
            // run sync
            await ref.read(syncServiceProvider).runSync();
          },
          icon: const Icon(Icons.sync),
          tooltip: 'مزامنة',
        )
      ],
      body: Consumer(builder: (context, ref, _) {
        final roomsAsync = ref.watch(roomsListProvider);
        final cashAsync = ref.watch(cashTransactionsListProvider);
        final expensesAsync = ref.watch(expensesListProvider);
        return roomsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('خطأ: $e')),
          data: (rooms) {
            final total = rooms.length;
            final busy = rooms.where((r) => r.status == 'محجوزة').length;
            final free = total - busy;
            final occupancy = total == 0 ? 0 : ((busy * 100) / total).round();
            double incomeMonth = 0;
            cashAsync.asData?.value.forEach((t) {
              if (t.transactionType == 'income') incomeMonth += t.amount;
            });
            double expenseMonth = 0;
            expensesAsync.asData?.value.forEach((e) => expenseMonth += e.amount);
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // بطاقات الإحصائيات
                _buildStatsSection(occupancy, busy, free, incomeMonth, expenseMonth),
                
                const SizedBox(height: 20),
                
                // قسم الغرف المختصر
                _buildRoomsSummarySection(context, rooms),
                
                const SizedBox(height: 20),
                
                // أزرار التنقل السريع
                _buildQuickActionsSection(context),
              ],
            );
          },
        );
      }),
    );
  }

  Future<Map<String, dynamic>> _loadKpis(db) async {
    final rooms = await db.select(db.rooms).get();
    final total = rooms.length;
    final busy = rooms.where((r) => r.status == 'محجوزة').length;
    final free = total - busy;
    final occupancy = total == 0 ? 0 : ((busy * 100) / total).round();

    final now = DateTime.now();
    final ym = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

    final incomes = await (db.select(db.cashTransactions)
          ..where((t) => t.transactionType.equals('income')))
        .get();
    final expenses = await (db.select(db.expenses)).get();

    double incomeMonth = 0;
    for (final i in incomes) {
      if (i.transactionTime.startsWith(ym)) incomeMonth += i.amount;
    }
    double expenseMonth = 0;
    for (final e in expenses) {
      if (e.date.startsWith(ym)) expenseMonth += e.amount;
    }

    return {
      'occupancyPct': occupancy,
      'busyRooms': busy,
      'freeRooms': free,
      'incomeMonth': incomeMonth.toStringAsFixed(2),
      'expenseMonth': expenseMonth.toStringAsFixed(2),
    };
  }

  Widget _buildStatsSection(int occupancy, int busy, int free, double incomeMonth, double expenseMonth) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إحصائيات اليوم',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _kpiCard('نسبة الإشغال', '$occupancy%', Icons.pie_chart)),
                const SizedBox(width: 8),
                Expanded(child: _kpiCard('محجوزة', '$busy', Icons.hotel, Colors.red)),
                const SizedBox(width: 8),
                Expanded(child: _kpiCard('شاغرة', '$free', Icons.hotel_outlined, Colors.green)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _kpiCard('الإيرادات', incomeMonth.toStringAsFixed(0), Icons.trending_up, Colors.green)),
                const SizedBox(width: 8),
                Expanded(child: _kpiCard('المصروفات', expenseMonth.toStringAsFixed(0), Icons.trending_down, Colors.red)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, [Color? color]) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (color ?? Colors.blue).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (color ?? Colors.blue).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color ?? Colors.blue, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.blue,
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRoomsSummarySection(BuildContext context, List<Room> rooms) {
    if (rooms.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.hotel, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              const Text('لا توجد غرف مسجلة'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pushNamed('/rooms'),
                child: const Text('إضافة غرف'),
              ),
            ],
          ),
        ),
      );
    }

    // تنظيم الغرف حسب الطوابق
    final Map<String, List<Room>> floorMap = {};
    for (final room in rooms) {
      String floorNumber = room.roomNumber.isNotEmpty ? room.roomNumber[0] : '0';
      floorMap.putIfAbsent(floorNumber, () => []).add(room);
    }

    final sortedFloors = floorMap.keys.toList()..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'حالة الغرف',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const RoomsDashboard()),
                  ),
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...sortedFloors.take(3).map((floor) => _buildFloorSummary(floor, floorMap[floor]!)),
            if (sortedFloors.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    '... و ${sortedFloors.length - 3} طوابق أخرى',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloorSummary(String floorNumber, List<Room> rooms) {
    final available = rooms.where((r) => r.status == 'شاغرة').length;
    final occupied = rooms.length - available;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.apartment, color: Colors.blue, size: 20),
          const SizedBox(width: 8),
          Text('الطابق $floorNumber', style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          _buildSmallChip('محجوزة', occupied, Colors.red),
          const SizedBox(width: 4),
          _buildSmallChip('شاغرة', available, Colors.green),
        ],
      ),
    );
  }

  Widget _buildSmallChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildQuickActionsSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إجراءات سريعة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildQuickActionButton(
                    context,
                    'حجز جديد',
                    Icons.add_box,
                    Colors.green,
                    () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const RoomsDashboard()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildQuickActionButton(
                    context,
                    'عرض الحجوزات',
                    Icons.list_alt,
                    Colors.blue,
                    () => Navigator.of(context).pushNamed('/bookings'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildQuickActionButton(
                    context,
                    'الملاحظات',
                    Icons.note_alt,
                    Colors.indigo,
                    () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const NotesScreen()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildQuickActionButton(
                    context,
                    'إدارة الغرف',
                    Icons.hotel,
                    Colors.orange,
                    () => Navigator.of(context).pushNamed('/rooms'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildQuickActionButton(
                    context,
                    'التقارير',
                    Icons.assessment,
                    Colors.purple,
                    () => Navigator.of(context).pushNamed('/reports'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildQuickActionButton(
                    context,
                    'الإعدادات',
                    Icons.settings,
                    Colors.grey,
                    () => Navigator.of(context).pushNamed('/settings'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
