import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/smart_sync_manager.dart';
import 'backup_provider.dart';

/// Provider لمدير المزامنة الذكية
final smartSyncManagerProvider = Provider<SmartSyncManager>((ref) {
  return SmartSyncManager.instance;
});

/// Provider لحالة المزامنة الذكية - يستمع لتغييرات حالة الاتصال
final smartSyncStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final manager = ref.watch(smartSyncManagerProvider);
  
  // استمع لتغييرات حالة تسجيل الدخول في Google Drive من المصدر الموحد
  final isSignedIn = ref.watch(smartSyncGoogleDriveSignInStatusProvider);
  
  final status = await manager.getStatus();
  // تحديث حالة تسجيل الدخول من المصدر الموحد
  status['signed_in'] = isSignedIn;
  
  return status;
});

/// Provider لحالة تسجيل الدخول Google Drive - مصدر الحقيقة الموحد
final smartSyncGoogleDriveSignInStatusProvider = Provider<bool>((ref) {
  // قراءة من المصدر الأساسي مباشرة
  final backupService = ref.watch(googleDriveBackupServiceProvider);
  return backupService.isSignedIn;
});

/// Provider لتهيئة المزامنة الذكية مع فحص حالة تسجيل الدخول
final smartSyncInitProvider = FutureProvider<void>((ref) async {
  final manager = ref.watch(smartSyncManagerProvider);
  final backupService = ref.watch(googleDriveBackupServiceProvider);
  
  // انتظار تهيئة BackupProvider أولاً
  await Future.delayed(const Duration(milliseconds: 500));
  
  await manager.initialize(backupService);
});