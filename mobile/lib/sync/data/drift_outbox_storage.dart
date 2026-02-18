/// Drift Outbox Storage Implementation
/// تطبيق OutboxStorage باستخدام Drift (raw SQL)

import 'dart:convert';
import 'package:drift/drift.dart';
import '../processors/outbox_processor.dart';
import '../models/sync_models.dart';

class OutboxRecord {
  final String id;
  final String tableName;
  final String uuid;
  final String operation;
  final String payload;
  final DateTime timestamp;
  final String vectorClock;
  final String? checksum;
  final String? deviceId;
  final int retryCount;
  final String? lastError;
  final DateTime? nextRetryAt;
  final DateTime? syncedAt;
  final bool isSynced;
  final bool isFailed;

  OutboxRecord({
    required this.id,
    required this.tableName,
    required this.uuid,
    required this.operation,
    required this.payload,
    required this.timestamp,
    required this.vectorClock,
    this.checksum,
    this.deviceId,
    this.retryCount = 0,
    this.lastError,
    this.nextRetryAt,
    this.syncedAt,
    this.isSynced = false,
    this.isFailed = false,
  });

  factory OutboxRecord.fromRow(QueryRow row) {
    return OutboxRecord(
      id: row.read<String>('id'),
      tableName: row.read<String>('table_name'),
      uuid: row.read<String>('uuid'),
      operation: row.read<String>('operation'),
      payload: row.read<String>('payload'),
      timestamp: DateTime.fromMillisecondsSinceEpoch(row.read<int>('timestamp')),
      vectorClock: row.read<String>('vector_clock'),
      checksum: row.readNullable<String>('checksum'),
      deviceId: row.readNullable<String>('device_id'),
      retryCount: row.read<int>('retry_count'),
      lastError: row.readNullable<String>('last_error'),
      nextRetryAt: row.readNullable<int>('next_retry_at') != null
          ? DateTime.fromMillisecondsSinceEpoch(row.read<int>('next_retry_at'))
          : null,
      syncedAt: row.readNullable<int>('synced_at') != null
          ? DateTime.fromMillisecondsSinceEpoch(row.read<int>('synced_at'))
          : null,
      isSynced: row.read<int>('is_synced') == 1,
      isFailed: row.read<int>('is_failed') == 1,
    );
  }
}

class DriftOutboxStorage implements OutboxStorage {
  final GeneratedDatabase _db;
  static const String _table = 'outbox_queue';

  DriftOutboxStorage(this._db);

  Future<void> _ensureTable() async {
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        uuid TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        vector_clock TEXT NOT NULL,
        checksum TEXT,
        device_id TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        next_retry_at INTEGER,
        synced_at INTEGER,
        is_synced INTEGER NOT NULL DEFAULT 0,
        is_failed INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  DeltaChange _toDeltaChange(OutboxRecord record) {
    return DeltaChange(
      id: record.id,
      table: record.tableName,
      uuid: record.uuid,
      operation: SyncOperation.values.firstWhere(
        (e) => e.name == record.operation,
        orElse: () => SyncOperation.update,
      ),
      payload: _parsePayload(record.payload),
      timestamp: record.timestamp,
      vectorClock: record.vectorClock,
      checksum: record.checksum,
      deviceId: record.deviceId,
      retryCount: record.retryCount,
      lastError: record.lastError,
      nextRetryAt: record.nextRetryAt,
    );
  }

  Map<String, dynamic> _parsePayload(String json) {
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  String _encodePayload(Map<String, dynamic> payload) {
    return jsonEncode(payload);
  }

  @override
  Future<void> initialize() async {
    await _ensureTable();
  }

  @override
  Future<void> save(DeltaChange change) async {
    await _db.customStatement(
      '''INSERT OR REPLACE INTO $_table
         (id, table_name, uuid, operation, payload, timestamp, vector_clock,
          checksum, device_id, retry_count, last_error, next_retry_at, synced_at, is_synced, is_failed)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        change.id,
        change.table,
        change.uuid,
        change.operation.name,
        _encodePayload(change.payload),
        change.timestamp.millisecondsSinceEpoch,
        change.vectorClock,
        change.checksum,
        change.deviceId,
        change.retryCount,
        change.lastError,
        change.nextRetryAt?.millisecondsSinceEpoch,
        null,
        0,
        0,
      ],
    );
  }

  @override
  Future<DeltaChange?> getById(String id) async {
    final rows = await _db.customSelect(
      'SELECT * FROM $_table WHERE id = ?',
      variables: [Variable.withString(id)],
    ).get();
    if (rows.isEmpty) return null;
    return _toDeltaChange(OutboxRecord.fromRow(rows.first));
  }

  @override
  Future<List<DeltaChange>> fetchPending({
    required int limit,
    required DateTime before,
    bool onlyRetryable = false,
  }) async {
    final beforeMs = before.millisecondsSinceEpoch;
    String sql;
    if (onlyRetryable) {
      sql = '''SELECT * FROM $_table
               WHERE is_synced = 0 AND is_failed = 0
               AND next_retry_at IS NOT NULL AND next_retry_at <= ?
               ORDER BY timestamp ASC LIMIT ?''';
    } else {
      sql = '''SELECT * FROM $_table
               WHERE is_synced = 0 AND is_failed = 0
               AND (next_retry_at IS NULL OR next_retry_at <= ?)
               ORDER BY timestamp ASC LIMIT ?''';
    }
    final rows = await _db.customSelect(
      sql,
      variables: [Variable.withInt(beforeMs), Variable.withInt(limit)],
    ).get();
    return rows.map((r) => _toDeltaChange(OutboxRecord.fromRow(r))).toList();
  }

  @override
  Future<void> markAsSynced(String id, DateTime timestamp) async {
    await _db.customStatement(
      'UPDATE $_table SET is_synced = 1, synced_at = ? WHERE id = ?',
      [timestamp.millisecondsSinceEpoch, id],
    );
  }

  @override
  Future<void> markAsFailed(String id, String error, DateTime timestamp) async {
    await _db.customStatement(
      'UPDATE $_table SET is_failed = 1, last_error = ?, synced_at = ? WHERE id = ?',
      [error, timestamp.millisecondsSinceEpoch, id],
    );
  }

  @override
  Future<void> scheduleRetry(
    String id, {
    required String error,
    required int retryCount,
    required DateTime nextRetryAt,
  }) async {
    await _db.customStatement(
      'UPDATE $_table SET retry_count = ?, last_error = ?, next_retry_at = ? WHERE id = ?',
      [retryCount, error, nextRetryAt.millisecondsSinceEpoch, id],
    );
  }

  @override
  Future<void> delete(String id) async {
    await _db.customStatement('DELETE FROM $_table WHERE id = ?', [id]);
  }

  @override
  Future<void> deleteByTable(String table) async {
    await _db.customStatement(
      'DELETE FROM $_table WHERE table_name = ?',
      [table],
    );
  }

  @override
  Future<int> deleteSyncedBefore(DateTime cutoff) async {
    return await _db.customUpdate(
      'DELETE FROM $_table WHERE is_synced = 1 AND synced_at < ?',
      variables: [Variable.withInt(cutoff.millisecondsSinceEpoch)],
    );
  }

  @override
  Future<int> pendingCount() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rows = await _db.customSelect(
      '''SELECT COUNT(*) as cnt FROM $_table
         WHERE is_synced = 0 AND is_failed = 0
         AND (next_retry_at IS NULL OR next_retry_at <= ?)''',
      variables: [Variable.withInt(nowMs)],
    ).get();
    return rows.first.read<int>('cnt');
  }

  @override
  Future<OutboxStats> getStats() async {
    final pending = await pendingCount();

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final syncingRows = await _db.customSelect(
      '''SELECT COUNT(*) as cnt FROM $_table
         WHERE is_synced = 0 AND is_failed = 0
         AND next_retry_at IS NOT NULL AND next_retry_at > ?''',
      variables: [Variable.withInt(nowMs)],
    ).get();
    final syncing = syncingRows.first.read<int>('cnt');

    final syncedRows = await _db.customSelect(
      'SELECT COUNT(*) as cnt FROM $_table WHERE is_synced = 1',
    ).get();
    final synced = syncedRows.first.read<int>('cnt');

    final failedRows = await _db.customSelect(
      'SELECT COUNT(*) as cnt FROM $_table WHERE is_failed = 1',
    ).get();
    final failed = failedRows.first.read<int>('cnt');

    final oldestRows = await _db.customSelect(
      '''SELECT timestamp FROM $_table
         WHERE is_synced = 0
         ORDER BY timestamp ASC LIMIT 1''',
    ).get();
    final oldest = oldestRows.isNotEmpty
        ? DateTime.fromMillisecondsSinceEpoch(oldestRows.first.read<int>('timestamp'))
        : null;

    return OutboxStats(
      pendingCount: pending,
      syncingCount: syncing,
      syncedCount: synced,
      failedCount: failed,
      oldestPending: oldest,
    );
  }
}
