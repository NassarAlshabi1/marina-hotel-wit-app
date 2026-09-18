import 'package:drift/drift.dart' hide Column;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/core_providers.dart';
import '../../providers/performance_provider.dart';
import '../../providers/repository_providers.dart';
import '../../services/crashlytics_service.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/status_utils.dart';
import 'debts_report_screen.dart';
import 'expenses_report_screen.dart';
import 'guest_payments_detail_report_screen.dart';
import 'income_expense_report_screen.dart';
import 'inventory_report_screen.dart';
import 'payments_report_screen.dart';
import 'salary_withdrawals_report_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  /// مفاتيح الـ cache لكل نوع بيانات

  /// الذاكرة المؤقتة
  Map<String, dynamic>? _cachedRooms;
  Map<String, dynamic>? _cachedFinancials;
  bool _loading = true;
  String? _loadError;

  /// RefreshableObject flag — للتحكم بإعادة التحميل
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool force = false}) async {
    if (force) {}
    setState(() {
      _loading = true;
      _loadError = null;
    });

    final db = ref.read(databaseProvider);
    final perf = ref.read(performanceProvider.notifier);

    try {
      // 1. تحميل بيانات الغرف (مع cache)
      final roomsData = await PerformanceTimer.measure(
        'reports_load_rooms',
        perf,
        () async {
          if (!force && _cachedRooms != null) {
            return _cachedRooms!;
          }
          final rooms = await db.select(db.rooms).get();
          final result = {'rooms': rooms};
          _cachedRooms = result;
          return result;
        },
        recordsProcessed: 1,
      );
      final rooms = roomsData['rooms'] as List;

      // 2. تحميل البيانات المالية (مع cache)
      final finData = await PerformanceTimer.measure(
        'reports_load_financials',
        perf,
        () async {
          if (!force && _cachedFinancials != null) {
            return _cachedFinancials!;
          }
          // ✅ إصلاح: فلترة المدفوعات باليوم الفندقي الحالي بدلاً من كل المدفوعات
          //以前: كان يجلب كل المدفوعات ويجمعها بدون فلترة تاريخ
          // الآن: يعرض فقط إيرادات ومصروفات اليوم الفندقي الحالي
          final hotelDay = HotelTimeEngine.getHotelDayKey();

          // المدفوعات: فلترة بـ hotelDayKey
          final paymentsQuery = db.select(db.payments)
            ..where((p) => p.deletedAt.isNull())
            ..where((p) => p.isVoided.equals(false))
            ..where(
              (p) =>
                  p.hotelDayKey.equals(hotelDay) |
                  (p.hotelDayKey.isNull() & p.paymentDate.like('$hotelDay%')),
            );
          final todayPayments = await paymentsQuery.get();
          double income = 0;
          for (final p in todayPayments) {
            income += p.amount;
          }

          // المصروفات: فلترة بـ hotelDayKey
          final expensesQuery = db.select(db.expenses)
            ..where((e) => e.deletedAt.isNull())
            ..where(
              (e) =>
                  e.hotelDayKey.equals(hotelDay) |
                  (e.hotelDayKey.isNull() & e.date.like('$hotelDay%')),
            );
          final todayExpenses = await expensesQuery.get();
          double expense = 0;
          for (final e in todayExpenses) {
            expense += e.amount;
          }
          final result = {'income': income, 'expense': expense};
          _cachedFinancials = result;
          return result;
        },
        recordsProcessed: 1,
      );

      // 3. بناء الرسوم البيانية
      final total = rooms.isEmpty ? 1 : rooms.length;

      final daily = List.generate(7, (i) {
        final busy = rooms
            .where((r) => StatusUtils.isRoomOccupied(r.status as String))
            .length;
        final occ = (busy * 100 / total).round().toDouble();
        return BarChartGroupData(
          x: i,
          barRods: [BarChartRodData(toY: occ, color: Colors.teal)],
        );
      });

      final revExp = [
        BarChartGroupData(
          x: 0,
          barRods: [
            BarChartRodData(
              toY: (finData['income'] as num).toDouble(),
              color: Colors.green,
            ),
          ],
        ),
        BarChartGroupData(
          x: 1,
          barRods: [
            BarChartRodData(
              toY: (finData['expense'] as num).toDouble(),
              color: Colors.red,
            ),
          ],
        ),
      ];

      final topRooms = rooms.take(5).toList();
      final topBars = <BarChartGroupData>[];
      for (var i = 0; i < topRooms.length; i++) {
        final r = topRooms[i];
        final v = StatusUtils.isRoomOccupied(r.status as String) ? 100.0 : 20.0;
        topBars.add(
          BarChartGroupData(
            x: i,
            barRods: [BarChartRodData(toY: v, color: Colors.blue)],
          ),
        );
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = null;
          // تخزين البيانات المعالجة للاستخدام في build
          _chartData = {
            'dailyOcc': daily,
            'revExp': revExp,
            'topRooms': topBars,
            'income': finData['income'],
            'expense': finData['expense'],
          };
        });
      }
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'ReportsScreen',
        action: 'loadData',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.warning,
        extra: {'forceRefresh': '$force'},
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'تعذر تحميل مؤشرات التقارير. حاول التحديث مرة أخرى.';
        });
      }
    }
  }

  Map<String, dynamic> _chartData = {};

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'التقارير',
      actions: [
        IconButton(
          onPressed: () => _loadData(force: true),
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث',
        ),
        IconButton(
          onPressed: () => ref.read(syncProvider).runSync(),
          icon: const Icon(Icons.sync),
          tooltip: 'مزامنة',
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_loadError != null && _chartData.isEmpty)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EmptyState(
                      title: 'تعذر تحميل التقارير',
                      subtitle: _loadError,
                      icon: Icons.error_outline,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => _loadData(force: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                // ─── التقارير المالية ───
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
                  onTap: () => _navigate((_) => const PaymentsReportScreen()),
                ),
                const SizedBox(height: 4),
                _ReportShortcut(
                  icon: Icons.assignment,
                  label: 'تقرير تفصيلي - الأيام والمدفوعات',
                  color: Colors.indigo,
                  onTap: () =>
                      _navigate((_) => const GuestPaymentsDetailReportScreen()),
                ),
                const SizedBox(height: 4),
                _ReportShortcut(
                  icon: Icons.account_balance_wallet,
                  label: 'تقرير المصروفات',
                  color: Colors.orange,
                  onTap: () => _navigate((_) => const ExpensesReportScreen()),
                ),
                const SizedBox(height: 4),
                _ReportShortcut(
                  icon: Icons.stacked_line_chart,
                  label: 'تقرير الدخل والخرج',
                  color: Colors.teal,
                  onTap: () =>
                      _navigate((_) => const IncomeExpenseReportScreen()),
                ),
                const SizedBox(height: 4),
                _ReportShortcut(
                  icon: Icons.payments_outlined,
                  label: 'تقرير سحبيات الرواتب',
                  color: Colors.blue,
                  onTap: () =>
                      _navigate((_) => const SalaryWithdrawalsReportScreen()),
                ),
                const SizedBox(height: 4),
                _ReportShortcut(
                  icon: Icons.inventory_2_outlined,
                  label: 'التقرير المخزني',
                  color: Colors.brown,
                  onTap: () => _navigate((_) => const InventoryReportScreen()),
                ),
                const SizedBox(height: 10),

                // ─── تقارير المخاطر والمتابعة ───
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
                  onTap: () => _navigate((_) => const DebtsReportScreen()),
                ),
                const SizedBox(height: 14),

                // ─── مؤشرات سريعة ───
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'مؤشرات سريعة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),

                // ملخص مالي سريع
                _buildQuickFinancialSummary(),
                const SizedBox(height: 12),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'الإشغال اليومي (آخر 7 أيام)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                ),
                SizedBox(
                  height: 150,
                  child: BarChart(
                    BarChartData(
                      barGroups:
                          _chartData['dailyOcc'] as List<BarChartGroupData>? ??
                          [],
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                    ),
                  ),
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
                  child: BarChart(
                    BarChartData(
                      barGroups:
                          _chartData['revExp'] as List<BarChartGroupData>? ??
                          [],
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                    ),
                  ),
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
                  child: BarChart(
                    BarChartData(
                      barGroups:
                          _chartData['topRooms'] as List<BarChartGroupData>? ??
                          [],
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// ملخص مالي سريع (إيرادات - مصروفات - صافي) لليوم الفندقي الحالي
  Widget _buildQuickFinancialSummary() {
    final income = (_chartData['income'] as num?)?.toDouble() ?? 0;
    final expense = (_chartData['expense'] as num?)?.toDouble() ?? 0;
    final net = income - expense;
    // عرض تاريخ اليوم الفندقي الحالي
    final hotelDay = HotelTimeEngine.getHotelDayKey();

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // عنوان اليوم الفندقي
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.today, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  'اليوم الفندقي: $hotelDay',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _buildFinIndicator('الإيرادات', income, Colors.green),
                ),
                Container(width: 1, height: 36, color: Colors.grey.shade200),
                Expanded(
                  child: _buildFinIndicator('المصروفات', expense, Colors.red),
                ),
                Container(width: 1, height: 36, color: Colors.grey.shade200),
                Expanded(
                  child: _buildFinIndicator(
                    'صافي',
                    net,
                    net >= 0 ? Colors.teal : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinIndicator(String label, double value, Color color) {
    final fmt = NumberFormat('#,##0', 'en_US');
    return Column(
      children: [
        Text(
          fmt.format(value),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  /// التنقل بأسلوب lazy — الـ WidgetBuilder لا يُنفذ إلا عند التنقل الفعلي
  void _navigate(WidgetBuilder builder) {
    Navigator.push<void>(context, MaterialPageRoute(builder: builder));
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
      margin: const EdgeInsets.symmetric(vertical: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        onTap: onTap,
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 14,
          color: Colors.grey,
        ),
      ),
    );
  }
}
