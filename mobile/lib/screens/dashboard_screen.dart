import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/app_scaffold.dart';
import '../services/providers.dart';
import '../services/sync_service.dart';

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
                _kpiCard('نسبة الإشغال اليوم', '$occupancy%'),
                _kpiCard('الغرف المحجوزة', '$busy'),
                _kpiCard('الغرف الشاغرة', '$free'),
                _kpiCard('إيرادات الشهر', incomeMonth.toStringAsFixed(2)),
                _kpiCard('مصروفات الشهر', expenseMonth.toStringAsFixed(2)),
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

  Widget _kpiCard(String title, String value) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
