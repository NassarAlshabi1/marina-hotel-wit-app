import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_db.dart';
import '../services/daos/sync_log_dao.dart';
import 'repository_providers.dart';

/// فلتر لسجل المزامنة
class SyncFilter {
  const SyncFilter({
    this.limit = 100,
    this.offset = 0,
    this.direction,
    this.status,
  });
  
  final int limit;
  final int offset;
  final String? direction; // 'pull', 'push', 'bidirectional'
  final String? status; // 'success', 'failed', 'in_progress'
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncFilter &&
          runtimeType == other.runtimeType &&
          limit == other.limit &&
          offset == other.offset &&
          direction == other.direction &&
          status == other.status;

  @override
  int get hashCode =>
      limit.hashCode ^ offset.hashCode ^ direction.hashCode ^ status.hashCode;
}

/// Provider لسجل المزامنة
final syncHistoryProvider =
    FutureProvider.family<List<SyncLogEntry>, SyncFilter>(
  (ref, filter) async {
    final db = ref.read(databaseProvider);
    final dao = SyncLogDao(db);
    return dao.getSyncHistory(
      limit: filter.limit,
      offset: filter.offset,
      direction: filter.direction,
      status: filter.status,
    );
  },
);

/// Provider لإحصائيات سجل المزامنة
final syncLogStatsProvider = FutureProvider<SyncStats>((ref) async {
  final db = ref.read(databaseProvider);
  final dao = SyncLogDao(db);
  return dao.getSyncStats();
});

/// Provider لآخر عملية مزامنة
final lastSyncProvider = FutureProvider<SyncLogEntry?>((ref) async {
  final db = ref.read(databaseProvider);
  final dao = SyncLogDao(db);
  return dao.getLastSync();
});

/// Provider لعدد السجلات
final syncLogCountProvider = FutureProvider<int>((ref) async {
  final db = ref.read(databaseProvider);
  final dao = SyncLogDao(db);
  return dao.count();
});

/// Stream لمراقبة السجلات الجديدة
final watchRecentSyncLogsProvider = StreamProvider.family<List<SyncLogEntry>, int>(
  (ref, limit) {
    final db = ref.read(databaseProvider);
    final dao = SyncLogDao(db);
    return dao.watchRecentLogs(limit: limit);
  },
);
