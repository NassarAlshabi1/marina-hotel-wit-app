/// Drift Outbox Storage Implementation
/// تطبيق OutboxStorage باستخدام Drift

import 'package:drift/drift.dart';
import '../processors/outbox_processor.dart';
import '../models/sync_models.dart';

/// جدول Outbox في Drift
@DataClassName('OutboxRecord')
class OutboxTable extends Table {
  TextColumn get id => text()();
  TextColumn get sourceTable => text()();
  TextColumn get uuid => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text()(); // JSON
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get vectorClock => text()();
  TextColumn get checksum => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isFailed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String? get tableName => 'outbox_queue';
}

/// تطبيق OutboxStorage باستخدام Drift
class DriftOutboxStorage implements OutboxStorage {
  final GeneratedDatabase _db;

  DriftOutboxStorage(this._db);

  /// الوصول إلى جدول Outbox
  OutboxTable get _table => OutboxTable();

  /// تحويل OutboxRecord إلى DeltaChange
  DeltaChange _toDeltaChange(OutboxRecord record) {
    return DeltaChange(
      id: record.id,
      table: record.sourceTable,
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

  /// تحويل DeltaChange إلى OutboxTable Companion
  OutboxTableCompanion _toCompanion(DeltaChange change) {
    return OutboxTableCompanion.insert(
      id: change.id,
      sourceTable: change.table,
      uuid: change.uuid,
      operation: change.operation.name,
      payload: _encodePayload(change.payload),
      timestamp: change.timestamp,
      vectorClock: change.vectorClock,
      checksum: Value(change.checksum),
      deviceId: Value(change.deviceId),
      retryCount: Value(change.retryCount),
      lastError: Value(change.lastError),
      nextRetryAt: Value(change.nextRetryAt),
    );
  }

  Map<String, dynamic> _parsePayload(String json) {
    // استخدام jsonDecode
    return {};
  }

  String _encodePayload(Map<String, dynamic> payload) {
    // استخدام jsonEncode
    return '{}';
  }

  @override
  Future<void> initialize() async {
    // يمكن إضافة تهيئة هنا إذا لزم الأمر
  }

  @override
  Future<void> save(DeltaChange change) async {
    await _db.into(_table).insertOnConflictUpdate(_toCompanion(change));
  }

  @override
  Future<DeltaChange?> getById(String id) async {
    final query = _db.select(_table)..where((t) => t.id.equals(id));
    final record = await query.getSingleOrNull();
    return record != null ? _toDeltaChange(record) : null;
  }

  @override
  Future<List<DeltaChange>> fetchPending({
    required int limit,
    required DateTime before,
    bool onlyRetryable = false,
  }) async {
    final query = _db.select(_table)
      ..where((t) => t.isSynced.equals(false))
      ..where((t) => t.isFailed.equals(false));

    if (onlyRetryable) {
      query.where((t) => t.nextRetryAt.isSmallerOrEqualValue(before));
    } else {
      query.where((t) =>
          t.nextRetryAt.isNull() | t.nextRetryAt.isSmallerOrEqualValue(before));
    }

    query
      ..orderBy([(t) => OrderingTerm(expression: t.timestamp)])
      ..limit(limit);

    final records = await query.get();
    return records.map(_toDeltaChange).toList();
  }

  @override
  Future<void> markAsSynced(String id, DateTime timestamp) async {
    final query = _db.update(_table)..where((t) => t.id.equals(id));

    await query.write(OutboxTableCompanion(
      isSynced: const Value(true),
      syncedAt: Value(timestamp),
    ));
  }

  @override
  Future<void> markAsFailed(String id, String error, DateTime timestamp) async {
    final query = _db.update(_table)..where((t) => t.id.equals(id));

    await query.write(OutboxTableCompanion(
      isFailed: const Value(true),
      lastError: Value(error),
      syncedAt: Value(timestamp),
    ));
  }

  @override
  Future<void> scheduleRetry(
    String id, {
    required String error,
    required int retryCount,
    required DateTime nextRetryAt,
  }) async {
    final query = _db.update(_table)..where((t) => t.id.equals(id));

    await query.write(OutboxTableCompanion(
      retryCount: Value(retryCount),
      lastError: Value(error),
      nextRetryAt: Value(nextRetryAt),
    ));
  }

  @override
  Future<void> delete(String id) async {
    final query = _db.delete(_table)..where((t) => t.id.equals(id));
    await query.go();
  }

  @override
  Future<void> deleteByTable(String table) async {
    // ignore: invalid_use_of_visible_for_overriding_member
    final query = _db.delete(_table)..where((t) => t.sourceTable.equals(table));
    await query.go();
  }

  @override
  Future<int> deleteSyncedBefore(DateTime cutoff) async {
    final query = _db.delete(_table)
      ..where((t) => t.isSynced.equals(true))
      ..where((t) => t.syncedAt.isSmallerThanValue(cutoff));

    return await query.go();
  }

  @override
  Future<int> pendingCount() async {
    final query = _db.select(_table)
      ..where((t) => t.isSynced.equals(false))
      ..where((t) => t.isFailed.equals(false))
      ..where((t) =>
          t.nextRetryAt.isNull() | t.nextRetryAt.isSmallerOrEqualValue(DateTime.now()));

    final count = await query.get();
    return count.length;
  }

  @override
  Future<OutboxStats> getStats() async {
    final pending = await pendingCount();

    final syncingQuery = _db.select(_table)
      ..where((t) => t.isSynced.equals(false))
      ..where((t) => t.isFailed.equals(false))
      ..where((t) => t.nextRetryAt.isBiggerThanValue(DateTime.now()));

    final syncing = (await syncingQuery.get()).length;

    final syncedQuery = _db.select(_table)..where((t) => t.isSynced.equals(true));
    final synced = (await syncedQuery.get()).length;

    final failedQuery = _db.select(_table)..where((t) => t.isFailed.equals(true));
    final failed = (await failedQuery.get()).length;

    final oldestQuery = _db.select(_table)
      ..where((t) => t.isSynced.equals(false))
      ..orderBy([(t) => OrderingTerm(expression: t.timestamp)])
      ..limit(1);

    final oldest = await oldestQuery.getSingleOrNull();

    return OutboxStats(
      pendingCount: pending,
      syncingCount: syncing,
      syncedCount: synced,
      failedCount: failed,
      oldestPending: oldest?.timestamp,
    );
  }
}
