import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/finance_kpi_providers.dart';
import '../../services/cloudflare_finance_service.dart';
import '../../src/finance/finance_models.dart';
import '../../utils/currency_formatter.dart';

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
              const SizedBox(height: 14),
              const _VarianceSection(),
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

// ═══════════════════════════════════════════════════════════════════
//  الفعلي مقابل المتوقع (حوكمة أسبوعية — خطوات §8)
//
//  - اعتماد نسخة أسبوعية من النموذج (manager/admin على الخادم).
//  - مقارنة الأسابيع المنتهية فعلياً بحركات D1 الحية بعتبات
//    5% (أخضر) / 10% (أصفر) / >10% (أحمر).
// ═══════════════════════════════════════════════════════════════════

class _VarianceSection extends ConsumerStatefulWidget {
  const _VarianceSection();

  @override
  ConsumerState<_VarianceSection> createState() => _VarianceSectionState();
}

class _VarianceSectionState extends ConsumerState<_VarianceSection> {
  bool _approving = false;

  Color _statusColor(String status) {
    switch (status) {
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.orange;
      case 'red':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _approve() async {
    setState(() => _approving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = ref.read(cloudflareFinanceServiceProvider);
      await service
          .approveSnapshot(
              label: 'نسخة ${DateTime.now().toIso8601String().substring(0, 10)}')
          .timeout(const Duration(seconds: 40));
      ref.invalidate(financeSnapshotsProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('تم اعتماد نسخة الأسبوع بنجاح')),
      );
    } on CloudflareFinanceException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(
          e.isForbidden
              ? 'اعتماد النسخة يتطلب صلاحية مدير'
              : 'فشل الاعتماد: ${e.message}',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر الاتصال بالخادم: $e')),
      );
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshotsAsync = ref.watch(financeSnapshotsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined, size: 16),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'الفعلي مقابل المتوقع (اعتماد أسبوعي)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: _approving ? null : _approve,
                  icon: _approving
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.6),
                        )
                      : const Icon(Icons.verified_outlined, size: 15),
                  label: const Text('اعتماد نسخة الأسبوع',
                      style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
            Text(
              'يعتمد المدير نسخة أسبوعية من النموذج، ثم تُقارن الأسابيع '
              'المنتهية فعلياً بالحركات الحقيقية: أخضر ≤ 5%، أصفر ≤ 10%، '
              'أحمر > 10% ويُفسَّر بإجراء ومسؤول.',
              style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            snapshotsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'اللقطات الأسبوعية تتطلب اتصالاً بالخادم وصلاحية '
                        'مدير أو أعلى.',
                        style:
                            TextStyle(fontSize: 10.5, color: Colors.grey[600]),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إعادة المحاولة',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          ref.invalidate(financeSnapshotsProvider),
                      icon: const Icon(Icons.refresh, size: 17),
                    ),
                  ],
                ),
              ),
              data: (snapshots) {
                if (snapshots.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'لا توجد نسخ معتمدة بعد — اعتمد أول نسخة أسبوعية '
                      'لتبدأ مقارنة الفعلي بالمتوقع.',
                      style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final snap in snapshots.take(8))
                      _SnapshotTile(
                        snapshot: snap,
                        statusColor: _statusColor,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── صف لقطة أسبوعية قابل للتوسيع لعرض الانحراف ──────────────────────

class _SnapshotTile extends ConsumerWidget {
  const _SnapshotTile({required this.snapshot, required this.statusColor});

  final FinanceSnapshotMeta snapshot;
  final Color Function(String) statusColor;

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final varianceAsync = ref.watch(financeVarianceProvider(snapshot.id));

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      dense: true,
      title: Text(
        snapshot.label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${snapshot.scenarioKey} • ${_fmtDate(snapshot.approvedAt)} • '
        'احتياج تمويل: ${CurrencyFormatter.formatAmount(snapshot.financingNeed)}',
        style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        varianceAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(10),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              'تعذر حساب المقارنة: $e',
              style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
            ),
          ),
          data: (report) {
            final ended =
                report.weeks.where((w) => w.actual != null).toList();
            if (ended.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  'لم ينتهِ أي أسبوع من هذه النسخة بعد — المقارنة تظهر '
                  'بعد مرور أسبوع على الاعتماد.',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
                ),
              );
            }
            return Column(
              children: [
                for (final w in ended)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor(w.status).withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(6),
                      border: Border(
                        left: BorderSide(color: statusColor(w.status), width: 3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(_statusIconFor(w.status),
                            size: 14, color: statusColor(w.status)),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'الأسبوع ${w.index}  (${w.start} ← ${w.end})',
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'داخل متوقع '
                                '${CurrencyFormatter.formatAmount(w.forecast.inflow)} '
                                '• فعلي '
                                '${CurrencyFormatter.formatAmount(w.actual!.inflow)}'
                                '${w.varianceNetPct == null ? '' : '  |  صافي الانحراف ${w.varianceNetPct!.toStringAsFixed(1)}%'}',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[700]),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor(w.status),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _statusLabel(w.status),
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  IconData _statusIconFor(String status) {
    switch (status) {
      case 'green':
        return Icons.check_circle_outline;
      case 'yellow':
        return Icons.warning_amber_rounded;
      case 'red':
        return Icons.error_outline;
      default:
        return Icons.help_outline;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'green':
        return 'مطابق';
      case 'yellow':
        return 'يراقب';
      case 'red':
        return 'انحراف';
      default:
        return '—';
    }
  }
}
