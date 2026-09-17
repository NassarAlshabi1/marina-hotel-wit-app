import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/appwrite_providers.dart';
import '../services/sync_enums.dart';
import 'snackbar_helper.dart';

/// ✅ إصلاح (مراجعة "Delta Sync × Cloudflare"، DELTA_SYNC_CLOUDFLARE_REVIEW.md
/// بند #1): عدة شاشات كانت تربط زر "مزامنة" / سحب-للتحديث بـ `SyncService`
/// القديم (`sync_service.dart`) — مسار REST/PHP قديم معطّل بالكامل
/// (`Env.baseApiUrl` فارغ افتراضياً ما لم يُمرَّر BASE_API_URL وقت البناء)
/// ومنفصل كلياً عن `CloudflareSyncManager` الفعلي (لا استدعاء واحد لـ
/// DeltaSyncService/SyncService من داخل cloudflare_sync_manager.dart).
///
/// النتيجة السابقة: ضغط الزر يستدعي `Future` غير منتظر وغير مُعالَج
/// بـ try/catch، فيفشل بصمت (خطأ شبكي فوري) دون أي مزامنة حقيقية مع
/// Cloudflare D1 ودون أي تغذية راجعة للمستخدم.
///
/// هذه الدالة الموحّدة تستبدل كل تلك الاستدعاءات: تُنفّذ دورة مزامنة
/// Cloudflare حقيقية (دفع + سحب، مع forcePull لتجاوز تبريد الدخول الكسول
/// عند طلب المستخدم الصريح — نفس عقد أزرار لوحة التحكم في
/// dashboard_sync_button.dart) وتُظهر نتيجة حقيقية — نجاح أو فشل فعلي —
/// بدل الوهم الصامت السابق.
Future<void> triggerManualCloudflareSync(
  BuildContext context,
  WidgetRef ref, {
  bool showSuccessSnackbar = true,
}) async {
  try {
    final result = await ref
        .read(appwriteSyncManagerProvider)
        .sync(forcePull: true);
    if (!context.mounted) return;

    if (result.isSuccess) {
      if (showSuccessSnackbar) {
        SnackBarHelper.showSuccess(context, '✅ تمت المزامنة بنجاح');
      }
      return;
    }

    if (result.status == SyncStatus.idle) {
      // ليست فشلاً حقيقياً: مزامنة أخرى قيد التنفيذ بالفعل، أو المزامنة
      // معطّلة عن بُعد/محلياً (kill switch) — تنبيه تحذيري لا خطأ أحمر.
      SnackBarHelper.showWarning(
        context,
        result.errorMessage ?? 'المزامنة قيد التنفيذ بالفعل',
      );
      return;
    }

    SnackBarHelper.showError(
      context,
      '⚠️ فشلت المزامنة: ${result.errorMessage ?? result.status.name}',
    );
  } catch (e) {
    if (!context.mounted) return;
    SnackBarHelper.showError(context, '❌ خطأ أثناء المزامنة: $e');
  }
}
