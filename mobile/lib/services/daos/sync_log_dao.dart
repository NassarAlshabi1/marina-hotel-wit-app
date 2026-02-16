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

    final results = await query
      ..limit(limit, offset: offset);

    return results.map((row) {
      final metadata = jsonDecode(row.metadata ?? '{}') as Map<String, dynamic>;
      
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

    final metadata = jsonDecode(result.metadata ?? '{}') as Map<String, dynamic>;
    
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

  /// إحصائيات المزامنة
  Future<SyncStats> getSyncStats({DateTime? since}) async {
    var query = select(syncLog);
    
    if (since != null) {
      query = query..where((t) => t.createdAt.isBiggerOrEqualValue(since.toIso8601String()));
    }

    final results = await query.get();
    
    if (results.isEmpty) {
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

    int successful = 0;
    int failed = 0;
    int totalPulled = 0;
    int totalPushed = 0;
    int totalDuration = 0;
    DateTime? lastSync;

    for (final row in results) {
      final metadata = jsonDecode(row.metadata ?? '{}') as Map<String, dynamic>;
      
      if (row.status == 'success') {
        successful++;
      } else {
        failed++;
      }

      totalPulled += (metadata['recordsPulled'] as int?) ?? 0;
      totalPushed += (metadata['recordsPushed'] as int?) ?? 0;
      totalDuration += (metadata['durationMs'] as int?) ?? 0;

      final createdAt = DateTime.parse(row.createdAt);
      if (lastSync == null || createdAt.isAfter(lastSync)) {
        lastSync = createdAt;
      }
    }

    return SyncStats(
      totalSyncs: results.length,
      successfulSyncs: successful,
      failedSyncs: failed,
      successRate: (successful / results.length) * 100,
      totalRecordsPulled: totalPulled,
      totalRecordsPushed: totalPushed,
      lastSync: lastSync,
      averageDurationMs: totalDuration ~/ results.length,
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
      final metadata = jsonDecode(row.metadata ?? '{}') as Map<String, dynamic>;
      
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
