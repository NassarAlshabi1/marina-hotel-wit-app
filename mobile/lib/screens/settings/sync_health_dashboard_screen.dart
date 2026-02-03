import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/sync_dashboard_provider.dart';
import '../../services/sync_health_monitor.dart';
import '../../services/sync_core/circuit_breaker.dart';
import '../../services/sync_integrity_checker.dart';
import 'package:intl/intl.dart';

class SyncHealthDashboardScreen extends ConsumerStatefulWidget {
  const SyncHealthDashboardScreen({super.key});

  @override
  ConsumerState<SyncHealthDashboardScreen> createState() =>
      _SyncHealthDashboardScreenState();
}

class _SyncHealthDashboardScreenState
    extends ConsumerState<SyncHealthDashboardScreen> {
  Future<void> _refreshAll() async {
    ref.invalidate(syncDashboardProvider);
  }

  @override
  Widget build(BuildContext context) {
    final dashboardAsync = ref.watch(syncDashboardProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مراقبة صحة المزامنة'),
          centerTitle: true,
          elevation: 0,
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshAll),
          ],
        ),
        body: dashboardAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'خطأ في تحميل البيانات',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshAll,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
          data: (dashboard) => RefreshIndicator(
            onRefresh: _refreshAll,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildOverallHealthCard(dashboard),
                  const SizedBox(height: 16),
                  _buildMetricsGrid(dashboard),
                  const SizedBox(height: 16),
                  _buildCircuitBreakerStatus(dashboard),
                  const SizedBox(height: 16),
                  _buildIntegrityReportCard(dashboard),
                  const SizedBox(height: 16),
                  _buildQueueStatus(dashboard),
                  const SizedBox(height: 16),
                  _buildRecommendationsCard(dashboard),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  String _getLocalizedErrorMessage(Object error) {
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('network') ||
        errorStr.contains('socket') ||
        errorStr.contains('connection')) {
      return 'خطأ في الاتصال بالإنترنت. تأكد من اتصالك وحاول مرة أخرى.';
    }
    if (errorStr.contains('timeout')) {
      return 'انتهت مهلة الاتصال. حاول مرة أخرى.';
    }
    if (errorStr.contains('unauthorized') || errorStr.contains('401')) {
      return 'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مرة أخرى.';
    }
    if (errorStr.contains('database') || errorStr.contains('drift')) {
      return 'خطأ في قاعدة البيانات المحلية. حاول إعادة تشغيل التطبيق.';
    }
    return 'حدث خطأ غير متوقع. حاول مرة أخرى لاحقاً.';
  }

  Widget _buildOverallHealthCard(SyncDashboardData dashboard) {
    final status = dashboard.healthMetrics.status;
    final color = _getStatusColor(status);
    final icon = _getStatusIcon(status);
    final statusText = _getStatusText(status);

    return Card(
      color: color.withOpacity(0.1),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 12),
            Text(
              'الحالة العامة',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.grey[700]),
            ),
            const SizedBox(height: 4),
            Text(
              statusText,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            StatusIndicator(status: status),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid(SyncDashboardData dashboard) {
    final metrics = dashboard.healthMetrics;
    final orchestratorMetrics = dashboard.orchestratorHealth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'المقاييس الرئيسية',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Builder(
          builder: (context) {
            final width = MediaQuery.sizeOf(context).width;
            final crossAxisCount = width < 360 ? 1 : width < 600 ? 2 : 3;
            return GridView.count(
              crossAxisCount: crossAxisCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
            MetricCard(
              title: 'المزامنات الناجحة',
              value: '${dashboard.orchestratorMetrics?.successfulSyncs ?? 0}',
              icon: Icons.check_circle,
              color: Colors.green,
            ),
            MetricCard(
              title: 'المزامنات الفاشلة',
              value: '${dashboard.orchestratorMetrics?.failedSyncs ?? 0}',
              icon: Icons.error,
              color: Colors.red,
            ),
            MetricCard(
              title: 'متوسط المدة',
              value: _formatDuration(metrics.averageSyncDuration),
              icon: Icons.timer,
              color: Colors.blue,
            ),
            MetricCard(
              title: 'معدل التعارضات',
              value: '${(metrics.conflictRate * 100).toStringAsFixed(0)}%',
              icon: Icons.merge_type,
              color: metrics.conflictRate > 0.3 ? Colors.orange : Colors.green,
            ),
            MetricCard(
              title: 'آخر مزامنة ناجحة',
              value: _formatLastSync(orchestratorMetrics.lastSuccessfulSync),
              icon: Icons.access_time,
              color: Colors.teal,
            ),
            MetricCard(
              title: 'خطر فقدان البيانات',
              value: '${(metrics.dataLossRisk * 100).toStringAsFixed(0)}%',
              icon: Icons.warning,
              color: metrics.dataLossRisk > 0.5 ? Colors.red : Colors.green,
            ),
          ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCircuitBreakerStatus(SyncDashboardData dashboard) {
    final circuitStates = dashboard.orchestratorHealth.circuitStates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'حالة Circuit Breakers',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: circuitStates.entries.map((entry) {
                return CircuitBreakerCard(name: entry.key, state: entry.value);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQueueStatus(SyncDashboardData dashboard) {
    final queueStats = dashboard.queueStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'حالة طابور المزامنة',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildQueueRow(
                  'إجمالي العناصر',
                  queueStats.totalItems.toString(),
                  Icons.list,
                ),
                const Divider(),
                _buildQueueRow(
                  'في الانتظار',
                  queueStats.pendingItems.toString(),
                  Icons.pending,
                  Colors.orange,
                ),
                const Divider(),
                _buildQueueRow(
                  'جاهز للمحاولة',
                  queueStats.retriableItems.toString(),
                  Icons.refresh,
                  Colors.blue,
                ),
                const Divider(),
                _buildQueueRow(
                  'فاشل',
                  queueStats.failedItems.toString(),
                  Icons.error,
                  Colors.red,
                ),
                if (queueStats.oldestItem != null) ...[
                  const Divider(),
                  _buildQueueRow(
                    'أقدم عنصر',
                    _formatDateTime(queueStats.oldestItem!),
                    Icons.calendar_today,
                  ),
                ],
                if (queueStats.lastProcessed != null) ...[
                  const Divider(),
                  _buildQueueRow(
                    'آخر معالجة',
                    _formatDateTime(queueStats.lastProcessed!),
                    Icons.update,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQueueRow(
    String label,
    String value,
    IconData icon, [
    Color? color,
  ]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color ?? Colors.grey[900],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationsCard(SyncDashboardData dashboard) {
    final recommendations = dashboard.healthMetrics.recommendations;

    if (recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'التوصيات',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Card(
          color: Colors.orange.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'نصائح لتحسين الأداء',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...recommendations.map(
                  (recommendation) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.arrow_left,
                          size: 20,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            recommendation,
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(SyncHealthStatus status) {
    switch (status) {
      case SyncHealthStatus.healthy:
        return Colors.green;
      case SyncHealthStatus.warning:
        return Colors.orange;
      case SyncHealthStatus.critical:
        return Colors.red;
      case SyncHealthStatus.error:
        return Colors.red.shade900;
    }
  }

  IconData _getStatusIcon(SyncHealthStatus status) {
    switch (status) {
      case SyncHealthStatus.healthy:
        return Icons.check_circle;
      case SyncHealthStatus.warning:
        return Icons.warning;
      case SyncHealthStatus.critical:
        return Icons.error;
      case SyncHealthStatus.error:
        return Icons.dangerous;
    }
  }

  String _getStatusText(SyncHealthStatus status) {
    switch (status) {
      case SyncHealthStatus.healthy:
        return 'صحي';
      case SyncHealthStatus.warning:
        return 'تحذير';
      case SyncHealthStatus.critical:
        return 'حرج';
      case SyncHealthStatus.error:
        return 'خطأ';
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}ث';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}د';
    } else {
      return '${duration.inHours}س';
    }
  }

  String _formatLastSync(DateTime? dateTime) {
    if (dateTime == null) return 'لم يتم بعد';

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'الآن';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes}د';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours}س';
    } else {
      return 'منذ ${difference.inDays} يوم';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final format = DateFormat('yyyy/MM/dd HH:mm', 'ar');
    return format.format(dateTime.toLocal());
  }

  Widget _buildIntegrityReportCard(SyncDashboardData dashboard) {
    final report = dashboard.integrityReport;

    if (report == null) {
      return const SizedBox.shrink();
    }

    final hasIssues = report.hasIssues;
    final hasCritical = report.hasCriticalIssues;
    final statusColor =
        hasCritical ? Colors.red : (hasIssues ? Colors.orange : Colors.green);
    final statusIcon = hasCritical
        ? Icons.error
        : (hasIssues ? Icons.warning : Icons.check_circle);
    final statusText =
        hasCritical ? 'مشاكل حرجة' : (hasIssues ? 'تحذيرات' : 'سليم');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'فحص سلامة البيانات',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                          if (hasIssues) ...[
                            const SizedBox(height: 4),
                            Text(
                              'تم اكتشاف ${report.issueCount} مشكلة',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (hasIssues) ...[
                  const Divider(height: 24),
                  _buildIntegrityMetricsRow(
                    'مشاكل حرجة',
                    report.criticalIssueCount.toString(),
                    Icons.error,
                    Colors.red,
                  ),
                  const SizedBox(height: 8),
                  _buildIntegrityMetricsRow(
                    'مشاكل عادية',
                    (report.issueCount - report.criticalIssueCount).toString(),
                    Icons.warning,
                    Colors.orange,
                  ),
                  const SizedBox(height: 8),
                  _buildIntegrityMetricsRow(
                    'مدة الفحص',
                    '${report.checkDuration.inMilliseconds}مللي ثانية',
                    Icons.timer,
                    Colors.blue,
                  ),
                  if (report.issuesByType.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text(
                      'تفصيل المشاكل',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...report.issuesByType.entries.map((entry) {
                      final typeLabel = _getIssueTypeLabel(entry.key);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(typeLabel),
                            Text(
                              entry.value.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ],
                if (!hasIssues) ...[
                  const Divider(height: 24),
                  Text(
                    'جميع الفحوصات نجحت ✓',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIntegrityMetricsRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: TextStyle(color: Colors.grey[700])),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  String _getIssueTypeLabel(IssueType issueType) {
    const labels = {
      IssueType.orphanedRecord: 'سجلات يتيمة',
      IssueType.duplicateUuid: 'معرّفات مكررة',
      IssueType.versionInconsistency: 'عدم تطابق الإصدارات',
      IssueType.amountMismatch: 'عدم تطابق المبالغ',
      IssueType.missingReference: 'مراجع مفقودة',
      IssueType.invalidStatus: 'حالات غير صالحة',
    };
    return labels[issueType] ?? issueType.toString().split('.').last;
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? Colors.blue;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: cardColor),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: cardColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class StatusIndicator extends StatelessWidget {
  final SyncHealthStatus status;

  const StatusIndicator({super.key, required this.status});

  Color get color {
    switch (status) {
      case SyncHealthStatus.healthy:
        return Colors.green;
      case SyncHealthStatus.warning:
        return Colors.orange;
      case SyncHealthStatus.critical:
        return Colors.red;
      case SyncHealthStatus.error:
        return Colors.red.shade900;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            _getStatusLabel(),
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _getStatusLabel() {
    switch (status) {
      case SyncHealthStatus.healthy:
        return 'النظام يعمل بشكل جيد';
      case SyncHealthStatus.warning:
        return 'يحتاج إلى انتباه';
      case SyncHealthStatus.critical:
        return 'وضع حرج';
      case SyncHealthStatus.error:
        return 'خطأ في النظام';
    }
  }
}

class CircuitBreakerCard extends StatelessWidget {
  final String name;
  final CircuitState state;

  const CircuitBreakerCard({
    super.key,
    required this.name,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getStateColor();
    final icon = _getStateIcon();
    final statusText = _getStateText();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getServiceName(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getServiceName() {
    switch (name) {
      case 'appwrite':
        return 'Appwrite';
      case 'google_drive':
        return 'Google Drive';
      default:
        return name;
    }
  }

  Color _getStateColor() {
    switch (state) {
      case CircuitState.closed:
        return Colors.green;
      case CircuitState.halfOpen:
        return Colors.orange;
      case CircuitState.open:
        return Colors.red;
    }
  }

  IconData _getStateIcon() {
    switch (state) {
      case CircuitState.closed:
        return Icons.check_circle;
      case CircuitState.halfOpen:
        return Icons.warning;
      case CircuitState.open:
        return Icons.error;
    }
  }

  String _getStateText() {
    switch (state) {
      case CircuitState.closed:
        return 'متصل';
      case CircuitState.halfOpen:
        return 'اختبار';
      case CircuitState.open:
        return 'مفصول';
    }
  }
}
