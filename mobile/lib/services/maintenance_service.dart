import '../utils/debug_log.dart';
import 'cloudflare_sync_manager.dart';
import 'unified_sync_orchestrator.dart';

/// خدمة الصيانة — تُجمّع عمليات الصيانة المتعددة الخطوات في method واحد
/// حتى تبقى الشاشات مركّزة على التعامل مع واجهة المستخدم فقط.
class MaintenanceService {
  factory MaintenanceService() => _instance;
  MaintenanceService._internal();
  static final MaintenanceService _instance = MaintenanceService._internal();
  static MaintenanceService get instance => _instance;

  /// إعادة تعيين المزامنة بالكامل:
  /// 1. reset الحالة في Cloudflare
  /// 2. reset أخطاء الـ outbox (يتم عبر المُعامل الخارجي)
  /// 3. بدء مزامنة جديدة
  Future<void> resetSyncAndResync({
    Future<void> Function()? resetOutboxErrors,
  }) async {
    try {
      final cloudflareManager = CloudflareSyncManager.instance;
      final orchestrator = UnifiedSyncOrchestrator.instance;
      if (orchestrator.isSyncing) {
        throw StateError('توجد دورة Cloudflare قيد التنفيذ؛ أعد المحاولة لاحقاً');
      }

      await cloudflareManager.resetSyncState();

      if (resetOutboxErrors != null) {
        await resetOutboxErrors();
      }

      final success = await orchestrator.syncNow(
        reason: 'maintenance_reset',
      );
      if (!success) {
        throw StateError('فشلت دورة Cloudflare بعد إعادة تعيين المؤشرات');
      }

      dlog('✅ MaintenanceService: Cloudflare reset and resync completed');
    } catch (e) {
      dlog(() => '❌ MaintenanceService: reset failed: $e');
      rethrow;
    }
  }
}
