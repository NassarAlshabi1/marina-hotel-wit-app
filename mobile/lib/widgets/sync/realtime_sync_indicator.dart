import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/service_providers.dart';
import '../../services/sync_health_monitor.dart';

/// مؤشر مزامنة حضي متقدم يعرض:
/// - شريط تقدم حي مع إحصائيات
/// - سرعة المزامنة والوقت المتبقي
/// - عدد السجلات المرفوعة/المسحوبة
/// - حالة الاتصال والأخطاء
class RealtimeSyncIndicator extends ConsumerStatefulWidget {
  const RealtimeSyncIndicator({
    super.key,
    this.compact = false,
    this.showDetailedStats = true,
  });

  /// إذا كانت true، عرض مؤشر صغير جداً (للـ app bar)
  final bool compact;

  /// إذا كانت true، عرض إحصائيات مفصلة
  final bool showDetailedStats;

  @override
  ConsumerState<RealtimeSyncIndicator> createState() =>
      _RealtimeSyncIndicatorState();
}

class _RealtimeSyncIndicatorState extends ConsumerState<RealtimeSyncIndicator>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late AnimationController _pulseController;
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();

    // تحديث الإحصائيات كل 100ms للحصول على تحديثات حيّة
    _statsTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        ref.invalidate(syncHealthReportProvider);
      }
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    _pulseController.dispose();
    _statsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncHealthAsync = ref.watch(syncHealthReportProvider);

    if (widget.compact) {
      return syncHealthAsync.when(
        data: (health) => _buildCompactIndicator(context, health),
        loading: () => _buildCompactLoading(),
        error: (_, __) => const Icon(Icons.error_outline, color: Colors.red),
      );
    }

    return syncHealthAsync.when(
      data: (health) => _buildFullIndicator(context, health),
      loading: () => _buildFullLoading(),
      error: (e, __) => _buildErrorView(e.toString()),
    );
  }

  /// مؤشر مضغوط للـ app bar
  Widget _buildCompactIndicator(
    BuildContext context,
    SyncHealthReport health,
  ) {
    final isSyncing = health.pendingCount > 0;
    final totalPending = health.pendingCount +
        health.failedCount +
        health.stuckProcessingCount;
    final progress = health.completedCount /
        (health.completedCount + totalPending).toDouble()
        .clamp(0, 1);

    Color statusColor;
    IconData statusIcon;

    if (health.failedCount > 0) {
      statusColor = Colors.red;
      statusIcon = Icons.error_outline;
    } else if (health.status == 'critical') {
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
    } else if (isSyncing) {
      statusColor = Colors.blue;
      statusIcon = Icons.sync;
    } else {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    }

    return Tooltip(
      message: _buildStatusMessage(health),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: isSyncing
                ? RotationTransition(
                    turns: _progressController,
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  )
                : Icon(statusIcon, color: statusColor, size: 20),
          ),
          if (totalPending > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                totalPending.toString(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// مؤشر كامل مفصّل
  Widget _buildFullIndicator(
    BuildContext context,
    SyncHealthReport health,
  ) {
    final isSyncing = health.pendingCount > 0;
    final totalPending = health.pendingCount +
        health.failedCount +
        health.stuckProcessingCount;
    final progress =
        health.completedCount / (health.completedCount + totalPending)
            .toDouble()
            .clamp(0, 1);

    return Column(
      children: [
        // بطاقة الحالة الرئيسية
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // رأس البطاقة
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        AnimatedBuilder(
                          animation: isSyncing ? _pulseController : const AlwaysStoppedAnimation(0),
                          builder: (_, __) {
                            return ScaleTransition(
                              scale: Tween<double>(begin: 0.8, end: 1.2)
                                  .animate(_pulseController),
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSyncing ? Colors.blue : Colors.green,
                                  boxShadow: [
                                    if (isSyncing)
                                      BoxShadow(
                                        color: Colors.blue.withValues(alpha: 0.5),
                                        blurRadius: 8,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSyncing ? 'جاري المزامنة...' : 'تمت المزامنة',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              health.status,
                              style: TextStyle(
                                fontSize: 12,
                                color: _getStatusColor(health.status),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (widget.showDetailedStats)
                      ScaleTransition(
                        scale: Tween<double>(begin: 0.9, end: 1.1)
                            .animate(_pulseController),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${totalPending} معلق',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // شريط التقدم
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'التقدم',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isSyncing ? Colors.blue : Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // بطاقات الإحصائيات
        if (widget.showDetailedStats) ...[
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _buildStatCard(
                context,
                icon: Icons.upload,
                label: 'مرفوع',
                value: health.completedCount.toString(),
                color: Colors.green,
              ),
              _buildStatCard(
                context,
                icon: Icons.download,
                label: 'معلق',
                value: health.pendingCount.toString(),
                color: Colors.blue,
              ),
              _buildStatCard(
                context,
                icon: Icons.error_outline,
                label: 'فاشل',
                value: health.failedCount.toString(),
                color: Colors.red,
              ),
              _buildStatCard(
                context,
                icon: Icons.hourglass_empty,
                label: 'عالق',
                value: health.stuckProcessingCount.toString(),
                color: Colors.orange,
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// كارت إحصائي صغير
  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.1),
              color.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Icon(icon, color: color, size: 24),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// حالة التحميل
  Widget _buildCompactLoading() {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Widget _buildFullLoading() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  /// حالة الخطأ
  Widget _buildErrorView(String error) {
    return Card(
      color: Colors.red.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'خطأ في تحميل بيانات المزامنة',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// الحصول على لون الحالة
  Color _getStatusColor(String status) {
    switch (status) {
      case 'healthy':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'error':
        return Colors.deepOrange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// بناء رسالة الحالة
  String _buildStatusMessage(SyncHealthReport health) {
    final parts = <String>[];

    if (health.status == 'healthy') {
      parts.add('✅ النظام صحي');
    } else {
      parts.add('⚠️ ${health.status}');
    }

    if (health.pendingCount > 0) {
      parts.add('${health.pendingCount} معلق');
    }
    if (health.failedCount > 0) {
      parts.add('${health.failedCount} فاشل');
    }
    if (health.stuckProcessingCount > 0) {
      parts.add('${health.stuckProcessingCount} عالق');
    }

    return parts.join('\n');
  }
}

/// مؤشر مزامنة مصغر جداً للدمج في widgets أخرى
class CompactSyncDot extends ConsumerWidget {
  const CompactSyncDot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(syncHealthReportProvider);

    return healthAsync.when(
      data: (health) {
        final isSyncing = health.pendingCount > 0;
        final hasFailed = health.failedCount > 0;

        Color color;
        if (hasFailed) {
          color = Colors.red;
        } else if (isSyncing) {
          color = Colors.blue;
        } else if (health.status == 'صحي') {
          color = Colors.green;
        } else {
          color = Colors.orange;
        }

        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              if (isSyncing)
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
            ],
          ),
        );
      },
      loading: () => Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.blue,
        ),
      ),
      error: (_, __) => Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red,
        ),
      ),
    );
  }
}
