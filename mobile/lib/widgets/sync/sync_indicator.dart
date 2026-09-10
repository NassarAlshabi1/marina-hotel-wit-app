// ═══════════════════════════════════════════════════════════════
//  sync_indicator.dart — مؤشر حالة المزامنة الحيّ في شريط التطبيق
//  ✅ (2026-09-10) إصلاح «مؤشرات المزامنة لا تعمل» + مؤشر السحب الكامل:
//
//  الجذر الأول: النسخة القديمة كانت تستمع إلى `syncStateProvider` من
//  SyncOrchestrator — مكوّن لا يُهيّأ في التطبيق أبداً (لا adapters
//  تُسجَّل ولا أحد يستدعي initialize) فبقي المؤشر فارغاً إلى الأبد،
//  بينما التدفق الحقيقي (CloudflareSyncManager.syncStatusStream الذي
//  يبثّ syncing/success/failed/idle من دورة sync() الفعلية) لم يكن
//  يستمعه أحد.
//
//  الجديد (طلب المستخدم): «مؤشر السحب الكامل يجب أن أعرف مسار حجم
//  السحب والمتبقي ويجب أن لا يعيق الانتقال الى الشاشات الاخرى»:
//   • أثناء السحب الكامل: حلقة تقدّم دقيقة (pulled/remaining الخادمي)
//     وتلميح «تم X / المتبقي Y» — من cloudflarePullProgressProvider.
//   • نقرة أثناء السحب تفتح لوحة التقدم (غير حاجبة — قابلة للإغلاق
//     والتنقل حر تماماً)؛ نقرة في غيره تفتح شاشة تسجيل الدخول.
// ═══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/appwrite_providers.dart';
import '../../screens/auth/cloudflare_login_screen.dart';
import '../../services/appwrite_sync_manager.dart'
    show SyncPullProgress, SyncStatus;
import '../../services/sync/sync_gate.dart';
import 'full_pull_progress_sheet.dart';

/// مؤشر حالة المزامنة الحيّ — يُعرض في AppBar الرئيسي.
///
/// حالة العرض (بالأولوية):
///  1. مزامنة جارية (syncing) → حلقة تقدّم (دقيقة عند توفر remaining)
///  2. مزامنة مزروعة في بوابة SyncGate (عملية أخرى شغّالة) → قرص دوّار
///  3. فشل آخر دورة (failed) → أيقونة تحذير برتقالية — نقرة تفتح شاشة
///     تسجيل الدخول/التشخيص
///  4. تغييرات محلية معلّقة (outbox > 0) → شارة عدّاد زرقاء
///  5. آخر دورة نجحت (success) → صحّة خضراء
///  6. خامل (idle) → سحابة خضراء «متصل»
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(cloudflareSyncStatusProvider);
    final pendingAsync = ref.watch(outboxCountProvider);
    final progressAsync = ref.watch(cloudflarePullProgressProvider);

    final status = statusAsync.when(
      data: (s) => s,
      loading: () => SyncStatus.idle,
      error: (_, __) => SyncStatus.failed,
    );
    final pending = pendingAsync.asData?.value ?? 0;
    final gateBusy = SyncGate.instance.state.isBusy;
    final progress =
        progressAsync.valueOrNull ??
        ref.read(appwriteSyncManagerProvider).lastPullProgress;
    final pulling = status == SyncStatus.syncing || gateBusy;

    return Tooltip(
      message: _tooltipFor(status, pending, gateBusy, progress),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: () => _handleTap(context, pulling),
        icon: _iconFor(context, status, pending, gateBusy, progress),
      ),
    );
  }

  /// ✅ «لا يعيق الانتقال» — النقرة تفتح لوحة غير حاجبة أثناء السحب،
  /// وشاشة تسجيل الدخول في باقي الحالات. لا حالة قفل ولا انتظار.
  void _handleTap(BuildContext context, bool pulling) {
    if (pulling) {
      showFullPullProgressSheet(context);
    } else {
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const CloudflareLoginScreen(),
          ),
        ),
      );
    }
  }

  String _tooltipFor(
    SyncStatus status,
    int pending,
    bool gateBusy,
    SyncPullProgress progress,
  ) {
    if (status == SyncStatus.syncing || gateBusy) {
      final buf = StringBuffer('جاري السحب — تم ${progress.pulledRows} سجل');
      final remaining = progress.remainingRows;
      if (!progress.isDone && remaining != null) {
        buf.write(' / المتبقي $remaining');
      }
      return buf.toString();
    }
    if (status == SyncStatus.failed) {
      return 'فشلت آخر مزامنة — اضغط للتفاصيل وتسجيل الدخول';
    }
    if (pending > 0) return '$pending تغييراً معلّقاً — اضغط للمزامنة';
    if (status == SyncStatus.success) return 'تمت المزامنة بنجاح';
    return 'اتصال Cloudflare — اضغط لإدارة تسجيل الدخول';
  }

  Widget _iconFor(
    BuildContext context,
    SyncStatus status,
    int pending,
    bool gateBusy,
    SyncPullProgress progress,
  ) {
    final theme = Theme.of(context);
    if (status == SyncStatus.syncing || gateBusy) {
      // ✅ مؤشر السحب الكامل: حلقة دقيقة (pulled/remaining) عند توفر
      // remaining من الخادم، وإلا حلقة عادية — والعدّاد في التلميح.
      final fraction = progress.isDone ? null : progress.fraction;
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          value: fraction,
        ),
      );
    }
    if (status == SyncStatus.failed) {
      return const Icon(Icons.cloud_off, color: Colors.orange, size: 22);
    }
    if (pending > 0) {
      return Badge(
        label: Text('$pending'),
        child: Icon(Icons.cloud_sync, color: theme.colorScheme.primary),
      );
    }
    if (status == SyncStatus.success) {
      return const Icon(Icons.cloud_done, color: Colors.green, size: 22);
    }
    return Icon(Icons.cloud_done_outlined, color: Colors.green.shade400);
  }
}
