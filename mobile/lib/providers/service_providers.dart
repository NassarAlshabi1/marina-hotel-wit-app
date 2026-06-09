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
// 📋 الخدمات المُغطاة (أكثر 5 خدمات استخداماً):
// 1. AppwriteService       — CRUD مع Appwrite (مُعرَّف أصلاً في appwrite_providers)
// 2. GoogleDriveBackupService — نسخ احتياطي على Google Drive
// 3. AnalyticsService       — تحليلات Firebase ومراقبة المزامنة
// 4. ConnectivityService    — مراقبة حالة الاتصال بالشبكة
// 5. DiagnosticsLogger      — تسجيل الأخطاء والتشخيصات
//
// 🔗 للانتقال: استبدل `ServiceName.instance` بـ `ref.read(serviceNameProvider)`
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/analytics_service.dart';
import '../services/connectivity_service.dart';

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
// مزود خدمة Google Drive للنسخ الاحتياطي — مُعادة تصديره من backup_provider
// ============================================================================
// googleDriveBackupServiceProvider مُعرَّف في backup_provider.dart
// مع ref.keepAlive() للمحافظة على حالة واحدة.
// يُستخدم حالياً في: backupStatusProvider، auto_backup، smart_sync.
//
// استخدام:
//   final backupService = ref.read(googleDriveBackupServiceProvider);
// ============================================================================

// ============================================================================
// مزود خدمة التحليلات
// ============================================================================
// خدمة التحليلات والتتبع عبر Firebase Analytics.
// ملاحظة: يجب استدعاء initialize() قبل الاستخدام (يتم عادةً في main.dart).
final analyticsServiceProvider = Provider.autoDispose<AnalyticsService>((ref) {
  return AnalyticsService();
});

// ============================================================================
// مزود خدمة الاتصال
// ============================================================================
// مراقبة حالة الاتصال بالشبكة (WiFi/Mobile/Ethernet).
// يتتبع تغييرات الاتصال عبر Stream ويوفر تنفيذ عند الاتصال.
// ملاحظة: يجب استدعاء initialize() بعد إنشاء المزود.
final connectivityServiceProvider = Provider.autoDispose<ConnectivityService>((ref) {
  final service = ConnectivityService.instance;
  ref.onDispose(service.dispose);
  return service;
});

// ============================================================================
// مزود مسجل التشخيصات — مُعادة تصديره من repository_providers
// ============================================================================
// diagnosticsLoggerProvider مُعرَّف في repository_providers.dart كـ
// ChangeNotifierProvider<DiagnosticsLogger> — يوفر دعم ChangeNotifier
// كاملاً مع إمكانية مراقبة التغييرات من الواجهة.
//
// استخدام:
//   final logger = ref.watch(diagnosticsLoggerProvider);
//
// ملاحظة: يجب استدعاء logger.initialize() بعد الحصول على المزود.
// ============================================================================
