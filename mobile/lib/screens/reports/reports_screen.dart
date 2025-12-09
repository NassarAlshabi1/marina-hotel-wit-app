import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../constants/status_constants.dart';
import '../../providers/core_providers.dart' as coreProviders;
import 'expenses_report_screen.dart';
import 'payments_report_screen.dart';
import 'debts_report_screen.dart';
import 'salary_withdrawals_report_screen.dart';
import 'income_expense_report_screen.dart';

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
              const Text('التقارير التفصيلية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final shortcuts = [
                    _ReportShortcut(
                      icon: Icons.receipt_long,
                      label: 'تقرير دفوعات النزلاء',
                      color: Colors.green,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PaymentsReportScreen()),
                      ),
                    ),
                    _ReportShortcut(
                      icon: Icons.pie_chart,
                      label: 'تقرير الديون',
                      color: Colors.purple,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DebtsReportScreen()),
                      ),
                    ),
                    _ReportShortcut(
                      icon: Icons.account_balance_wallet,
                      label: 'تقرير المصروفات',
                      color: Colors.orange,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ExpensesReportScreen()),
                      ),
                    ),
                    _ReportShortcut(
                      icon: Icons.payments_outlined,
                      label: 'تقرير سحبيات الرواتب',
                      color: Colors.blue,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SalaryWithdrawalsReportScreen()),
                      ),
                    ),
                    _ReportShortcut(
                      icon: Icons.stacked_line_chart,
                      label: 'تقرير الدخل والخرج',
                      color: Colors.teal,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const IncomeExpenseReportScreen()),
                      ),
                    ),
                  ];

                  if (shortcuts.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final rows = <Widget>[];
                  for (int i = 0; i < shortcuts.length; i += 2) {
                    final first = shortcuts[i];
                    final second = i + 1 < shortcuts.length ? shortcuts[i + 1] : null;
                    rows.add(
                      Row(
                        children: [
                          Expanded(child: first),
                          const SizedBox(width: 12),
                          Expanded(child: second ?? const SizedBox()),
                        ],
                      ),
                    );
                    if (i + 2 < shortcuts.length) {
                      rows.add(const SizedBox(height: 12));
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
                  );
                },
              ),
              const SizedBox(height: 24),
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
      final busy = rooms.where((r) => r.status == RoomStatus.occupied).length;
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
      final v = r.status == RoomStatus.occupied ? 100.0 : 20.0;
      topBars.add(BarChartGroupData(x: i, barRods: [BarChartRodData(toY: v)]));
    }

    return {'dailyOcc': daily, 'revExp': revExp, 'topRooms': topBars};
  }
}

class _ReportShortcut extends StatelessWidget {
  const _ReportShortcut({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 32, color: color),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
