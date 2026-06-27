// lib/screens/settings/sync_health/sync_health_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../components/app_scaffold.dart';
import '../../../core/core.dart';
import '../../../providers/repository_providers.dart';
import '../../../services/sync_health_monitor.dart';

/// شاشة مراقبة صحة نظام المزامنة.
///
/// تعرض مؤشرات حيوية عن حالة المزامنة:
/// - الحالة العامة (صحي/تحذير/خطأ/حرج)
/// - عدد عناصر outbox المعلقة/الفاشلة/العالقة
/// - عمر أقدم عنصر معلق
/// - إحصائيات حسب entity
/// - حجم الجداول
/// - انتهاكات FK
class SyncHealthScreen extends ConsumerStatefulWidget {
  const SyncHealthScreen({super.key});

  @override
  ConsumerState<SyncHealthScreen> createState() => _SyncHealthScreenState();
}

class _SyncHealthScreenState extends ConsumerState<SyncHealthScreen> {
  late SyncHealthReport _report;
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadReport();
    // تحديث كل 30 ثانية
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadReport());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadReport() async {
    try {
      final db = ref.read(databaseProvider);
      final report = await SyncHealthMonitor.instance.getHealthReport(db);
      if (mounted) {
        setState(() {
          _report = report;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'حالة المزامنة',
      actions: [
        IconButton(
          onPressed: _loadReport,
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث',
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : RefreshIndicator(
                  onRefresh: _loadReport,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildOverallStatusCard(),
                      const SizedBox(height: 16),
                      _buildOutboxStatsCard(),
                      const SizedBox(height: 16),
                      _buildEntityBreakdownCard(),
                      const SizedBox(height: 16),
                      _buildTableSizesCard(),
                      const SizedBox(height: 16),
                      _buildFkViolationsCard(),
                      const SizedBox(height: 32),
                      Text(
                        'آخر تحديث: ${_report.timestamp.toIso8601String()}',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'فشل تحميل التقرير',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadReport,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallStatusCard() {
    final status = _report.status;
    return Card(
      color: _statusColor(status).withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(status.emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(
              status.label,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _statusColor(status),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusDescription(status),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutboxStatsCard() {
    final r = _report;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.outbox, color: UIConstants.backupColor),
                const SizedBox(width: 8),
                Text(
                  'صندوق الصادر (Outbox)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(),
            _buildStatRow('معلق', r.pendingCount, Colors.orange),
            _buildStatRow('قيد المعالجة', r.processingCount, Colors.blue),
            _buildStatRow('فشل', r.failedCount,
                r.failedCount > 0 ? Colors.red : Colors.green),
            _buildStatRow('مكتمل', r.completedCount, Colors.green),
            const Divider(),
            _buildStatRow(
              'عالق في المعالجة',
              r.stuckProcessingCount,
              r.stuckProcessingCount > 0 ? Colors.red : Colors.green,
            ),
            _buildStatRow(
              'عمر أقدم عنصر',
              r.oldestPendingAgeFormatted,
              _ageColor(r.oldestPendingAge),
              isString: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntityBreakdownCard() {
    final breakdown = _report.entityBreakdown;
    if (breakdown.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
              const SizedBox(height: 8),
              Text(
                'لا توجد عناصر معلقة أو فاشلة',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    final sorted = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.list, color: UIConstants.backupColor),
                const SizedBox(width: 8),
                Text(
                  'العناصر المعلقة/الفاشلة حسب النوع',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(),
            ...sorted.map((entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: entry.value > 10
                              ? Colors.red.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${entry.value}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: entry.value > 10 ? Colors.red : Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildTableSizesCard() {
    final sizes = _report.tableSizes;
    final sorted = sizes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, color: UIConstants.backupColor),
                const SizedBox(width: 8),
                Text(
                  'حجم الجداول',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(),
            ...sorted.map((entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildFkViolationsCard() {
    final violations = _report.fkViolations;
    return Card(
      color: violations > 0
          ? Colors.red.withValues(alpha: 0.1)
          : Colors.green.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              violations > 0 ? Icons.warning : Icons.check_circle,
              color: violations > 0 ? Colors.red : Colors.green,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'سلامة المفاتيح الأجنبية',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    violations == 0
                        ? 'لا توجد انتهاكات — قاعدة البيانات سليمة'
                        : '$violations انتهاك مفتاح أجنبي — يحتاج إصلاح',
                    style: TextStyle(
                      color: violations > 0 ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, dynamic value, Color color,
      {bool isString = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isString ? value.toString() : '$value',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(SyncHealthStatus status) {
    switch (status) {
      case SyncHealthStatus.healthy:
      case SyncHealthStatus.ok:
        return Colors.green;
      case SyncHealthStatus.warning:
        return Colors.orange;
      case SyncHealthStatus.error:
        return Colors.red;
      case SyncHealthStatus.critical:
        return Colors.red.shade900;
      case SyncHealthStatus.unknown:
        return Colors.grey;
    }
  }

  String _statusDescription(SyncHealthStatus status) {
    switch (status) {
      case SyncHealthStatus.healthy:
        return 'نظام المزامنة يعمل بشكل مثالي';
      case SyncHealthStatus.ok:
        return 'نظام المزامنة يعمل بشكل جيد';
      case SyncHealthStatus.warning:
        return 'يوجد تحذيرات تحتاج متابعة';
      case SyncHealthStatus.error:
        return 'يوجد أخطاء تحتاج إصلاح';
      case SyncHealthStatus.critical:
        return 'مشاكل حرجة — يرجى الاتصال بالدعم';
      case SyncHealthStatus.unknown:
        return 'تعذرت قراءة حالة المزامنة';
    }
  }

  Color _ageColor(Duration? age) {
    if (age == null) return Colors.green;
    if (age > SyncHealthMonitor.stuckThreshold) return Colors.red;
    if (age.inMinutes > 5) return Colors.orange;
    return Colors.green;
  }
}
