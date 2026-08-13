
import 'appwrite_sync_manager.dart';
import 'unified_sync_orchestrator.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// خدمة الصيانة — تُجمّع عمليات الصيانة المتعددة الخطوات في method واحد
/// حتى تبقى الشاشات مركّزة على التعامل مع واجهة المستخدم فقط.
class MaintenanceService {
  factory MaintenanceService() => _instance;
  MaintenanceService._internal();
  static final MaintenanceService _instance = MaintenanceService._internal();
  static MaintenanceService get instance => _instance;

  /// إعادة تعيين المزامنة بالكامل:
  /// 1. reset الحالة في Appwrite
  /// 2. reset أخطاء الـ outbox (يتم عبر المُعامل الخارجي)
  /// 3. بدء مزامنة جديدة
  Future<void> resetSyncAndResync({
    Future<void> Function()? resetOutboxErrors,
  }) async {
    try {
      final appwriteManager = AppwriteSyncManager.instance;
      if (appwriteManager == null) {
        dlog('⚠️ MaintenanceService: AppwriteSyncManager not initialized');
        return;
      }

      await appwriteManager.resetSyncState();

      if (resetOutboxErrors != null) {
        await resetOutboxErrors();
      }

      await UnifiedSyncOrchestrator.instance.syncNow(
        reason: 'maintenance_reset',
      );

      dlog('✅ MaintenanceService: Sync reset and resync completed');
    } catch (e) {
      dlog(() => '❌ MaintenanceService: reset failed: $e');
      rethrow;
    }
  }
}
