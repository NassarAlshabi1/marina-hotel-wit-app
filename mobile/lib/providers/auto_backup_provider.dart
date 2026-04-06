import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auto_backup_manager.dart' show AutoBackupManager;
import 'backup_provider.dart'; // استيراد Provider الموجود
import 'appwrite_providers.dart'; // AppwriteService + connectionStatus
import 'repository_providers.dart'; // databaseProvider

/// Provider لمدير النسخ التلقائي
final autoBackupManagerProvider = Provider<AutoBackupManager>((ref) {
  return AutoBackupManager.instance;
});

/// Provider لحالة النسخ التلقائي
final autoBackupStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final manager = ref.watch(autoBackupManagerProvider);
      return await manager.getStatus();
    });

/// Provider لتهيئة النسخ التلقائي (مع تهيئة DeltaSync دائماً)
final autoBackupInitProvider = FutureProvider<void>((ref) async {
  final manager = ref.watch(autoBackupManagerProvider);
  final backupService = ref.watch(
    googleDriveBackupServiceProvider,
  );
  final appwriteService = ref.watch(appwriteServiceProvider);
  final database = ref.watch(databaseProvider);

  await manager.initialize(
    backupService,
    appwriteService: appwriteService,
    database: database,
  );
});
