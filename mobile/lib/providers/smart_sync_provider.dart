import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/smart_sync_manager.dart' show SmartSyncManager;
import 'backup_provider.dart';

/// Provider لمدير المزامنة الذكية
final smartSyncManagerProvider = Provider<SmartSyncManager>((ref) {
  return SmartSyncManager.instance;
});

/// Provider لحالة المزامنة الذكية
final smartSyncStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final manager = ref.watch(smartSyncManagerProvider);

  // استمع لتغييرات حالة تسجيل الدخول في Google Drive
  ref.watch(smartSyncGoogleDriveSignInStatusProvider);

  return manager.getStatus();
});

/// Provider لحالة تسجيل الدخول Google Drive (في smart_sync_provider)
final smartSyncGoogleDriveSignInStatusProvider = Provider<bool>((ref) {
  final backupState = ref.watch(backupStatusProvider);
  return backupState.signedInAccount != null;
});

/// Provider لتهيئة المزامنة الذكية مع فحص حالة تسجيل الدخول
/// ✅ إصلاح: استبدال Future.delayed بالاستماع الصحيح لحالة تسجيل الدخول
final smartSyncInitProvider = FutureProvider<void>((ref) async {
  final manager = ref.watch(smartSyncManagerProvider);
  final backupService = ref.watch(googleDriveBackupServiceProvider);

  // انتظار تهيئة BackupProvider من خلال مراقبة حالة تسجيل الدخول
  // بدلاً من Future.delayed الذي قد لا يكفي أو يكون طويلاً بلا داع
  final signInState = ref.watch(smartSyncGoogleDriveSignInStatusProvider);
  if (!signInState) {
    // لا نهيئ المزامنة بدون تسجيل دخول — سيعاد الحساب عند تغيير الحالة
    return;
  }

  await manager.initialize(backupService);
});
