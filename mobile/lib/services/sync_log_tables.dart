import 'package:drift/drift.dart';

/// ════════════════════════════════════════════════════════════════
/// NEW SYNC LOG TABLES FOR OPTIMIZED SYNC
/// ════════════════════════════════════════════════════════════════
/// 
/// Add these tables to your local_db.dart file to enable
/// comprehensive sync tracking and performance monitoring.
/// ════════════════════════════════════════════════════════════════

/// Tracks all sync operations with detailed metrics
class SyncLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncId => text().unique()(); // UUID for this sync operation
  TextColumn get deviceId => text()(); // Source device
  TextColumn get syncType => text()(); // 'delta', 'full', 'conflict_resolve'
  TextColumn get direction => text()(); // 'upload', 'download', 'bidirectional'
  IntColumn get startTimestamp => integer()();
  IntColumn get endTimestamp => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get recordsUploaded => integer().withDefault(const Constant(0))();
  IntColumn get recordsDownloaded => integer().withDefault(const Constant(0))();
  IntColumn get conflictsResolved => integer().withDefault(const Constant(0))();
  IntColumn get dataSizeBytes => integer().nullable()(); // Uncompressed
  IntColumn get compressedSizeBytes => integer().nullable()(); // Compressed
  RealColumn get compressionRatio => real().nullable()(); // % reduction
  TextColumn get status => text()(); // 'in_progress', 'completed', 'failed'
  TextColumn get errorMessage => text().nullable()();
  TextColumn get networkType => text().nullable()(); // 'wifi', 'mobile', 'ethernet'
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  
  @override
  List<Index> get indexes => [
    Index('idx_sync_log_device', [deviceId]),
    Index('idx_sync_log_timestamp', [startTimestamp]),
    Index('idx_sync_log_status', [status]),
  ];
}

/// Row-level hash cache for ultra-fast change detection
class SyncRowHash extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tableName => text()();
  TextColumn get recordUuid => text()();
  TextColumn get rowHashSha1 => text()(); // SHA-1 hash of entire row
  IntColumn get lastModified => integer()(); // For quick comparison
  IntColumn get version => integer()(); // Record version
  TextColumn get deviceId => text()(); // Last device that modified
  IntColumn get cachedAt => integer()(); // When this hash was computed
  
  @override
  List<Index> get indexes => [
    Index('idx_sync_row_hash_lookup', [tableName, recordUuid]),
    Index('idx_sync_row_hash_modified', [lastModified]),
    Index('idx_sync_row_hash_cached', [cachedAt]),
  ];
}

/// Tracks all conflicts and resolution strategies
class SyncConflictLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get conflictId => text().unique()();
  TextColumn get tableName => text()();
  TextColumn get recordUuid => text()();
  IntColumn get detectedAt => integer()();
  TextColumn get localDeviceId => text()();
  TextColumn get remoteDeviceId => text()();
  TextColumn get localData => text()(); // JSON
  TextColumn get remoteData => text()(); // JSON
  IntColumn get localTimestamp => integer()();
  IntColumn get remoteTimestamp => integer()();
  IntColumn get localVersion => integer()();
  IntColumn get remoteVersion => integer()();
  TextColumn get resolutionStrategy => text()(); // 'newer_wins', 'version_wins', 'manual'
  TextColumn get resolvedData => text().nullable()(); // JSON of final data
  IntColumn get resolvedAt => integer().nullable()();
  TextColumn get resolvedBy => text().nullable()(); // 'auto' or user ID
  TextColumn get status => text()(); // 'pending', 'resolved', 'ignored'
  
  @override
  List<Index> get indexes => [
    Index('idx_sync_conflict_table_uuid', [tableName, recordUuid]),
    Index('idx_sync_conflict_status', [status]),
    Index('idx_sync_conflict_detected', [detectedAt]),
  ];
}

/// ════════════════════════════════════════════════════════════════
/// MIGRATION GUIDE
/// ════════════════════════════════════════════════════════════════
/// 
/// Add these tables to your AppDatabase class in local_db.dart:
/// 
/// ```dart
/// @DriftDatabase(tables: [
///   Rooms,
///   Bookings,
///   BookingNotes,
///   ShiftNotes,
///   Employees,
///   Expenses,
///   CashTransactions,
///   Payments,
///   Debts,
///   Outbox,
///   SyncState,
///   // NEW TABLES
///   SyncLog,
///   SyncRowHash,
///   SyncConflictLog,
/// ])
/// class AppDatabase extends _$AppDatabase {
///   // ...
///   
///   @override
///   int get schemaVersion => 8; // Increment version
///   
///   @override
///   MigrationStrategy get migration => MigrationStrategy(
///     onUpgrade: (m, from, to) async {
///       // ... existing migrations
///       
///       if (from < 8) {
///         await m.createTable(syncLog);
///         await m.createTable(syncRowHash);
///         await m.createTable(syncConflictLog);
///       }
///     },
///   );
/// }
/// ```
/// 
/// ════════════════════════════════════════════════════════════════

/// ════════════════════════════════════════════════════════════════
/// EXAMPLE QUERIES
/// ════════════════════════════════════════════════════════════════

/*

// Query sync statistics
Future<List<SyncLogData>> getRecentSyncs() async {
  return (select(syncLog)
    ..orderBy([(t) => OrderingTerm.desc(t.startTimestamp)])
    ..limit(10)
  ).get();
}

// Get sync success rate
Future<double> getSyncSuccessRate() async {
  final total = await (selectOnly(syncLog)
    ..addColumns([syncLog.id.count()]))
    .getSingle();
    
  final successful = await (selectOnly(syncLog)
    ..where(syncLog.status.equals('completed'))
    ..addColumns([syncLog.id.count()]))
    .getSingle();
    
  final totalCount = total.read(syncLog.id.count()) ?? 0;
  final successCount = successful.read(syncLog.id.count()) ?? 0;
  
  return totalCount > 0 ? successCount / totalCount : 0.0;
}

// Get average sync duration
Future<int?> getAverageSyncDuration() async {
  final result = await (selectOnly(syncLog)
    ..where(syncLog.status.equals('completed'))
    ..addColumns([syncLog.durationMs.avg()]))
    .getSingle();
    
  return result.read(syncLog.durationMs.avg())?.toInt();
}

// Get total data transferred
Future<int> getTotalDataTransferred() async {
  final result = await (selectOnly(syncLog)
    ..addColumns([syncLog.compressedSizeBytes.sum()]))
    .getSingle();
    
  return result.read(syncLog.compressedSizeBytes.sum())?.toInt() ?? 0;
}

// Find cached hash for a record
Future<SyncRowHashData?> getCachedHash(String table, String uuid) async {
  return (select(syncRowHash)
    ..where((t) => t.tableName.equals(table) & t.recordUuid.equals(uuid)))
    .getSingleOrNull();
}

// Update cached hash
Future<void> updateCachedHash({
  required String table,
  required String uuid,
  required String hash,
  required int lastModified,
  required int version,
  required String deviceId,
}) async {
  await into(syncRowHash).insert(
    SyncRowHashCompanion.insert(
      tableName: table,
      recordUuid: uuid,
      rowHashSha1: hash,
      lastModified: lastModified,
      version: version,
      deviceId: deviceId,
      cachedAt: DateTime.now().millisecondsSinceEpoch,
    ),
    mode: InsertMode.insertOrReplace,
  );
}

// Get unresolved conflicts
Future<List<SyncConflictLogData>> getUnresolvedConflicts() async {
  return (select(syncConflictLog)
    ..where((t) => t.status.equals('pending'))
    ..orderBy([(t) => OrderingTerm.desc(t.detectedAt)]))
    .get();
}

// Resolve conflict
Future<void> resolveConflict(
  String conflictId,
  Map<String, dynamic> resolvedData,
  String resolvedBy,
) async {
  await (update(syncConflictLog)
    ..where((t) => t.conflictId.equals(conflictId)))
    .write(SyncConflictLogCompanion(
      resolvedData: Value(jsonEncode(resolvedData)),
      resolvedAt: Value(DateTime.now().millisecondsSinceEpoch),
      resolvedBy: Value(resolvedBy),
      status: const Value('resolved'),
    ));
}

// Clean old sync logs (keep last 30 days)
Future<void> cleanOldSyncLogs() async {
  final cutoff = DateTime.now().subtract(Duration(days: 30));
  
  await (delete(syncLog)
    ..where((t) => t.startTimestamp.isSmallerThanValue(cutoff.millisecondsSinceEpoch)))
    .go();
}

// Clean old cached hashes (keep last 7 days)
Future<void> cleanOldCachedHashes() async {
  final cutoff = DateTime.now().subtract(Duration(days: 7));
  
  await (delete(syncRowHash)
    ..where((t) => t.cachedAt.isSmallerThanValue(cutoff.millisecondsSinceEpoch)))
    .go();
}

*/
