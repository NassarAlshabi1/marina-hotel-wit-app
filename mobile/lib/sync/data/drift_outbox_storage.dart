/// Drift Outbox Storage Implementation
/// تطبيق OutboxStorage باستخدام Drift
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../services/local_db.dart';
import '../models/sync_models.dart';
import '../processors/outbox_processor.dart';

/// تطبيق OutboxStorage باستخدام Drift
class DriftOutboxStorage implements OutboxStorage {

  DriftOutboxStorage(this._db);
  final AppDatabase _db;

  /// تحويل OutboxData إلى DeltaChange
  DeltaChange _toDeltaChange(OutboxData record) {
    Map<String, dynamic> payloadMap = {};
    try {
      final decoded = jsonDecode(record.payload);
      if (decoded is Map<String, dynamic>) {
        payloadMap = decoded;
      }
    } catch (e) { debugPrint('WARN: Failed to parse outbox payload: $e'); }

    return DeltaChange(
      id: record.idempotencyKey ?? record.id.toString(),
      table: record.entity,
      uuid: record.localUuid,
      operation: SyncOperation.values.firstWhere(
        (e) => e.name == record.op,
        orElse: () => SyncOperation.update,
      ),
      payload: payloadMap,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        record.clientTs * 1000,
        isUtc: true,
      ),
      vectorClock: '',
      retryCount: record.attempts,
      lastError: record.lastError,
      nextRetryAt: record.processingStartedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(
              record.processingStartedAt! * 1000,
              isUtc: true,
            )
          : null,
    );
  }

  /// تحويل DeltaChange إلى OutboxCompanion
  /// ✅ فصل هندسي: جميع الإدخالات من هذا المسار تحمل source='local'
  OutboxCompanion _toCompanion(DeltaChange change) {
    return OutboxCompanion(
      entity: Value(change.table),
      op: Value(change.operation.name),
      localUuid: Value(change.uuid),
      payload: Value(jsonEncode(change.payload)),
      clientTs: Value(change.timestamp.millisecondsSinceEpoch ~/ 1000),
      attempts: Value(change.retryCount),
      lastError: Value(change.lastError),
      idempotencyKey: Value(change.id),
      processingStatus: const Value('pending'),
      processingStartedAt: Value(
        change.nextRetryAt?.millisecondsSinceEpoch != null
            ? change.nextRetryAt!.millisecondsSinceEpoch ~/ 1000
            : null,
      ),
      source: const Value('local'),
    );
  }

  @override
  Future<void> initialize() async {
    // Database is already initialized
  }

  @override
  Future<void> save(DeltaChange change) async {
    final companion = _toCompanion(change);
    final existing = await (_db.select(_db.outbox)
          ..where((t) => t.idempotencyKey.equals(change.id)))
        .getSingleOrNull();
    if (existing != null) {
      await (_db.update(_db.outbox)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    } else {
      await _db.into(_db.outbox).insert(companion);
    }
  }

  @override
  Future<DeltaChange?> getById(String id) async {
    final record = await (_db.select(_db.outbox)
          ..where((t) => t.idempotencyKey.equals(id)))
        .getSingleOrNull();
    return record != null ? _toDeltaChange(record) : null;
  }

  @override
  Future<List<DeltaChange>> fetchPending({
    required int limit,
    required DateTime before,
    bool onlyRetryable = false,
  }) async {
    final query = _db.select(_db.outbox)
      ..where((t) => t.processingStatus.equals('pending'));

    if (onlyRetryable) {
      final beforeEpoch = before.millisecondsSinceEpoch ~/ 1000;
      query.where(
        (t) => t.processingStartedAt.isSmallerOrEqualValue(beforeEpoch),
      );
    }

    query
      ..orderBy([(t) => OrderingTerm(expression: t.clientTs)])
      ..limit(limit);

    final records = await query.get();
    return records.map(_toDeltaChange).toList();
  }

  @override
  Future<void> markAsSynced(String id, DateTime timestamp) async {
    final existing = await (_db.select(_db.outbox)
          ..where((t) => t.idempotencyKey.equals(id)))
        .getSingleOrNull();
    if (existing == null) {
      return;
    }

    await (_db.update(_db.outbox)..where((t) => t.id.equals(existing.id)))
        .write(const OutboxCompanion(
      processingStatus: Value('synced'),
    ),);
  }

  @override
  Future<void> markAsFailed(String id, String error, DateTime timestamp) async {
    final existing = await (_db.select(_db.outbox)
          ..where((t) => t.idempotencyKey.equals(id)))
        .getSingleOrNull();
    if (existing == null) {
      return;
    }

    await (_db.update(_db.outbox)..where((t) => t.id.equals(existing.id)))
        .write(OutboxCompanion(
      processingStatus: const Value('failed'),
      lastError: Value(error),
    ),);
  }

  @override
  Future<void> scheduleRetry(
    String id, {
    required String error,
    required int retryCount,
    required DateTime nextRetryAt,
  }) async {
    final existing = await (_db.select(_db.outbox)
          ..where((t) => t.idempotencyKey.equals(id)))
        .getSingleOrNull();
    if (existing == null) {
      return;
    }

    await (_db.update(_db.outbox)..where((t) => t.id.equals(existing.id)))
        .write(OutboxCompanion(
      attempts: Value(retryCount),
      lastError: Value(error),
      processingStatus: const Value('pending'),
      processingStartedAt:
          Value(nextRetryAt.millisecondsSinceEpoch ~/ 1000),
    ),);
  }

  @override
  Future<void> delete(String id) async {
    final existing = await (_db.select(_db.outbox)
          ..where((t) => t.idempotencyKey.equals(id)))
        .getSingleOrNull();
    if (existing == null) {
      return;
    }

    await (_db.delete(_db.outbox)..where((t) => t.id.equals(existing.id)))
        .go();
  }

  @override
  Future<void> deleteByTable(String table) async {
    await (_db.delete(_db.outbox)..where((t) => t.entity.equals(table))).go();
  }

  @override
  Future<int> deleteSyncedBefore(DateTime cutoff) async {
    final epochCutoff = cutoff.millisecondsSinceEpoch ~/ 1000;
    final query = _db.delete(_db.outbox)
      ..where((t) => t.processingStatus.equals('synced'))
      ..where((t) => t.clientTs.isSmallerThanValue(epochCutoff));

    return query.go();
  }

  @override
  Future<int> pendingCount() async {
    final result = await (_db.select(_db.outbox)
          ..where((t) => t.processingStatus.equals('pending')))
        .get();
    return result.length;
  }

  @override
  Future<OutboxStats> getStats() async {
    final pending = await pendingCount();

    final syncingResult = await (_db.select(_db.outbox)
          ..where((t) => t.processingStatus.equals('retrying')))
        .get();
    final syncing = syncingResult.length;

    final syncedResult = await (_db.select(_db.outbox)
          ..where((t) => t.processingStatus.equals('synced')))
        .get();
    final synced = syncedResult.length;

    final failedResult = await (_db.select(_db.outbox)
          ..where((t) => t.processingStatus.equals('failed')))
        .get();
    final failed = failedResult.length;

    final oldestResult = await (_db.select(_db.outbox)
          ..where((t) => t.processingStatus.equals('pending'))
          ..orderBy([(t) => OrderingTerm(expression: t.clientTs)])
          ..limit(1))
        .getSingleOrNull();

    return OutboxStats(
      pendingCount: pending,
      syncingCount: syncing,
      syncedCount: synced,
      failedCount: failed,
      oldestPending: oldestResult != null
          ? DateTime.fromMillisecondsSinceEpoch(
              oldestResult.clientTs * 1000,
              isUtc: true,
            )
          : null,
    );
  }
}
