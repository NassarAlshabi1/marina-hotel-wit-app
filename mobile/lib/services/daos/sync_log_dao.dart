import 'dart:convert';
import 'package:drift/drift.dart';
import '../local_db.dart';

part 'sync_log_dao.g.dart';

/// نموذج مبسط لسجل المزامنة للعرض
class SyncLogEntry {
  final int id;
  final String syncId;
  final String direction; // pull, push, bidirectional
  final String deviceId;
  final String status; // success, failed, partial
  final DateTime createdAt;
  final DateTime? completedAt;
  final int? recordsCount;
  final String? errorMessage;
  final int? durationMs;
  final String? target; // Appwrite, GoogleDrive

  SyncLogEntry({
    required this.id,
    required this.syncId,
    required this.direction,
    required this.deviceId,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.recordsCount,
    this.errorMessage,
    this.durationMs,
    this.target,
  });
}

/// إحصائيات المزامنة
class SyncStats {
  final int totalSyncs;
  final int successfulSyncs;
  final int failedSyncs;
  final double successRate;
  final int totalRecordsPulled;
  final int totalRecordsPushed;
  final DateTime? lastSync;
  final int averageDurationMs;

  SyncStats({
    required this.totalSyncs,
    required this.successfulSyncs,
    required this.failedSyncs,
    required this.successRate,
    required this.totalRecordsPulled,
    required this.totalRecordsPushed,
    this.lastSync,
    required this.averageDurationMs,
  });
}

@DriftAccessor(tables: [SyncLog, SyncConflicts])
class SyncLogDao extends DatabaseAccessor<AppDatabase> with _$SyncLogDaoMixin {
  SyncLogDao(AppDatabase db) : super(db);

  /// تسجيل عملية مزامنة جديدة
  /// [operations] can be null if no operations list is available
  Future<int> logSync({
    required String syncId,
    required String direction,
    required String deviceId,
    required String target,
    required String status,
    int? recordsPulled,
    int? recordsPushed,
    String? errorMessage,
    int? durationMs,
    Map<String, dynamic>? metadata,
  }) async {
    final now = DateTime.now();
    
    final entry = SyncLogCompanion(
      syncId: Value(syncId),
      direction: Value(direction),
      deviceId: Value(deviceId),
      status: Value(status),
      createdAt: Value(now.toIso8601String()),
      completedAt: status != 'in_progress' ? Value(now.toIso8601String()) : const Value.absent(),
      metadata: Value(jsonEncode({
        'target': target,
        'recordsPulled': recordsPulled,
        'recordsPushed': recordsPushed,
        'durationMs': durationMs,
        'errorMessage': errorMessage,
        ...?metadata,
      })),
      operations: const Value.absent(),
    );

    return await into(syncLog).insert(entry);
  }

  /// الحصول على سجل المزامنة (مع pagination)
  Future<List<SyncLogEntry>> getSyncHistory({
    int limit = 50,
    int offset = 0,
    String? direction, // 'pull', 'push', null للكل
    String? status, // 'success', 'failed', null للكل
  }) async {
    var query = select(syncLog)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);

    if (direction != null) {
      query = query..where((t) => t.direction.equals(direction));
    }

    if (status != null) {
      query = query..where((t) => t.status.equals(status));
    }

    query = query..limit(limit, offset: offset);

    final results = await query.get();

    return results.map((row) {
      final metadata = jsonDecode(row.metadata) as Map<String, dynamic>;
      
      return SyncLogEntry(
        id: row.id,
        syncId: row.syncId,
        direction: row.direction,
        deviceId: row.deviceId,
        status: row.status,
        createdAt: DateTime.parse(row.createdAt),
        completedAt: row.completedAt != null ? DateTime.parse(row.completedAt!) : null,
        recordsCount: (metadata['recordsPulled'] as int?) ?? (metadata['recordsPushed'] as int?),
        errorMessage: metadata['errorMessage'] as String?,
        durationMs: metadata['durationMs'] as int?,
        target: metadata['target'] as String?,
      );
    }).toList();
  }

  /// الحصول على آخر عملية مزامنة
  Future<SyncLogEntry?> getLastSync() async {
    final query = select(syncLog)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(1);
    
    final result = await query.getSingleOrNull();
    if (result == null) return null;

    final metadata = jsonDecode(result.metadata) as Map<String, dynamic>;
    
    return SyncLogEntry(
      id: result.id,
      syncId: result.syncId,
      direction: result.direction,
      deviceId: result.deviceId,
      status: result.status,
      createdAt: DateTime.parse(result.createdAt),
      completedAt: result.completedAt != null ? DateTime.parse(result.completedAt!) : null,
      recordsCount: (metadata['recordsPulled'] as int?) ?? (metadata['recordsPushed'] as int?),
      errorMessage: metadata['errorMessage'] as String?,
      durationMs: metadata['durationMs'] as int?,
      target: metadata['target'] as String?,
    );
  }

  /// إحصائيات المزامنة (using SQL aggregates instead of Dart loop)
  Future<SyncStats> getSyncStats({DateTime? since}) async {
    var whereClause = '';
    final variables = <Variable<Object>>[];

    if (since != null) {
      whereClause = 'WHERE created_at >= ?';
      variables.add(Variable<String>(since.toIso8601String()));
    }

    final result = await customSelect(
      "SELECT "
      "  COUNT(*) AS total_syncs, "
      "  COALESCE(SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END), 0) AS successful_syncs, "
      "  COALESCE(SUM(CASE WHEN status != 'success' THEN 1 ELSE 0 END), 0) AS failed_syncs, "
      "  COALESCE(SUM(json_extract(metadata, '\$.recordsPulled')), 0) AS total_pulled, "
      "  COALESCE(SUM(json_extract(metadata, '\$.recordsPushed')), 0) AS total_pushed, "
      "  COALESCE(SUM(json_extract(metadata, '\$.durationMs')), 0) AS total_duration, "
      "  MAX(created_at) AS last_sync_at "
      "FROM sync_log $whereClause",
      variables: variables,
      readsFrom: {syncLog},
    ).getSingle();

    final totalSyncs = result.read<int>('total_syncs');

    if (totalSyncs == 0) {
      return SyncStats(
        totalSyncs: 0,
        successfulSyncs: 0,
        failedSyncs: 0,
        successRate: 0,
        totalRecordsPulled: 0,
        totalRecordsPushed: 0,
        averageDurationMs: 0,
      );
    }

    final successful = result.read<int>('successful_syncs');
    final lastSyncAt = result.read<String?>('last_sync_at');

    return SyncStats(
      totalSyncs: totalSyncs,
      successfulSyncs: successful,
      failedSyncs: result.read<int>('failed_syncs'),
      successRate: (successful / totalSyncs) * 100,
      totalRecordsPulled: result.read<int>('total_pulled'),
      totalRecordsPushed: result.read<int>('total_pushed'),
      lastSync: lastSyncAt != null ? DateTime.parse(lastSyncAt) : null,
      averageDurationMs: result.read<int>('total_duration') ~/ totalSyncs,
    );
  }

  /// حذف السجلات القديمة (للصيانة)
  Future<int> deleteOldLogs({required Duration olderThan}) async {
    final cutoff = DateTime.now().subtract(olderThan);
    
    final query = delete(syncLog)
      ..where((t) => t.createdAt.isSmallerThanValue(cutoff.toIso8601String()));
    
    return await query.go();
  }

  /// عدد السجلات
  Future<int> count() async {
    final countExpr = countAll();
    final query = selectOnly(syncLog)..addColumns([countExpr]);
    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }

  /// Stream للسجلات الجديدة (للـ UI المباشر)
  Stream<List<SyncLogEntry>> watchRecentLogs({int limit = 20}) {
    final query = select(syncLog)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);

    return query.watch().map((rows) => rows.map((row) {
      final metadata = jsonDecode(row.metadata) as Map<String, dynamic>;
      
      return SyncLogEntry(
        id: row.id,
        syncId: row.syncId,
        direction: row.direction,
        deviceId: row.deviceId,
        status: row.status,
        createdAt: DateTime.parse(row.createdAt),
        completedAt: row.completedAt != null ? DateTime.parse(row.completedAt!) : null,
        recordsCount: (metadata['recordsPulled'] as int?) ?? (metadata['recordsPushed'] as int?),
        errorMessage: metadata['errorMessage'] as String?,
        durationMs: metadata['durationMs'] as int?,
        target: metadata['target'] as String?,
      );
    }).toList());
  }
}
