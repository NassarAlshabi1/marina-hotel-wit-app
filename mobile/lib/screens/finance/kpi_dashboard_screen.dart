import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/finance_kpi_providers.dart';
import '../../src/finance/finance_models.dart';

/// شاشة لوحة المؤشرات الأسبوعية (KPIs).
///
/// تعرض 16 مؤشراً: التشغيل (إشغال/ADR/RevPAR)، الإيراد والتحصيل،
/// التكلفة، والسيولة — بالأسبوع الحالي مقابل السابق والهدف والحالة
/// بألوان الإنذار (أخضر/أصفر/أحمر).
class KpiDashboardScreen extends ConsumerWidget {
  const KpiDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(kpiSnapshotProvider);

    return AppScaffold(
      title: 'لوحة المؤشرات الأسبوعية',
      subtitle: 'ربط أداء التشغيل والتكاليف بالسيولة النقدية',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(financeDataBundleProvider);
          ref.invalidate(kpiSnapshotProvider);
          await ref.read(kpiSnapshotProvider.future);
        },
        child: snapshotAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 80),
              const Icon(Icons.error_outline, color: Colors.red, size: 42),
              const SizedBox(height: 8),
              Center(child: Text('تعذر حساب المؤشرات: $e')),
              const SizedBox(height: 12),
              Center(
                child: FilledButton.tonal(
                  onPressed: () => ref.invalidate(kpiSnapshotProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (snapshot) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            children: [
              _Legend(periods: snapshot),
              const SizedBox(height: 8),
              const _HeaderRow(),
              const SizedBox(height: 4),
              for (final row in snapshot.rows) ...[
                _KpiRow(entry: row),
                const SizedBox(height: 4),
              ],
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'قاعدة القراءة: أي مؤشر أحمر يتطلب إجراءً تصحيحياً '
                  'ومسؤولاً وموعد إغلاق، والأصفر يُراقب في الأسبوع التالي. '
                  'فرق الصندوق وفرق الإيرادات يفحصان جودة التسجيل اليومي.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── مفتاح الألوان + الفترات ─────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend({required this.periods});

  final KpiSnapshot periods;

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 4.5, backgroundColor: c),
            const SizedBox(width: 4),
            Text(t, style: const TextStyle(fontSize: 10.5)),
          ],
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                dot(Colors.green, 'مستقر'),
                dot(Colors.orange, 'يراقب'),
                dot(Colors.red, 'يتطلب إجراءً'),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'الحالي: ${periods.currentPeriodText}   |   السابق: ${periods.previousPeriodText}',
              style: TextStyle(fontSize: 10.5, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── صف العناوين ─────────────────────────────────────────────────────

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.bold,
      color: Colors.grey,
    );
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('المؤشر', style: style)),
          Expanded(
            flex: 3,
            child: Text('الأسبوع الحالي', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 3,
            child: Text('السابق / الهدف', style: style, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

// ── صف مؤشر ─────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.entry});

  final KpiEntry entry;

  Color get _statusColor {
    switch (entry.status) {
      case AlertLevel.good:
        return Colors.green;
      case AlertLevel.warning:
        return Colors.orange;
      case AlertLevel.danger:
        return Colors.red;
      case AlertLevel.unknown:
        return Colors.grey;
    }
  }

  IconData get _statusIcon {
    switch (entry.status) {
      case AlertLevel.good:
        return Icons.check_circle;
      case AlertLevel.warning:
        return Icons.warning_amber_rounded;
      case AlertLevel.danger:
        return Icons.error;
      case AlertLevel.unknown:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_statusIcon, size: 13, color: _statusColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          entry.label,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.hint,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                entry.currentText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _statusColor == Colors.grey
                      ? Theme.of(context).colorScheme.onSurface
                      : _statusColor,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  Text(
                    entry.previousText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.targetText,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9.5, color: Colors.grey[600]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
