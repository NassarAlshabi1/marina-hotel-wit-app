import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart';
import '../../services/providers.dart';
import '../../services/daos/outbox_dao.dart';
import 'sync_error_log_screen.dart';

/// ✅ Provider لحالة التحميل — يمنع Rapid Taps على الأزرار
final _isStatsActionLoadingProvider = StateProvider<bool>((ref) => false);

class AppwriteSyncStatsScreen extends ConsumerWidget {
  const AppwriteSyncStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(syncStatsProvider);
    final hasErrors = ref.watch(_syncHasErrorsProvider);

    return AppScaffold(
      title: 'إحصائيات المزامنة',
      actions: [
        // زر سجل الأخطاء مع Badge
        IconButton(
          icon: Badge(
            isLabelVisible: hasErrors,
            label: const Text('!'),
            child: const Icon(Icons.error_outline),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SyncErrorLogScreen(),
              ),
            );
          },
          tooltip: 'سجل الأخطاء',
        ),
      ],
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

  // ==================== Helper: Safe Casting ====================

  /// ✅ Type-safe extraction — يمنع runtime errors من dynamic
  int _intVal(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  double _doubleVal(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return 0.0;
  }

  // ==================== قسم Outbox والأزرار ====================

  Widget _buildOutboxAndActions(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> stats,
  ) {
    final outboxCount = _intVal(stats, 'outboxCount');
    final failedCount = _intVal(stats, 'failedCount');
    final conflictCount = _intVal(stats, 'conflictCount') +
        _intVal(stats, 'totalConflicts');
    final hasErrors = failedCount > 0 || conflictCount > 0;
    // ✅ حالة تحميل موحدة لمنع Rapid Taps
    final isActionLoading = ref.watch(_isStatsActionLoadingProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
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
                      if (hasErrors) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (failedCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$failedCount فشل',
                                  style: const TextStyle(fontSize: 12, color: Colors.red),
                                ),
                              ),
                            if (failedCount > 0 && conflictCount > 0)
                              const SizedBox(width: 8),
                            if (conflictCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$conflictCount تعارض',
                                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // زر عرض الأخطاء (يظهر فقط عند وجود أخطاء)
                if (hasErrors) ...[
                  IconButton(
                    icon: Badge(
                      label: Text('${failedCount + conflictCount}'),
                      child: const Icon(Icons.error_outline, color: Colors.red),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SyncErrorLogScreen(),
                        ),
                      );
                    },
                    tooltip: 'عرض الأخطاء',
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // ✅ زر محمي من Rapid Taps
                ElevatedButton.icon(
                  onPressed: isActionLoading ? null : () async {
                    ref.read(_isStatsActionLoadingProvider.notifier).state = true;
                    try {
                      final manager = ref.read(appwriteSyncManagerProvider);
                      await manager.sync();
                      ref.invalidate(syncStatsProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تمت إعادة المحاولة')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red),
                        );
                      }
                    } finally {
                      if (context.mounted) {
                        ref.read(_isStatsActionLoadingProvider.notifier).state = false;
                      }
                    }
                  },
                  icon: isActionLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('مزامنة الآن'),
                ),
                OutlinedButton.icon(
                  onPressed: isActionLoading ? null : () async {
                    ref.read(_isStatsActionLoadingProvider.notifier).state = true;
                    try {
                      final db = ref.read(databaseProvider);
                      final dao = OutboxDao(db);
                      await dao.resetErrors();
                      await dao.clearStale(attemptsThreshold: 3);
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
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red),
                        );
                      }
                    } finally {
                      if (context.mounted) {
                        ref.read(_isStatsActionLoadingProvider.notifier).state = false;
                      }
                    }
                  },
                  icon: const Icon(Icons.cleaning_services),
                  label: const Text('تفريغ ذكي'),
                ),
                if (hasErrors)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SyncErrorLogScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.list_alt),
                    label: const Text('سجل الأخطاء'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== قسم ملخص المزامنة ====================

  Widget _buildSummaryCard(Map<String, dynamic> stats) {
    final totalSyncs = _intVal(stats, 'totalSyncs');
    final successfulSyncs = _intVal(stats, 'successfulSyncs');
    final failedSyncs = _intVal(stats, 'failedSyncs');
    // ✅ حساب successRate آمن من Division by Zero
    final successRate = totalSyncs > 0
        ? (successfulSyncs / totalSyncs * 100)
        : 0.0;

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

  // ==================== رسم بياني لمعدل النجاح ====================

  Widget _buildSuccessRateCard(Map<String, dynamic> stats) {
    final totalSyncs = _intVal(stats, 'totalSyncs');
    final successfulSyncs = _intVal(stats, 'successfulSyncs');

    // ✅ حساب آمن من Division by Zero
    final successRate = totalSyncs > 0
        ? (successfulSyncs / totalSyncs * 100)
        : 0.0;

    // ✅ Clamp القيم لمنع قيم سالبة أو NaN
    final clampedSuccess = successRate.clamp(0.0, 100.0);
    final clampedFail = (100.0 - clampedSuccess).clamp(0.0, 100.0);

    // ✅ Empty State — لا توجد بيانات كافية
    if (totalSyncs == 0) {
      return _buildEmptyStateCard(
        icon: Icons.pie_chart_outline,
        title: 'معدل النجاح',
        message: 'لا توجد مزامنات مسجلة بعد',
        subMessage: 'قم بأول مزامنة لرؤية الإحصائيات',
      );
    }

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
              child: Semantics(
                label: 'رسم بياني دائري: معدل النجاح ${clampedSuccess.toStringAsFixed(1)}%',
                child: ExcludeSemantics(
                  child: PieChart(
                    PieChartData(
                      sections: [
                        PieChartSectionData(
                          value: clampedSuccess,
                          title: '${clampedSuccess.toStringAsFixed(1)}%',
                          color: Colors.green,
                          radius: 80,
                          titleStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        PieChartSectionData(
                          value: clampedFail,
                          title: '${clampedFail.toStringAsFixed(1)}%',
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
                    swapAnimationDuration: const Duration(milliseconds: 800),
                    swapAnimationCurve: Curves.easeInOutCubic,
                  ),
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

  // ==================== رسم بياني للبيانات المنقولة ====================

  Widget _buildDataTransferCard(Map<String, dynamic> stats) {
    final recordsPushed = _intVal(stats, 'totalRecordsPushed');
    final recordsPulled = _intVal(stats, 'totalRecordsPulled');
    final conflicts = _intVal(stats, 'totalConflicts') +
        _intVal(stats, 'conflictCount');

    // ✅ Empty State — لا توجد بيانات منقولة
    final hasData = recordsPushed > 0 || recordsPulled > 0 || conflicts > 0;
    if (!hasData) {
      return _buildEmptyStateCard(
        icon: Icons.bar_chart,
        title: 'البيانات المنقولة',
        message: 'لا توجد بيانات منقولة بعد',
        subMessage: 'ستظهر هنا بعد أول مزامنة',
      );
    }

    final maxValue = [
      recordsPushed,
      recordsPulled,
      conflicts,
    ].reduce((a, b) => a > b ? a : b);

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
              child: Semantics(
                label: 'رسم بياني: رفع $recordsPushed، تحميل $recordsPulled، تضارب $conflicts',
                child: ExcludeSemantics(
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      // ✅ maxValue آمن > 0 بسبب hasData check
                      maxY: maxValue * 1.2,
                      barTouchData: BarTouchData(enabled: true),
                      titlesData: FlTitlesData(
                        show: true,
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
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxValue / 5,
                      ),
                      borderData: FlBorderData(show: false),
                      // ✅ Helper method لتقليل التكرار
                      barGroups: [
                        BarChartGroupData(
                          x: 0,
                          barRods: [_buildBarRod(recordsPushed.toDouble(), Colors.orange)],
                        ),
                        BarChartGroupData(
                          x: 1,
                          barRods: [_buildBarRod(recordsPulled.toDouble(), Colors.purple)],
                        ),
                        BarChartGroupData(
                          x: 2,
                          barRods: [_buildBarRod(conflicts.toDouble(), Colors.amber)],
                        ),
                      ],
                    ),
                    swapAnimationDuration: const Duration(milliseconds: 800),
                    swapAnimationCurve: Curves.easeInOutCubic,
                  ),
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

  // ==================== آخر مزامنة ====================

  Widget _buildLastSyncCard(Map<String, dynamic> stats) {
    final lastSyncTime = stats['lastSyncTime'];

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

  // ==================== مكونات مساعدة ====================

  /// ✅ Empty State موحد للرسوم البيانية
  Widget _buildEmptyStateCard({
    required IconData icon,
    required String title,
    required String message,
    String? subMessage,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.grey, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Icon(icon, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                    if (subMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subMessage,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ Helper لتقليل تكرار BarChartRodData
  BarChartRodData _buildBarRod(double value, Color color) {
    return BarChartRodData(
      toY: value,
      color: color,
      width: 40,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    );
  }

  Widget _buildStatBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
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
    if (isoString == null) return '---';
    try {
      final dt = DateTime.parse(isoString);
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
    } catch (e) {
      return '---';
    }
  }

  /// ✅ _timeAgo مع التصريف العربي الصحيح
  String _timeAgo(String? isoString) {
    if (isoString == null) return '---';
    try {
      final dt = DateTime.parse(isoString);
      final diff = DateTime.now().difference(dt);

      if (diff.isNegative) return 'الآن';

      if (diff.inDays > 365) {
        return DateFormat.yMMMd('ar').format(dt);
      } else if (diff.inDays >= 30) {
        final months = (diff.inDays / 30).floor();
        return '$months ${_arabicPlural(months, 'شهر', 'شهران', 'أشهر')}';
      } else if (diff.inDays > 0) {
        return '${diff.inDays} ${_arabicPlural(diff.inDays, 'يوم', 'يومان', 'أيام')}';
      } else if (diff.inHours > 0) {
        return '${diff.inHours} ${_arabicPlural(diff.inHours, 'ساعة', 'ساعتان', 'ساعات')}';
      } else if (diff.inMinutes > 0) {
        return '${diff.inMinutes} ${_arabicPlural(diff.inMinutes, 'دقيقة', 'دقيقتان', 'دقائق')}';
      } else {
        return 'الآن';
      }
    } catch (e) {
      return '---';
    }
  }

  /// ✅ التصريف العربي الصحيح حسب العدد
  String _arabicPlural(int count, String one, String two, String few) {
    if (count == 1) return one;
    if (count == 2) return two;
    if (count >= 3 && count <= 10) return few;
    return few;
  }
}

/// ✅ Provider مشتق لمعرفة ما إذا كانت هناك أخطاء (لـ Badge)
final _syncHasErrorsProvider = Provider<bool>((ref) {
  final statsAsync = ref.watch(syncStatsProvider);
  return statsAsync.when(
    data: (stats) {
      final failed = (stats['failedCount'] as int?) ?? 0;
      final conflicts = ((stats['conflictCount'] as int?) ?? 0) +
          ((stats['totalConflicts'] as int?) ?? 0);
      return failed > 0 || conflicts > 0;
    },
    loading: () => false,
    error: (_, __) => false,
  );
});
