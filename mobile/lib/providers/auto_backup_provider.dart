import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auto_backup_manager.dart';
import '../services/google_drive_backup_service.dart';

/// Provider لخدمة Google Drive backup
final googleDriveBackupServiceProvider = Provider<GoogleDriveBackupService>((ref) {
  return GoogleDriveBackupService();
});

/// Provider لمدير النسخ التلقائي
final autoBackupManagerProvider = Provider<AutoBackupManager>((ref) {
  return AutoBackupManager.instance;
});

/// Provider لحالة النسخ التلقائي
final autoBackupStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final manager = ref.watch(autoBackupManagerProvider);
  return await manager.getStatus();
});

/// Provider لتهيئة النسخ التلقائي
final autoBackupInitProvider = FutureProvider<void>((ref) async {
  final manager = ref.watch(autoBackupManagerProvider);
  final backupService = ref.watch(googleDriveBackupServiceProvider);
  
  await manager.initialize(backupService);
});