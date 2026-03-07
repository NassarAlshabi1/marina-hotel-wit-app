import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/core_providers.dart' as core_providers;
import '../../providers/repository_providers.dart';
import '../../services/daos/sync_log_dao.dart';
import '../../services/reports/sync_report_generator.dart';
import '../../utils/status_utils.dart';
import 'expenses_report_screen.dart';
import 'payments_report_screen.dart';
import 'debts_report_screen.dart';
import 'salary_withdrawals_report_screen.dart';
import 'income_expense_report_screen.dart';
import '../settings/sync_history_screen.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(core_providers.dbProvider);
    return AppScaffold(
      title: 'التقارير',
      actions: [
        IconButton(
          onPressed: () => ref.read(core_providers.syncProvider).runSync(),
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
            padding: const EdgeInsets.all(12),
            children: [
              const Text(
                'التقارير المالية',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
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
              const SizedBox(height: 16),
              const Text(
                'تقارير المخاطر والمتابعة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              _ReportShortcut(
                icon: Icons.pie_chart,
                label: 'تقرير الديون',
                color: Colors.purple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DebtsReportScreen()),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'تقارير النظام',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              _ReportShortcut(
                icon: Icons.sync,
                label: 'تقرير أداء المزامنة',
                color: Colors.indigo,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SyncHistoryScreen()),
                ),
              ),
              const SizedBox(height: 8),
              _ReportShortcut(
                icon: Icons.cloud_upload,
                label: 'تصدير تقرير المزامنة PDF',
                color: Colors.teal,
                onTap: () => _exportSyncReport(context, ref),
              ),
              const SizedBox(height: 24),
              const Text(
                'مؤشرات سريعة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              const Text(
                'الإشغال اليومي (آخر 7 أيام)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(
                height: 200,
                child: BarChart(BarChartData(barGroups: d['dailyOcc'])),
              ),
              const SizedBox(height: 16),
              const Text(
                'الإيرادات مقابل المصروفات (الشهر)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(
                height: 200,
                child: BarChart(BarChartData(barGroups: d['revExp'])),
              ),
              const SizedBox(height: 16),
              const Text(
                'أعلى الغرف إشغالاً',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(
                height: 200,
                child: BarChart(BarChartData(barGroups: d['topRooms'])),
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
      final busy =
          rooms.where((r) => StatusUtils.isRoomOccupied(r.status)).length;
      final occ = (busy * 100 / total).round();
      return BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(toY: occ.toDouble())],
      );
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
      final v = StatusUtils.isRoomOccupied(r.status) ? 100.0 : 20.0;
      topBars.add(
        BarChartGroupData(
          x: i,
          barRods: [BarChartRodData(toY: v)],
        ),
      );
    }

    return {'dailyOcc': daily, 'revExp': revExp, 'topRooms': topBars};
  }

  Future<void> _exportSyncReport(BuildContext context, WidgetRef ref) async {
    // إظهار مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final db = ref.read(databaseProvider);
      final dao = SyncLogDao(db);

      // جمع بيانات التقرير
      final report = await SyncReportDataProvider.gatherReportData(
        syncLogDao: dao,
        maxLogs: 100,
      );

      // إغلاق مؤشر التحميل
      if (context.mounted) Navigator.pop(context);

      // تصدير التقرير
      await SyncReportGenerator.shareReport(report: report);

      // إظهار رسالة نجاح
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء تقرير المزامنة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // إغلاق مؤشر التحميل
      if (context.mounted) Navigator.pop(context);

      // إظهار رسالة خطأ
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء التقرير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
      elevation: 1,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }
}
