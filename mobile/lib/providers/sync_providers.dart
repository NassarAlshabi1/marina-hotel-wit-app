import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/appwrite_service.dart';
import '../services/appwrite_sync_manager.dart';
import '../services/daos/outbox_dao.dart';
import '../services/sync_core/sync_error_service.dart';
import '../services/sync_core/sync_pull_service.dart';
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

/// ✅ P3-6 (Conflict Visibility): عدد التعارضات المعلقة في قاعدة البيانات.
///
/// يستخدم drift's `.watch()` لمراقبة جدول `sync_conflicts` تلقائياً —
/// أي إضافة صف جديد أو حلّ تعارض سيُحدّث العدد فوراً في الـ UI دون
/// إعادة تحميل.
///
/// التعارض "المعلّق" = صف في sync_conflicts حيث `resolution` فارغ.
/// (مطابق تماماً لمنطق ConflictManager.loadPendingConflicts.)
final pendingConflictsCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  // count rows in syncConflicts where resolution = ''
  final query = db
      .selectOnly(db.syncConflicts)
      ..addColumns([db.syncConflicts.id.count()])
      ..where(db.syncConflicts.resolution.equals(''));
  return query.watchSingle().map((row) => row.read(db.syncConflicts.id.count()) ?? 0);
});
