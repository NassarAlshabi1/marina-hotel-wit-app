import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/appwrite_service.dart';
import '../services/appwrite_sync_manager.dart';
import '../services/daos/outbox_dao.dart';
import '../services/sync_core/sync_error_service.dart';
import '../services/sync_core/sync_pull_service.dart';
import '../services/sync_core/sync_push_service.dart';
import '../services/sync_mutex.dart';
import 'repository_providers.dart' show databaseProvider;

/// توفير خدمة Appwrite
final appwriteServiceProvider = Provider<AppwriteService>((ref) {
  return AppwriteService();
});

/// توفير OutboxDao
final outboxDaoProvider = Provider<OutboxDao>((ref) {
  return OutboxDao(ref.read(databaseProvider));
});

/// توفير SyncMutex
final syncMutexProvider = Provider<SyncMutex>((ref) {
  return SyncMutex();
});

/// توفير SyncErrorService
final syncErrorServiceProvider = Provider.family<SyncErrorService, String>((ref, tag) {
  return SyncErrorService(tag: tag);
});

/// توفير SyncPushService
final syncPushServiceProvider = Provider<SyncPushService>((ref) {
  return SyncPushService(
    appwriteService: ref.read(appwriteServiceProvider),
    database: ref.read(databaseProvider),
    outboxDao: ref.read(outboxDaoProvider),
    errorService: ref.read(syncErrorServiceProvider('PUSH')),
  );
});

/// توفير SyncPullService
final syncPullServiceProvider = Provider<SyncPullService>((ref) {
  return SyncPullService(
    appwriteService: ref.read(appwriteServiceProvider),
    database: ref.read(databaseProvider),
    outboxDao: ref.read(outboxDaoProvider),
    errorService: ref.read(syncErrorServiceProvider('PULL')),
  );
});

/// توفير AppwriteSyncManager
final syncManagerProvider = Provider<AppwriteSyncManager>((ref) {
  return AppwriteSyncManager(
    appwriteService: ref.read(appwriteServiceProvider),
    database: ref.read(databaseProvider),
  );
});
