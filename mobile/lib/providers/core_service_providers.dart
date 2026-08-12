import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/alarm_backup.dart';
import '../services/appwrite_logger.dart';
import '../services/appwrite_sync_manager.dart';
import '../services/auth_local_store.dart';
import '../services/booking_derived_fields_service.dart';
import '../services/booking_price_adjustment_service.dart';
import '../services/conflict_manager.dart';
import '../services/daos/sync_log_dao.dart';
import '../services/gemini_service.dart';
import '../services/google_drive_backup_service.dart';
import '../services/google_drive_conflict_resolver.dart';
import '../services/local_backup_service.dart';
import '../services/price_adjustment_service.dart';
import '../services/repositories/payments_repository.dart';
import '../services/salary_entitlement_service.dart';
import '../services/screen_sync_controller.dart';
import '../services/secondary_appwrite_config.dart';
import '../services/secondary_appwrite_service.dart';
import '../services/secondary_backup_service.dart';
// ✅ Wave 5 (2026-08-12): secondary_sync_manager.dart أُزيل بالكامل.
import '../services/stay_balance_calculator.dart';
import '../services/sync_guardian.dart';
import '../services/sync_performance_settings.dart';
import '../services/whatsapp_service.dart';
import '../services/whatsapp_settings_sync.dart';
import 'appwrite_providers.dart';
import 'repository_providers.dart';

final bookingDerivedFieldsServiceProvider =
    Provider<BookingDerivedFieldsService>((ref) {
      final db = ref.read(databaseProvider);
      return BookingDerivedFieldsService(db);
    });

final authLocalStoreProvider = Provider<AuthLocalStore>((ref) {
  return AuthLocalStore();
});

final salaryEntitlementServiceProvider = Provider<SalaryEntitlementService>((
  ref,
) {
  final db = ref.read(databaseProvider);
  return SalaryEntitlementService(db);
});

final stayBalanceCalculatorProvider = Provider<StayBalanceCalculator>((ref) {
  return const StayBalanceCalculator();
});

final priceAdjustmentServiceProvider = Provider<PriceAdjustmentService>((ref) {
  final db = ref.read(databaseProvider);
  return PriceAdjustmentService(db);
});

final screenSyncControllerProvider =
    Provider.family<ScreenSyncController, String>((ref, screenId) {
      return ScreenSyncController(screenId: screenId);
    });

final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService.instance;
});

final googleDriveConflictResolverProvider =
    Provider<GoogleDriveConflictResolver>((ref) {
      return GoogleDriveConflictResolver.instance;
    });

final alarmBackupProvider = Provider<AlarmBackup>((ref) {
  return AlarmBackup();
});

final appwriteLoggerProvider = Provider<AppwriteLogger>((ref) {
  return AppwriteLogger();
});

final googleDriveBackupServiceProvider = Provider<GoogleDriveBackupService>((
  ref,
) {
  return GoogleDriveBackupService();
});

final bookingPriceAdjustmentServiceProvider =
    Provider<BookingPriceAdjustmentService>((ref) {
      final db = ref.read(databaseProvider);
      return BookingPriceAdjustmentService(db);
    });

final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  final db = ref.read(databaseProvider);
  return PaymentsRepository(db);
});

final secondaryAppwriteConfigProvider = Provider<SecondaryAppwriteConfig>((
  ref,
) {
  return SecondaryAppwriteConfig();
});

// ✅ Wave 5 (2026-08-12): secondarySyncManagerProvider أُزيل بالكامل.
// SecondarySyncManager لم يعد موجوداً — Appwrite primary هو authority الوحيد.
// secondaryAppwriteService و secondaryBackupService ما زالا موجودتين لأن
// AppwriteHealthChecker يستخدمهما لفحص الـ failover (مسار قراءة فقط).

final secondaryAppwriteServiceProvider = Provider<SecondaryAppwriteService>((
  ref,
) {
  return SecondaryAppwriteService.instance;
});

final secondaryBackupServiceProvider = Provider<SecondaryBackupService>((ref) {
  return SecondaryBackupService.instance;
});

final appwriteSyncManagerProvider2 = Provider<AppwriteSyncManager>((ref) {
  final service = ref.read(appwriteServiceProvider);
  final database = ref.read(databaseProvider);
  final manager = AppwriteSyncManager(
    appwriteService: service,
    database: database,
  );
  ref.onDispose(manager.dispose);
  return manager;
});

final syncGuardianProvider2 = Provider<SyncGuardian>((ref) {
  return SyncGuardian.instance;
});

final conflictManagerProvider = Provider<ConflictManager>((ref) {
  final db = ref.read(databaseProvider);
  return ConflictManager(db);
});

final syncLogDaoProvider = Provider<SyncLogDao>((ref) {
  final db = ref.read(databaseProvider);
  return SyncLogDao(db);
});

final syncPerformanceSettingsProvider = Provider<SyncPerformanceSettings>((
  ref,
) {
  return SyncPerformanceSettings();
});

final whatsappServiceProvider = Provider<WhatsAppService>((ref) {
  return WhatsAppService(
    apiType: WhatsAppApiType.greenapi,
  );
});

final whatsappSettingsSyncProvider = Provider<WhatsAppSettingsSync>((ref) {
  final service = ref.read(appwriteServiceProvider);
  return WhatsAppSettingsSync(service);
});

final localBackupServiceProvider = Provider<LocalBackupService>((ref) {
  return LocalBackupService();
});
