import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auto_backup_manager.dart' show AutoBackupManager;
import 'appwrite_providers.dart' show connectionStatusProvider;
import 'repository_providers.dart'; // databaseProvider

/// Provider لمدير النسخ التلقائي
final autoBackupManagerProvider = Provider<AutoBackupManager>((ref) {
  return AutoBackupManager.instance;
});

/// Provider لحالة النسخ التلقائي
final autoBackupStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final manager = ref.watch(autoBackupManagerProvider);
      return manager.getStatus();
    });

/// Provider لتهيئة النسخ التلقائي (مع تهيئة DeltaSync دائماً)
final autoBackupInitProvider = FutureProvider<void>((ref) async {
  final manager = ref.read(autoBackupManagerProvider);
  final backupService = ref.read(googleDriveBackupServiceProvider);
  final database = ref.read(databaseProvider);

  await manager.initialize(backupService, database: database);
});
