import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../utils/status_utils.dart';
import 'expenses_report_screen.dart';
import 'payments_report_screen.dart';
import 'debts_report_screen.dart';
import 'salary_withdrawals_report_screen.dart';
import 'income_expense_report_screen.dart';
import 'guest_payments_detail_report_screen.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(coreProviders.dbProvider);
    return AppScaffold(
      title: 'التقارير',
      actions: [
        IconButton(
          onPressed: () => ref.read(coreProviders.syncProvider).runSync(),
          icon: const Icon(Icons.sync),
        ),
      ],
      body: FutureBuilder(
        future: _prepareData(db),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'التقارير المالية',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(height: 6),
              _ReportShortcut(
                icon: Icons.receipt_long,
                label: 'تقرير دفوعات النزلاء',
                color: Colors.green,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PaymentsReportScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _ReportShortcut(
                icon: Icons.assignment,
                label: 'تقرير تفصيلي - الأيام والمدفوعات',
                color: Colors.indigo,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const GuestPaymentsDetailReportScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _ReportShortcut(
                icon: Icons.account_balance_wallet,
                label: 'تقرير المصروفات',
                color: Colors.orange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ExpensesReportScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _ReportShortcut(
                icon: Icons.stacked_line_chart,
                label: 'تقرير الدخل والخرج',
                color: Colors.teal,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const IncomeExpenseReportScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _ReportShortcut(
                icon: Icons.payments_outlined,
                label: 'تقرير سحبيات الرواتب',
                color: Colors.blue,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SalaryWithdrawalsReportScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'تقارير المخاطر والمتابعة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(height: 6),
              _ReportShortcut(
                icon: Icons.pie_chart,
                label: 'تقرير الديون',
                color: Colors.purple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DebtsReportScreen()),
                ),
              ),
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'مؤشرات سريعة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'الإشغال اليومي (آخر 7 أيام)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ),
              SizedBox(
                height: 150,
                child: BarChart(BarChartData(barGroups: d['dailyOcc'] as List<BarChartGroupData>?)),
              ),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'الإيرادات مقابل المصروفات (الشهر)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ),
              SizedBox(
                height: 150,
                child: BarChart(BarChartData(barGroups: d['revExp'] as List<BarChartGroupData>?)),
              ),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'أعلى الغرف إشغالاً',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ),
              SizedBox(
                height: 150,
                child: BarChart(BarChartData(barGroups: d['topRooms'] as List<BarChartGroupData>?)),
              ),
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
      final busy = rooms
          .where((r) => StatusUtils.isRoomOccupied(r.status as String))
          .length;
      final occ = ((busy as int) * 100 / (total as int)).round().toDouble();
      return BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(toY: occ)],
      );
    });

    // month revenue vs expense: placeholder from local
    final incomes = await db.select(db.cashTransactions).get();
    double income = 0;
    for (final i in incomes as List) {
      income += (i.amount as num).toDouble();
    }
    final expenses = await db.select(db.expenses).get();
    double expense = 0;
    for (final e in expenses as List) {
      expense += (e.amount as num).toDouble();
    }
    final revExp = [
      BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: income)]),
      BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: expense)]),
    ];

    // top rooms by occupancy (approx by status)
    final topRooms = rooms.take(5).toList();
    final topBars = <BarChartGroupData>[];
    for (var i = 0; i < (topRooms as List).length; i++) {
      final r = topRooms[i];
      final v = StatusUtils.isRoomOccupied(r.status as String) ? 100.0 : 20.0;
      topBars.add(
        BarChartGroupData(
          x: i,
          barRods: [BarChartRodData(toY: v)],
        ),
      );
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
      elevation: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        onTap: onTap,
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      ),
    );
  }
}
