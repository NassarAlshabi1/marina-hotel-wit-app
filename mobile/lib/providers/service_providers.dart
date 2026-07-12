// ============================================================================
// 🔄 ملاحظة الترحيل — Migration Note
// ============================================================================
// هذا الملف يحتوي على مزودات Riverpod لخدمات النظام الأساسية.
// الغرض منه تسهيل الانتقال التدريجي من أنماط Singleton إلى Riverpod.
//
// ⚠️ قواعد مهمة:
// 1. لا تُعدِّل أي كود حالي — أضف المزودات بجانب الـ Singletons الموجودة.
// 2. الكود القديم الذي يستخدم ClassName.instance أو ClassName() سيستمر بالعمل.
// 3. يمكنك استخدام المزودات الجديدة تدريجياً في الشاشات الجديدة.
// 4. عند استخدام مزود جديد، تأكد أن الخدمة تُهيأ عبر ref.onDispose عند الحاجة.
//
// 📋 الخدمات المُغطاة:
// 1. AppwriteService       — CRUD مع Appwrite (مُعرَّف أصلاً في appwrite_providers)
// 2. GoogleDriveBackupService — نسخ احتياطي على Google Drive
// 3. AnalyticsService       — تحليلات Firebase ومراقبة المزامنة
// 4. ConnectivityService    — مراقبة حالة الاتصال بالشبكة
// 5. DiagnosticsLogger      — تسجيل الأخطاء والتشخيصات
// 6. GeminiService          — خدمة الذكاء الاصطناعي Gemini
// 7. CrashlyticsService     — تسجيل الأخطاء عبر Crashlytics
// 8. NightAuditService      — خدمة التدقيق الليلي
// 9. SyncOrchestrator       — منسق المزامنة العام
// 10. SyncPerformanceOptimizer — مُحسّن أداء المزامنة
// 11. DataUsageManager      — مُدير استخدام البيانات
// 12. CentralSyncCoordinator — منسق المزامنة المركزي
// 13. SyncHealthMonitor     — مراقب صحة المزامنة
// 14. SecondaryBackupService — خدمة النسخ الاحتياطي الثانوي
//
// 🔗 للانتقال: استبدل `ServiceName.instance` بـ `ref.read(serviceNameProvider)`
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/analytics_service.dart';
import '../services/central_sync_coordinator.dart';
import '../services/connectivity_service.dart';
import '../services/crashlytics_service.dart';
import '../services/data_usage_manager.dart';
import '../services/gemini_service.dart';
import '../services/night_audit_service.dart';
import '../services/secondary_backup_service.dart';
import '../services/sync_health_monitor.dart';
import '../services/sync_orchestrator.dart';
import '../services/sync_performance_optimizer.dart';

// إعادة تصدير appwriteServiceProvider من appwrite_providers لتجنب التعارض
// لأنه مُعرَّف هناك بالفعل مع مزودات أخرى تعتمد عليه.
export 'appwrite_providers.dart' show appwriteServiceProvider;
// إعادة تصدير googleDriveBackupServiceProvider من backup_provider
// لأنه مُعرَّف هناك بالفعل مع ref.keepAlive() ويُستخدم في مزودات أخرى.
export 'backup_provider.dart' show googleDriveBackupServiceProvider;
// إعادة تصدير diagnosticsLoggerProvider من repository_providers
// لأنه مُعرَّف هناك بالفعل كـ ChangeNotifierProvider.
export 'repository_providers.dart' show diagnosticsLoggerProvider;

// ============================================================================
// مزود خدمة التحليلات
// ============================================================================
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});

// ============================================================================
// مزود خدمة الاتصال
// ============================================================================
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService.instance;
  ref.onDispose(service.dispose);
  return service;
});

// ============================================================================
// مزود خدمة Gemini AI
// ============================================================================
final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService.instance;
});

// ============================================================================
// مزود خدمة Crashlytics
// ============================================================================
final crashlyticsServiceProvider = Provider<CrashlyticsService>((ref) {
  return CrashlyticsService.instance;
});

// ============================================================================
// مزود خدمة التدقيق الليلي
// ============================================================================
final nightAuditServiceProvider = Provider<NightAuditService>((ref) {
  return NightAuditService.instance;
});

// ============================================================================
// مزود منسق المزامنة العام
// ============================================================================
final syncOrchestratorProvider = Provider<SyncOrchestrator>((ref) {
  return SyncOrchestrator.instance;
});

// ============================================================================
// مزود مُحسّن أداء المزامنة
// ============================================================================
final syncPerformanceOptimizerProvider = Provider<SyncPerformanceOptimizer>((ref) {
  return SyncPerformanceOptimizer.instance;
});

// ============================================================================
// مزود مُدير استخدام البيانات
// ============================================================================
final dataUsageManagerProvider = Provider<DataUsageManager>((ref) {
  return DataUsageManager.instance;
});

// ============================================================================
// مزود منسق المزامنة المركزي
// ============================================================================
final centralSyncCoordinatorProvider = Provider<CentralSyncCoordinator>((ref) {
  return CentralSyncCoordinator.instance;
});

// ============================================================================
// مزود مراقب صحة المزامنة
// ============================================================================
final syncHealthMonitorProvider = Provider<SyncHealthMonitor>((ref) {
  return SyncHealthMonitor.instance;
});

// ============================================================================
// مزود خدمة النسخ الاحتياطي الثانوي
// ============================================================================
final secondaryBackupServiceProvider = Provider<SecondaryBackupService>((ref) {
  return SecondaryBackupService.instance;
});
