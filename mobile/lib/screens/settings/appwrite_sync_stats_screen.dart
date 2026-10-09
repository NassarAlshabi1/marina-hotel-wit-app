import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/providers.dart';

class AppwriteSyncStatsScreen extends ConsumerWidget {
  const AppwriteSyncStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(syncStatsProvider);

    return AppScaffold(
      title: 'إحصائيات المزامنة',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(syncStatsProvider);
        },
        child: statsAsync.when(
          data: (stats) => _buildContent(context, ref, stats),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'خطأ في تحميل الإحصائيات',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> stats,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOutboxAndActions(context, ref, stats),
        const SizedBox(height: 16),
        _buildSummaryCard(stats),
        const SizedBox(height: 16),

        // رسم بياني لمعدل النجاح
        _buildSuccessRateCard(stats),
        const SizedBox(height: 16),

        // رسم بياني للبيانات المنقولة
        _buildDataTransferCard(stats),
        const SizedBox(height: 16),

        _buildLastSyncCard(stats),
      ],
    );
  }

  Widget _buildOutboxAndActions(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> stats,
  ) {
    final outboxCount = stats['outboxCount'] ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Outbox',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$outboxCount عنصر قيد الإرسال',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () async {
                final manager = ref.read(appwriteSyncManagerProvider);
                await manager.sync();
                ref.invalidate(syncStatsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تمت إعادة المحاولة')),
                  );
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة محاولة'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final db = ref.read(databaseProvider);
                final dao = OutboxDao(db);
                await dao.resetErrors();
                await dao.clearStale();
                ref.invalidate(syncStatsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'تفريغ ذكي: تم تهيئة المحاولات وحذف العناصر القديمة',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.cleaning_services),
              label: const Text('تفريغ ذكي'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> stats) {
    final totalSyncs = stats['totalSyncs'] ?? 0;
    final successfulSyncs = stats['successfulSyncs'] ?? 0;
    final failedSyncs = stats['failedSyncs'] ?? 0;
    final successRate = stats['successRate'] ?? 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bar_chart, color: Colors.blue, size: 24),
                SizedBox(width: 8),
                Text(
                  'ملخص المزامنة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            // الصف الأول
            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    'إجمالي المزامنات',
                    '$totalSyncs',
                    Icons.sync_alt,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatBox(
                    'معدل النجاح',
                    '${successRate.toStringAsFixed(1)}%',
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // الصف الثاني
            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    'المزامنات الناجحة',
                    '$successfulSyncs',
                    Icons.check,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatBox(
                    'المزامنات الفاشلة',
                    '$failedSyncs',
                    Icons.error,
                    Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessRateCard(Map<String, dynamic> stats) {
    final successRate = (stats['successRate'] ?? 0.0) as double;
    final failRate = 100 - successRate;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.pie_chart, color: Colors.green, size: 24),
                SizedBox(width: 8),
                Text(
                  'معدل النجاح',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 24),

            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(
                      value: successRate,
                      title: '${successRate.toStringAsFixed(1)}%',
                      color: Colors.green,
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      value: failRate,
                      title: '${failRate.toStringAsFixed(1)}%',
                      color: Colors.red,
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                  sectionsSpace: 2,
                  centerSpaceRadius: 0,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // الأسطورة
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('نجح', Colors.green),
                const SizedBox(width: 24),
                _buildLegendItem('فشل', Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTransferCard(Map<String, dynamic> stats) {
    final recordsPushed = (stats['totalRecordsPushed'] as num?)?.toInt() ?? 0;
    final recordsPulled = (stats['totalRecordsPulled'] as num?)?.toInt() ?? 0;
    final conflicts = (stats['totalConflicts'] as num?)?.toInt() ?? 0;

    final maxValue = [
      recordsPushed,
      recordsPulled,
      conflicts,
    ].reduce((a, b) => a > b ? a : b).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.swap_vert, color: Colors.purple, size: 24),
                SizedBox(width: 8),
                Text(
                  'البيانات المنقولة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 24),

            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxValue > 0 ? maxValue * 1.2 : 10,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          switch (value.toInt()) {
                            case 0:
                              return const Text(
                                'رفع',
                                style: TextStyle(fontSize: 12),
                              );
                            case 1:
                              return const Text(
                                'تحميل',
                                style: TextStyle(fontSize: 12),
                              );
                            case 2:
                              return const Text(
                                'تضارب',
                                style: TextStyle(fontSize: 12),
                              );
                            default:
                              return const Text('');
                          }
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                  ),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maxValue > 0 ? maxValue / 5 : 1,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: recordsPushed.toDouble(),
                          color: Colors.orange,
                          width: 40,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: recordsPulled.toDouble(),
                          color: Colors.purple,
                          width: 40,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 2,
                      barRods: [
                        BarChartRodData(
                          toY: conflicts.toDouble(),
                          color: Colors.amber,
                          width: 40,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // تفاصيل الأرقام
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDataItem(
                  'رفع',
                  recordsPushed,
                  Icons.upload,
                  Colors.orange,
                ),
                _buildDataItem(
                  'تحميل',
                  recordsPulled,
                  Icons.download,
                  Colors.purple,
                ),
                _buildDataItem('تضارب', conflicts, Icons.warning, Colors.amber),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastSyncCard(Map<String, dynamic> stats) {
    final lastSyncTime = stats['lastSyncTime'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.history, color: Colors.teal, size: 24),
                SizedBox(width: 8),
                Text(
                  'آخر مزامنة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            if (lastSyncTime != null) ...[
              _buildInfoRow(
                'الوقت',
                _formatDateTime(lastSyncTime),
                Icons.access_time,
              ),
              _buildInfoRow('منذ', _timeAgo(lastSyncTime), Icons.schedule),
            ] else ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'لم تتم أي مزامنة بعد',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _buildDataItem(String label, int value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null) {
      return '---';
    }
    try {
      final dt = DateTime.parse(isoString);
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
    } catch (e) {
      return '---';
    }
  }

  String _timeAgo(String? isoString) {
    if (isoString == null) {
      return '---';
    }
    try {
      final dt = DateTime.parse(isoString);
      final diff = DateTime.now().difference(dt);

      if (diff.inDays > 0) {
        return '${diff.inDays} يوم';
      } else if (diff.inHours > 0) {
        return '${diff.inHours} ساعة';
      } else if (diff.inMinutes > 0) {
        return '${diff.inMinutes} دقيقة';
      } else {
        return 'الآن';
      }
    } catch (e) {
      return '---';
    }
  }
}
