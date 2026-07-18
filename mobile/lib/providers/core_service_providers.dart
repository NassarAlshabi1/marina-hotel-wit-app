// lib/providers/core_service_providers.dart
// مزودات Riverpod للخدمات الأساسية المستخدمة في الشاشات
// هذا الملف يساعد في إزالة استيرادات services المباشرة من الشاشات

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/booking_derived_fields_service.dart';
import '../services/auth_local_store.dart';
import '../services/salary_entitlement_service.dart';
import '../services/stay_balance_calculator.dart';
import '../services/price_adjustment_service.dart';
import '../services/screen_sync_controller.dart';
import '../services/gemini_service.dart';
import '../services/google_drive_auto_sync_engine.dart';
import '../services/google_drive_conflict_resolver.dart';
import '../services/alarm_backup.dart';
import '../services/appwrite_logger.dart';
import '../services/google_drive_backup_service.dart';
import '../services/booking_price_adjustment_service.dart';
import '../services/repositories/payments_repository.dart';
import '../services/secondary_appwrite_config.dart';
import '../services/secondary_sync_manager.dart';
import '../services/secondary_appwrite_service.dart';
import '../services/secondary_backup_service.dart';
import '../services/appwrite_sync_manager.dart';
import '../services/sync_guardian.dart';
import '../services/conflict_manager.dart';
import '../services/daos/sync_log_dao.dart';
import '../services/sync_performance_settings.dart';
import '../services/whatsapp_service.dart';
import '../services/whatsapp_settings_sync.dart';
import '../services/local_backup_service.dart';

/// مزود خدمة الحقول المشتقة للحجز
final bookingDerivedFieldsServiceProvider = Provider<BookingDerivedFieldsService>((ref) {
  final db = ref.read(databaseProvider);
  return BookingDerivedFieldsService(db);
});

/// مزود خدمة المصادقة المحلية
final authLocalStoreProvider = Provider<AuthLocalStore>((ref) {
  return AuthLocalStore();
});

/// مزود خدمة استحقاقات الرواتب
final salaryEntitlementServiceProvider = Provider<SalaryEntitlementService>((ref) {
  final db = ref.read(databaseProvider);
  return SalaryEntitlementService(db);
});

/// مزود حاسبة رصيد الإقامة
final stayBalanceCalculatorProvider = Provider<StayBalanceCalculator>((ref) {
  final db = ref.read(databaseProvider);
  return StayBalanceCalculator(db);
});

/// مزود خدمة تعديل الأسعار
final priceAdjustmentServiceProvider = Provider<PriceAdjustmentService>((ref) {
  final db = ref.read(databaseProvider);
  return PriceAdjustmentService(db);
});

/// مزود متحكم مزامنة الشاشة
final screenSyncControllerProvider = Provider<ScreenSyncController>((ref) {
  final db = ref.read(databaseProvider);
  return ScreenSyncController(db);
});

/// مزود خدمة Gemini AI
final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService.instance;
});

/// مزود محرك مزامنة Google Drive التلقائي
final googleDriveAutoSyncEngineProvider = Provider<GoogleDriveAutoSyncEngine>((ref) {
  final service = GoogleDriveAutoSyncEngine.instance;
  ref.onDispose(service.dispose);
  return service;
});

/// مزود محلل تعارضات Google Drive
final googleDriveConflictResolverProvider = Provider<GoogleDriveConflictResolver>((ref) {
  return GoogleDriveConflictResolver.instance;
});

/// مزود إنذار النسخ الاحتياطي
final alarmBackupProvider = Provider<AlarmBackup>((ref) {
  return AlarmBackup.instance;
});

/// مزود مسجل Appwrite
final appwriteLoggerProvider = Provider<AppwriteLogger>((ref) {
  return AppwriteLogger.instance;
});

/// مزود خدمة النسخ الاحتياطي على Google Drive
final googleDriveBackupServiceProvider = Provider<GoogleDriveBackupService>((ref) {
  return GoogleDriveBackupService.instance;
});

/// مزود خدمة تعديل أسعار الحجز
final bookingPriceAdjustmentServiceProvider = Provider<BookingPriceAdjustmentService>((ref) {
  final db = ref.read(databaseProvider);
  return BookingPriceAdjustmentService(db);
});

/// مزود مستودع المدفوعات
final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  final db = ref.read(databaseProvider);
  return PaymentsRepository(db);
});

/// مزود إعدادات Appwrite الثانوية
final secondaryAppwriteConfigProvider = Provider<SecondaryAppwriteConfig>((ref) {
  return SecondaryAppwriteConfig.instance;
});

/// مزود مدير المزامنة الثانوية
final secondarySyncManagerProvider = Provider<SecondarySyncManager>((ref) {
  return SecondarySyncManager.instance;
});

/// مزود خدمة Appwrite الثانوية
final secondaryAppwriteServiceProvider = Provider<SecondaryAppwriteService>((ref) {
  return SecondaryAppwriteService.instance;
});

/// مزود خدمة النسخ الاحتياطي الثانوي
final secondaryBackupServiceProvider = Provider<SecondaryBackupService>((ref) {
  return SecondaryBackupService.instance;
});

/// مزود مدير مزامنة Appwrite
final appwriteSyncManagerProvider2 = Provider<AppwriteSyncManager>((ref) {
  final service = ref.read(appwriteServiceProvider);
  final database = ref.read(databaseProvider);
  final manager = AppwriteSyncManager(appwriteService: service, database: database);
  ref.onDispose(manager.dispose);
  return manager;
});

/// مزود حارس المزامنة
final syncGuardianProvider2 = Provider<SyncGuardian>((ref) {
  return SyncGuardian.instance;
});

/// مزود مدير التعارضات
final conflictManagerProvider = Provider<ConflictManager>((ref) {
  return ConflictManager.instance;
});

/// مزود DAO سجلات المزامنة
final syncLogDaoProvider = Provider<SyncLogDao>((ref) {
  final db = ref.read(databaseProvider);
  return SyncLogDao(db);
});

/// مزود إعدادات أداء المزامنة
final syncPerformanceSettingsProvider = Provider<SyncPerformanceSettings>((ref) {
  return SyncPerformanceSettings.instance;
});

/// مزود خدمة WhatsApp
final whatsappServiceProvider = Provider<WhatsAppService>((ref) {
  return WhatsAppService.instance;
});

/// مزود إعدادات مزامنة WhatsApp
final whatsappSettingsSyncProvider = Provider<WhatsAppSettingsSync>((ref) {
  return WhatsAppSettingsSync.instance;
});

/// مزود خدمة النسخ الاحتياطي المحلي
final localBackupServiceProvider = Provider<LocalBackupService>((ref) {
  return LocalBackupService.instance;
});
