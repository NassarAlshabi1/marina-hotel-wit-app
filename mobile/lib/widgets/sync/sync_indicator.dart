// ═══════════════════════════════════════════════════════════════
//  sync_indicator.dart — مؤشر حالة المزامنة الحيّ في شريط التطبيق
//  ✅ (2026-09-10) إصلاح «مؤشرات المزامنة لا تعمل»:
//
//  الجذر: النسخة القديمة كانت تستمع إلى `syncStateProvider` من
//  SyncOrchestrator — مكوّن لا يُهيّأ في التطبيق أبداً (لا adapters
//  تُسجَّل ولا أحد يستدعي initialize) فبقي المؤشر فارغاً إلى الأبد،
//  بينما التدفق الحقيقي (CloudflareSyncManager.syncStatusStream الذي
//  يبثّ syncing/success/failed/idle من دورة sync() الفعلية) لم يكن
//  يستمعه أحد.
//
//  الآن: SyncIndicator يستمع إلى cloudflareSyncStatusProvider
//  (جسر Riverpod فوق التدفق الحقيقي) + عدّاد الـ Outbox — وعند
//  الفشل/عدم تسجيل الدخول يفتح شاشة تسجيل الدخول إلى Cloudflare
//  (CloudflareLoginScreen) بنقرة واحدة.
// ═══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/appwrite_providers.dart';
import '../../screens/auth/cloudflare_login_screen.dart';
import '../../services/appwrite_sync_manager.dart' show SyncStatus;
import '../../services/sync/sync_gate.dart';

/// مؤشر حالة المزامنة الحيّ — يُعرض في AppBar الرئيسي.
///
/// حالة العرض (بالأولوية):
///  1. مزامنة جارية (syncing) → قرص دوّار + عدّاد التغييرات المعلقة
///  2. مزامنة مزروعة في بوابة SyncGate (عملية أخرى شغّالة) → قرص دوّار
///  3. فشل آخر دورة (failed) → أيقونة تحذير برتقالية — نقرة تفتح شاشة
///     تسجيل الدخول/التشخيص
///  4. تغييرات محلية معلّقة (outbox > 0) → شارة عدّاد زرقاء على أيقونة
///     السحابة
///  5. آخر دورة نجحت (success) → صحّة خضراء (تُثبَّت حتى idle التالية)
///  6. خامل (idle) → سحابة خضراء «متصل»
///
/// نقرة على المؤشر تفتح شاشة تسجيل الدخول إلى Cloudflare دائماً.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(cloudflareSyncStatusProvider);
    final pendingAsync = ref.watch(outboxCountProvider);

    // الحالة الفعّالة: نُبقي آخر success ظاهراً أثناء idle (لأن المدير
    // يعيد idle بعد كل دورة) — map بسيط بلا مؤقّتات ولا setState.
    final status = statusAsync.when(
      data: (s) => s,
      loading: () => SyncStatus.idle,
      error: (_, __) => SyncStatus.failed,
    );
    final pending = pendingAsync.asData?.value ?? 0;
    final gateBusy = SyncGate.instance.state.isBusy;

    return Tooltip(
      message: _tooltipFor(status, pending, gateBusy),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: () => _openLoginScreen(context),
        icon: _iconFor(context, status, pending, gateBusy),
      ),
    );
  }

  void _openLoginScreen(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const CloudflareLoginScreen(),
        ),
      ),
    );
  }

  String _tooltipFor(SyncStatus status, int pending, bool gateBusy) {
    if (status == SyncStatus.syncing || gateBusy) return 'جاري المزامنة...';
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
  ) {
    final theme = Theme.of(context);
    if (status == SyncStatus.syncing || gateBusy) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
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
