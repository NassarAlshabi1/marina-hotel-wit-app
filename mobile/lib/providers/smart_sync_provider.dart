import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/smart_sync_manager.dart';
import '../services/google_drive_backup_service.dart';

/// Provider لمدير المزامنة الذكية
final smartSyncManagerProvider = Provider<SmartSyncManager>((ref) {
  return SmartSyncManager.instance;
});

/// Provider لحالة المزامنة الذكية
final smartSyncStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final manager = ref.watch(smartSyncManagerProvider);
  return await manager.getStatus();
});

/// Provider لتهيئة المزامنة الذكية
final smartSyncInitProvider = FutureProvider<void>((ref) async {
  final manager = ref.watch(smartSyncManagerProvider);
  final backupService = GoogleDriveBackupService();
  
  await manager.initialize(backupService);
});