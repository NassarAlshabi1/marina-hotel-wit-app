import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/repository_providers.dart';
import '../../services/daos/sync_log_dao.dart';

/// Provider لسجل المزامنة
final syncHistoryProvider = FutureProvider.family<List<SyncLogEntry>, SyncFilter>(
  (ref, filter) async {
    final db = ref.read(databaseProvider);
    final dao = SyncLogDao(db);
    return await dao.getSyncHistory(
      limit: filter.limit,
      offset: filter.offset,
      direction: filter.direction,
      status: filter.status,
    );
  },
);

/// Provider لإحصائيات المزامنة
final syncStatsProvider = FutureProvider<SyncStats>((ref) async {
  final db = ref.read(databaseProvider);
  final dao = SyncLogDao(db);
  return await dao.getSyncStats(since: DateTime.now().subtract(const Duration(days: 7)));
});

class SyncFilter {
  final int limit;
  final int offset;
  final String? direction;
  final String? status;

  const SyncFilter({
    this.limit = 50,
    this.offset = 0,
    this.direction,
    this.status,
  });
}

class SyncHistoryScreen extends ConsumerStatefulWidget {
  const SyncHistoryScreen({super.key});

  @override
  ConsumerState<SyncHistoryScreen> createState() => _SyncHistoryScreenState();
}

class _SyncHistoryScreenState extends ConsumerState<SyncHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedDirection;
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل المزامنة'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.history), text: 'السجل'),
            Tab(icon: Icon(Icons.analytics), text: 'الإحصائيات'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'تصفية',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(syncHistoryProvider),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHistoryTab(),
          _buildStatsTab(),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    final filter = SyncFilter(
      direction: _selectedDirection,
      status: _selectedStatus,
    );
    
    final logsAsync = ref.watch(syncHistoryProvider(filter));

    return logsAsync.when(
      data: (logs) {
        if (logs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_toggle_off, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'لا توجد عمليات مزامنة مسجلة',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            return _buildLogCard(log);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('خطأ: $error', style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  Widget _buildLogCard(SyncLogEntry log) {
    final isSuccess = log.status == 'success';
    final isPull = log.direction == 'pull';
    final isPush = log.direction == 'push';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSuccess ? Colors.green.shade200 : Colors.red.shade200,
            width: 1,
          ),
        ),
        child: ExpansionTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isSuccess
                  ? (isPull ? Colors.blue.shade50 : Colors.purple.shade50)
                  : Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                isSuccess
                    ? (isPull ? Icons.download : Icons.upload)
                    : Icons.error,
                color: isSuccess
                    ? (isPull ? Colors.blue : Colors.purple)
                    : Colors.red,
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  isPull ? 'سحب من السيرفر' : 'رفع إلى السيرفر',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSuccess ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isSuccess ? '✓ نجح' : '✗ فشل',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                _formatDateTime(log.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              if (log.recordsCount != null)
                Text(
                  '${log.recordsCount} سجل',
                  style: TextStyle(
                    fontSize: 12,
                    color: isPull ? Colors.blue.shade700 : Colors.purple.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('معرف العملية:', log.syncId.substring(0, 8)),
                  _buildDetailRow('الجهاز:', log.deviceId),
                  _buildDetailRow('الوجهة:', log.target ?? 'غير معروف'),
                  if (log.durationMs != null)
                    _buildDetailRow('المدة:', '${log.durationMs} مللي ثانية'),
                  if (log.completedAt != null)
                    _buildDetailRow('اكتمل:', _formatDateTime(log.completedAt!)),
                  if (log.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              log.errorMessage!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsTab() {
    final statsAsync = ref.watch(syncStatsProvider);

    return statsAsync.when(
      data: (stats) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildStatsCards(stats),
              const SizedBox(height: 24),
              _buildSuccessRateChart(stats),
              const SizedBox(height: 24),
              _buildRecordsChart(stats),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('خطأ: $error', style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  Widget _buildStatsCards(SyncStats stats) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        _buildStatCard(
          'إجمالي المزامنات',
          stats.totalSyncs.toString(),
          Icons.sync,
          Colors.blue,
        ),
        _buildStatCard(
          'نسبة النجاح',
          '${stats.successRate.toStringAsFixed(1)}%',
          Icons.check_circle,
          Colors.green,
        ),
        _buildStatCard(
          'سجول ممسوحة',
          stats.totalRecordsPulled.toString(),
          Icons.download,
          Colors.blue.shade700,
        ),
        _buildStatCard(
          'سجول مرفوعة',
          stats.totalRecordsPushed.toString(),
          Icons.upload,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessRateChart(SyncStats stats) {
    final success = stats.successfulSyncs.toDouble();
    final failed = stats.failedSyncs.toDouble();
    final total = stats.totalSyncs.toDouble();

    if (total == 0) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'نسبة نجاح المزامنة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(
                      value: success,
                      title: '${((success / total) * 100).toStringAsFixed(0)}%',
                      color: Colors.green,
                      radius: 60,
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    PieChartSectionData(
                      value: failed,
                      title: failed > 0 ? '${((failed / total) * 100).toStringAsFixed(0)}%' : '',
                      color: Colors.red,
                      radius: 50,
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('نجح', Colors.green, stats.successfulSyncs),
                const SizedBox(width: 24),
                _buildLegendItem('فشل', Colors.red, stats.failedSyncs),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordsChart(SyncStats stats) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'إحصائيات السجول',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: [stats.totalRecordsPulled, stats.totalRecordsPushed]
                      .reduce((a, b) => a > b ? a : b)
                      .toDouble() * 1.2,
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: stats.totalRecordsPulled.toDouble(),
                          color: Colors.blue,
                          width: 30,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: stats.totalRecordsPushed.toDouble(),
                          color: Colors.purple,
                          width: 30,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value == 0 ? 'مسحوبة' : 'مرفوعة',
                            style: const TextStyle(fontSize: 12),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, int count) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text('$label ($count)'),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'الآن';
    } else if (diff.inHours < 1) {
      return 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inDays < 1) {
      return 'منذ ${diff.inHours} ساعة';
    } else if (diff.inDays < 7) {
      return 'منذ ${diff.inDays} يوم';
    } else {
      return '${dateTime.year}/${dateTime.month}/${dateTime.day}';
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تصفية السجل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String?>(
                value: _selectedDirection,
                decoration: const InputDecoration(labelText: 'النوع'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('الكل')),
                  DropdownMenuItem(value: 'pull', child: Text('سحب')),
                  DropdownMenuItem(value: 'push', child: Text('رفع')),
                ],
                onChanged: (value) => setState(() => _selectedDirection = value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                value: _selectedStatus,
                decoration: const InputDecoration(labelText: 'الحالة'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('الكل')),
                  DropdownMenuItem(value: 'success', child: Text('نجح')),
                  DropdownMenuItem(value: 'failed', child: Text('فشل')),
                ],
                onChanged: (value) => setState(() => _selectedStatus = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {});
                Navigator.pop(context);
              },
              child: const Text('تطبيق'),
            ),
          ],
        );
      },
    );
  }
}
