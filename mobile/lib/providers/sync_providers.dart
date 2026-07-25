// lib/providers/sync_providers.dart
// مزودات Riverpod لخدمات المزامنة العامة

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sync/sync_gate.dart';
import '../services/sync_constants.dart';

/// مزود بوابة المزامنة العامة (Singleton)
final syncGateProvider = Provider<SyncGate>((ref) {
  return SyncGate.instance;
});

/// مزود ما إذا كانت المزامنة مشغولة
final syncIsBusyProvider = Provider<bool>((ref) {
  final gate = ref.watch(syncGateProvider);
  return gate.isBusy;
});

/// مزود مفتاح SharedPreferences لآخر سحب تلقائي
final lastAppOpenPullKeyProvider = Provider<String>((ref) {
  return SyncConstants.lastAppOpenPullKey;
});

<<<<<<< HEAD
/// مزود فاصل المزامنة التلقائية عند الفتح
final appOpenSyncIntervalProvider = Provider<Duration>((ref) {
  return SyncConstants.appOpenSyncInterval;
=======
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
  );
});

/// توفير AppwriteSyncManager
final syncManagerProvider = Provider<AppwriteSyncManager>((ref) {
  return AppwriteSyncManager(appwriteService: ref.read(appwriteServiceProvider), database: ref.read(databaseProvider));
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
  final query = db.selectOnly(db.syncConflicts)
    ..addColumns([db.syncConflicts.id.count()])
    ..where(db.syncConflicts.resolution.equals(''));
  return query.watchSingle().map((row) => row.read(db.syncConflicts.id.count()) ?? 0);
>>>>>>> origin/refactor/clean-v2
});
