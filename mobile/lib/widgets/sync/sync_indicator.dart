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
//
//  ✅ (2026-09-17) طلب المستخدم: «عند فتح التطبيق يفترض يفحص تلقائيا
//  الاتصال مع cloudflare worker d1» — المؤشر يعكس الآن نتيجة فحص
//  الاتصال التلقائي (connectionStatusProvider الذي يملؤه مراقب الإقلاع):
//   • فحص مكتمل والـ Worker غير قابل للوصول → سحابة حمراء معلّقة.
//   • الـ Worker حي لكن قاعدة D1 لا تستجيب → سحابة برتقالية.
//   • لم يُنفّذ فحص بعد (lastCheckedAt == null) → السلوك السابق كما هو
//     (لا وميض أحمر قبل اكتمال أول فحص عند الإقلاع).
// ═══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
///  2. فحص اتصال مكتمل والسحابة غير قابلة للوصول → سحابة حمراء معلّقة
///  3. فشل آخر دورة (failed) → أيقونة تحذير برتقالية — نقرة تفتح شاشة
///     تسجيل الدخول/التشخيص
///  4. السحابة حية لكن D1 لا يستجيب → سحابة برتقالية
///  5. تغييرات محلية معلّقة (outbox > 0) → شارة عدّاد زرقاء
///  6. آخر دورة نجحت (success) → صحّة خضراء
///  7. خامل (idle) → سحابة خضراء «متصل» (التلميح يذكر زمن D1 إن توفر)
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(cloudflareSyncStatusProvider);
    final pendingAsync = ref.watch(outboxCountProvider);
    final progressAsync = ref.watch(cloudflarePullProgressProvider);
    final connection = ref.watch(connectionStatusProvider);

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

    // نتيجة فحص الاتصال التلقائي (startup watcher). null = لم يُفحص بعد.
    final checked = connection.lastCheckedAt != null;
    final cloudUnreachable = checked && !connection.isConnected;
    final d1Down =
        checked && connection.isConnected && connection.isD1Connected == false;

    return Tooltip(
      message: _tooltipFor(
        status,
        pending,
        gateBusy,
        progress,
        connection,
        checked,
      ),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: () => _handleTap(context, pulling),
        icon: _iconFor(
          context,
          status,
          pending,
          gateBusy,
          progress,
          cloudUnreachable,
          d1Down,
        ),
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
    ConnectionState connection,
    bool checked,
  ) {
    if (status == SyncStatus.syncing || gateBusy) {
      final buf = StringBuffer('جاري السحب — تم ${progress.pulledRows} سجل');
      final remaining = progress.remainingRows;
      if (!progress.isDone && remaining != null) {
        buf.write(' / المتبقي $remaining');
      }
      return buf.toString();
    }
    if (checked && !connection.isConnected) {
      final when = connection.lastCheckedAt;
      final hhmm = when == null ? '' : ' — ${DateFormat.Hm().format(when)}';
      return 'تعذر الوصول لخادم Cloudflare$hhmm — اضغط للتفاصيل والتشخيص';
    }
    if (status == SyncStatus.failed) {
      return 'فشلت آخر مزامنة — اضغط للتفاصيل وتسجيل الدخول';
    }
    if (checked && connection.isD1Connected == false) {
      return 'قاعدة D1 لا تستجيب (${connection.d1Error ?? 'غير معروف'}) — اضغط للتفاصيل';
    }
    if (pending > 0) return '$pending تغييراً معلقاً — اضغط للمزامنة';
    if (status == SyncStatus.success) return 'تمت المزامنة بنجاح';
    if (checked && connection.isD1Connected == true) {
      final ms = connection.d1LatencyMs;
      return 'اتصال Cloudflare سليم — D1 يستجيب'
          '${ms == null ? '' : ' ($ms ms)'} — اضغط لإدارة تسجيل الدخول';
    }
    return 'اتصال Cloudflare — اضغط لإدارة تسجيل الدخول';
  }

  Widget _iconFor(
    BuildContext context,
    SyncStatus status,
    int pending,
    bool gateBusy,
    SyncPullProgress progress,
    bool cloudUnreachable,
    bool d1Down,
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
    // ✅ فحص الإقلاع مكتمل والسحابة غير قابلة للوصول — أعلى أولوية بعد
    // المزامنة الجارية: كل ما بعده معلومات قديمة على أي حال.
    if (cloudUnreachable) {
      return const Icon(Icons.cloud_off, color: Colors.red, size: 22);
    }
    if (status == SyncStatus.failed) {
      return const Icon(Icons.cloud_off, color: Colors.orange, size: 22);
    }
    if (d1Down) {
      return const Icon(Icons.cloud, color: Colors.orange, size: 22);
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
