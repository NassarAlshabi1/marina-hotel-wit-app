import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/core_providers.dart' as coreProviders;

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(coreProviders.dbProvider);
    return AppScaffold(
      title: 'التقارير',
      actions: [IconButton(onPressed: () => ref.read(coreProviders.syncProvider).runSync(), icon: const Icon(Icons.sync))],
      body: FutureBuilder(
        future: _prepareData(db),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final d = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text('الإشغال اليومي (آخر 7 أيام)', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 200, child: BarChart(BarChartData(barGroups: d['dailyOcc']))),
              const SizedBox(height: 16),
              const Text('الإيرادات مقابل المصروفات (الشهر)', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 200, child: BarChart(BarChartData(barGroups: d['revExp']))),
              const SizedBox(height: 16),
              const Text('أعلى الغرف إشغالاً', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 200, child: BarChart(BarChartData(barGroups: d['topRooms']))),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _prepareData(db) async {
    final rooms = await db.select(db.rooms).get();
    final total = rooms.length == 0 ? 1 : rooms.length;

    // dummy last 7 days occupancy by current status
    final daily = List.generate(7, (i) {
      final busy = rooms.where((r) => r.status == 'محجوزة').length;
      final occ = (busy * 100 / total).round();
      return BarChartGroupData(x: i, barRods: [BarChartRodData(toY: occ.toDouble())]);
    });

    // month revenue vs expense: placeholder from local
    final incomes = await db.select(db.cashTransactions).get();
    double income = 0;
    for (final i in incomes) {
      income += i.amount;
    }
    final expenses = await db.select(db.expenses).get();
    double expense = 0;
    for (final e in expenses) {
      expense += e.amount;
    }
    final revExp = [
      BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: income)]),
      BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: expense)]),
    ];

    // top rooms by occupancy (approx by status)
    final topRooms = rooms.take(5).toList();
    final topBars = <BarChartGroupData>[];
    for (var i = 0; i < topRooms.length; i++) {
      final r = topRooms[i];
      final v = r.status == 'محجوزة' ? 100.0 : 20.0;
      topBars.add(BarChartGroupData(x: i, barRods: [BarChartRodData(toY: v)]));
    }

    return {'dailyOcc': daily, 'revExp': revExp, 'topRooms': topBars};
  }
}
