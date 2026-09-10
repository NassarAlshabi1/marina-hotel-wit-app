// ═══════════════════════════════════════════════════════════════
//  full_pull_progress_sheet.dart — لوحة تقدم السحب الكامل (غير حاجبة)
//  ✅ (2026-09-10) طلب المستخدم: «مؤشر السحب الكامل يجب أن أعرف مسار
//  حجم السحب والمتبقي ويجب أن لا يعيق الانتقال الى الشاشات الاخرى»
//
//  مبادئ التصميم:
//   • Bottom sheet قابل للسحب/الإغلاق دائماً (isDismissible) — لا يمنع
//     التنقل أبداً؛ السحب نفسه يعمل في الخلفية والبثّ يغذي اللوحة
//     أينما كان المستخدم.
//   • نسبة مئوية دقيقة عند توفر remaining الخادمي، وإلا عدّاد
//     «تم سحب N سجلاً» بحلقة غير-محددة (worker قديم) — لا نكذب.
//   • حالة النهاية (نجاح/فشل) تظهر بوضوح واللوحة تبقى قابلة للإغلاق.
// ═══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/appwrite_providers.dart';
import '../../services/appwrite_sync_manager.dart' show SyncPullProgress;

/// يفتح لوحة تقدم السحب الكامل — استدعِها من نقرة المؤشر أثناء السحب.
///
/// عدم الحجب عقد صريح: bottom sheet عادي قابل للإغلاق بالنقر خارجه
/// أو السحب لأسفل، ولا يوقف أي تنقّل جارٍ (السحب في الخلفية عبر
/// SyncGate لا علاقة له بهذا الـ route).
void showFullPullProgressSheet(BuildContext context) {
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.55,
        child: FullPullProgressSheet(),
      ),
    ),
  );
}

class FullPullProgressSheet extends ConsumerWidget {
  const FullPullProgressSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(cloudflarePullProgressProvider);
    // StreamProvider قد يقضي إطاراً واحداً على loading قبل أول بثّ —
    // نعرض لقطة المدير الحالية بدل واجهة فارغة (شاشة فُتحت متأخرة).
    final manager = ref.watch(appwriteSyncManagerProvider);
    final progress = progressAsync.valueOrNull ?? manager.lastPullProgress;

    final theme = Theme.of(context);
    final fraction = progress.fraction;
    final isSyncing = !progress.isDone;
    final remaining = progress.remainingRows;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // مقبض السحب — تذكير بصري أن اللوحة قابلة للإغلاق
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    progress.isFullSync ? Icons.cloud_download : Icons.sync,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      progress.isFullSync
                          ? 'تقدم السحب الكامل من السحابة'
                          : 'تقدم السحب',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: CircularProgressIndicator(
                          strokeWidth: 10,
                          // دقيق عند توفر remaining (worker المحدّث)،
                          // وإلا حلقة دوّارة عادية مع العدّاد.
                          value: fraction,
                        ),
                      ),
                      Text(
                        _centerLabel(progress),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _statRow(
                Icons.download_done,
                'تم سحبه',
                '${progress.pulledRows} سجل',
                Colors.green,
              ),
              if (isSyncing && remaining != null)
                _statRow(
                  Icons.schedule,
                  'المتبقي',
                  '$remaining سجل',
                  Colors.orange,
                ),
              if (isSyncing) ...[
                _statRow(
                  Icons.layers,
                  'الصفحات المنجزة',
                  '${progress.pages}',
                  Colors.blue,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.swipe_down, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'يمكنك التنقل بين الشاشات بحرية — السحب يعمل في '
                          'الخلفية وهذه اللوحة قابلة للإغلاق في أي وقت.',
                          style: TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (progress.isDone) ...[
                const SizedBox(height: 8),
                if (progress.errorMessage != null)
                  _banner(
                    'فشل السحب: ${progress.errorMessage}',
                    theme.colorScheme.errorContainer,
                    Icons.error_outline,
                  )
                else
                  _banner(
                    '✅ اكتمل السحب — ${progress.pulledRows} سجلاً '
                    '${progress.isFullSync ? '(مزامنة كاملة)' : ''}',
                    Colors.green.withValues(alpha: 0.12),
                    Icons.check_circle_outline,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _centerLabel(SyncPullProgress progress) {
    if (progress.isDone && progress.errorMessage == null) return 'اكتمل';
    final fraction = progress.fraction;
    if (fraction == null) return '${progress.pulledRows}';
    return '${(fraction * 100).toStringAsFixed(0)}%';
  }

  Widget _statRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _banner(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
