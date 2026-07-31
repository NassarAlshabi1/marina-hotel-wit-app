// ═══════════════════════════════════════════════════════════════
//  sync_repository.dart — Sync Repository
//  Coordinates between Drift SQLite (local) and Cloudflare Worker (remote)
//  Works with sync_queue, sync_log, and sync_conflicts tables
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';

// ═══════════════════════════════════════════════════════════════
//  Drift Table Definitions
// ═══════════════════════════════════════════════════════════════

/// Outbox queue — pending operations to push to server
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get localUuid => text().unique()();
  TextColumn get entity => text()();
  TextColumn get operation => text()(); // 'create', 'update', 'delete'
  TextColumn get payload => text()(); // JSON
  TextColumn get idempotencyKey => text()();
  IntColumn get clientTs => integer()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  // 'pending', 'pushing', 'delivered', 'failed'
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
}

/// Sync log — record of every sync operation
class SyncLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  TextColumn get direction => text()(); // 'push' or 'pull'
  IntColumn get timestamp => integer()();
  TextColumn get payload => text().nullable()(); // JSON snapshot
}

/// Sync conflicts — records of LWW conflicts
class SyncConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get localPayload => text()();
  TextColumn get remotePayload => text()();
  TextColumn get resolution => text().withDefault(const Constant('last_write_wins'))();
  IntColumn get createdAt => integer()();
}

/// Sync state — tracks cursor for delta sync
class SyncState extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get lastPullCursor => integer().withDefault(const Constant(0))();
  IntColumn get lastPullTs => integer().withDefault(const Constant(0))();
  IntColumn get lastPushTs => integer().withDefault(const Constant(0))();
}

// ═══════════════════════════════════════════════════════════════
//  Drift Database
// ═══════════════════════════════════════════════════════════════

@DriftDatabase(tables: [SyncQueue, SyncLog, SyncConflicts, SyncState])
class SyncDatabase extends _$SyncDatabase {
  SyncDatabase() : super(_openConnection());

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'sync_queue.db'));
      return NativeDatabase(file);
    });
  }

  @override
  int get schemaVersion => 1;
}

// ═══════════════════════════════════════════════════════════════
//  Sync Repository
// ═══════════════════════════════════════════════════════════════

/// Entity table name mapping (must match server-side ENTITY_TABLES)
const _entityTables = {
  'rooms': 'rooms',
  'bookings': 'bookings',
  'payments': 'payments',
  'expenses': 'expenses',
  'employees': 'employees',
};

class SyncRepository {
  SyncRepository({
    required this.apiClient,
    SyncDatabase? db,
  }) : _db = db ?? SyncDatabase();

  final ApiClient apiClient;
  final SyncDatabase _db;
  final _uuid = const Uuid();

  // ─── Queue an operation for push ─────────────────────────

  /// Queue a create operation
  Future<void> queueCreate({
    required String entity,
    required String localUuid,
    required Map<String, dynamic> data,
    required String vectorClock,
    int? updatedAt,
  }) async {
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.syncQueue).insert(SyncQueueCompanion.insert(
          localUuid: localUuid,
          entity: entity,
          operation: 'create',
          payload: jsonEncode(data),
          idempotencyKey: '$entity:create:$localUuid:$now',
          clientTs: now,
          updatedAt: Value(now),
        ));
  }

  /// Queue an update operation
  Future<void> queueUpdate({
    required String entity,
    required String localUuid,
    required Map<String, dynamic> data,
    required String vectorClock,
    int? updatedAt,
  }) async {
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.syncQueue).insert(SyncQueueCompanion.insert(
          localUuid: localUuid,
          entity: entity,
          operation: 'update',
          payload: jsonEncode(data),
          idempotencyKey: '$entity:update:$localUuid:$now',
          clientTs: now,
          updatedAt: Value(now),
        ));
  }

  /// Queue a delete operation
  Future<void> queueDelete({
    required String entity,
    required String localUuid,
    int? updatedAt,
  }) async {
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.syncQueue).insert(SyncQueueCompanion.insert(
          localUuid: localUuid,
          entity: entity,
          operation: 'delete',
          payload: jsonEncode({'id': localUuid}),
          idempotencyKey: '$entity:delete:$localUuid:$now',
          clientTs: now,
          updatedAt: Value(now),
        ));
  }

  // ─── Push changes to server ──────────────────────────────

  /// Push all pending operations from the outbox to the server
  Future<PushResult?> pushChanges({int batchSize = 50}) async {
    // ─── Get pending operations ──────────────────────────────
    final pending = await (_db.select(_db.syncQueue)
          ..where((t) => t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.clientTs)])
          ..limit(batchSize))
        .get();

    if (pending.isEmpty) {
      return null;
    }

    // ─── Mark as 'pushing' ───────────────────────────────────
    for (final item in pending) {
      await (_db.update(_db.syncQueue)..where((t) => t.id.equals(item.id))).write(
        SyncQueueCompanion(
          status: const Value('pushing'),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        ),
      );
    }

    // ─── Build operations ────────────────────────────────────
    final operations = pending.map((item) {
      final data = jsonDecode(item.payload) as Map<String, dynamic>;
      return PushOperation(
        idempotencyKey: item.idempotencyKey,
        entity: item.entity,
        operation: item.operation,
        data: data,
        vectorClock: (data['vector_clock'] as String?) ?? '{}',
        updatedAt: item.clientTs,
        deviceId: apiClient.deviceId,
      );
    }).toList();

    // ─── Send to server ──────────────────────────────────────
    final response = await apiClient.pushChanges(operations: operations);

    if (!response.success) {
      // ─── Mark all as failed ─────────────────────────────────
      for (final item in pending) {
        await (_db.update(_db.syncQueue)..where((t) => t.id.equals(item.id))).write(
          SyncQueueCompanion(
            status: const Value('failed'),
            attempts: Value(item.attempts + 1),
            lastError: Value(response.error),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          ),
        );
      }
      return null;
    }

    final result = response.data!;

    // ─── Process results ─────────────────────────────────────
    for (final item in pending) {
      final resultItem = result.results.firstWhere(
        (r) => r.idempotencyKey == item.idempotencyKey,
        orElse: () => PushResultItem(
          idempotencyKey: item.idempotencyKey,
          success: false,
          error: 'No response from server',
        ),
      );

      if (resultItem.success) {
        // ─── Mark as delivered ─────────────────────────────────
        await (_db.update(_db.syncQueue)..where((t) => t.id.equals(item.id))).write(
          SyncQueueCompanion(
            status: const Value('delivered'),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          ),
        );

        // ─── Log to sync_log ───────────────────────────────────
        await _db.into(_db.syncLog).insert(SyncLogCompanion.insert(
              entity: item.entity,
              entityId: resultItem.entityId ?? item.localUuid,
              operation: item.operation,
              direction: 'push',
              timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              payload: Value(item.payload),
            ));
      } else {
        // ─── Mark as failed ────────────────────────────────────
        await (_db.update(_db.syncQueue)..where((t) => t.id.equals(item.id))).write(
          SyncQueueCompanion(
            status: const Value('failed'),
            attempts: Value(item.attempts + 1),
            lastError: Value(resultItem.error),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          ),
        );
      }
    }

    // ─── Update sync state ───────────────────────────────────
    final state = await (_db.select(_db.syncState)..where((t) => t.id.equals(1))).getSingleOrNull();
    if (state != null) {
      await (_db.update(_db.syncState)..where((t) => t.id.equals(1))).write(
        SyncStateCompanion(
          lastPushTs: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        ),
      );
    } else {
      await _db.into(_db.syncState).insert(SyncStateCompanion.insert(
            lastPushTs: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          ));
    }

    // ─── Clean up delivered items ────────────────────────────
    await (_db.delete(_db.syncQueue)..where((t) => t.status.equals('delivered'))).go();

    return result;
  }

  // ─── Pull changes from server ────────────────────────────

  /// Pull delta changes from server and apply to local DB
  Future<PullResult?> pullChanges({
    Function(String entity, Map<String, dynamic> data)? onApplyChange,
  }) async {
    // ─── Get current cursor ──────────────────────────────────
    final state = await (_db.select(_db.syncState)..where((t) => t.id.equals(1))).getSingleOrNull();
    final cursor = state?.lastPullCursor ?? 0;

    // ─── Pull from server ────────────────────────────────────
    final response = await apiClient.pullChanges(cursor: cursor);

    if (!response.success) {
      return null;
    }

    final result = response.data!;

    // ─── Apply changes to local DB ───────────────────────────
    for (final change in result.changes) {
      final entity = _findEntityForRecord(change);
      if (entity != null && onApplyChange != null) {
        await onApplyChange(entity, change);
      }

      // ─── Log to sync_log ───────────────────────────────────
      await _db.into(_db.syncLog).insert(SyncLogCompanion.insert(
            entity: entity ?? 'unknown',
            entityId: change['id']?.toString() ?? '',
            operation: change['deleted_at'] != null ? 'delete' : 'update',
            direction: 'pull',
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            payload: Value(jsonEncode(change)),
          ));
    }

    // ─── Update cursor ───────────────────────────────────────
    if (state != null) {
      await (_db.update(_db.syncState)..where((t) => t.id.equals(1))).write(
        SyncStateCompanion(
          lastPullCursor: Value(result.cursor),
          lastPullTs: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        ),
      );
    } else {
      await _db.into(_db.syncState).insert(SyncStateCompanion.insert(
            lastPullCursor: Value(result.cursor),
            lastPullTs: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          ));
    }

    return result;
  }

  // ─── Full sync (push then pull) ──────────────────────────

  /// Run a full sync cycle: push pending → pull remote
  Future<void> fullSync({
    Function(String entity, Map<String, dynamic> data)? onApplyChange,
  }) async {
    // Push first
    await pushChanges();

    // Then pull
    await pullChanges(onApplyChange: onApplyChange);
  }

  // ─── File operations ─────────────────────────────────────

  /// Upload a file to R2
  Future<ApiResponse<FileMetadata>> uploadFile(File file) {
    return apiClient.uploadFile(file: file);
  }

  /// Download a file from R2
  Future<ApiResponse<List<int>>> downloadFile(String fileId) {
    return apiClient.downloadFile(fileId);
  }

  /// Delete a file from R2
  Future<ApiResponse<bool>> deleteFile(String fileId) {
    return apiClient.deleteFile(fileId);
  }

  // ─── Conflict management ─────────────────────────────────

  /// Get conflicts from local DB
  Future<List<SyncConflict>> getLocalConflicts() async {
    return (_db.select(_db.syncConflicts)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Get conflicts from server
  Future<ApiResponse<List<Map<String, dynamic>>>> getRemoteConflicts({
    int limit = 50,
  }) {
    return apiClient.getConflicts(limit: limit);
  }

  // ─── Queue management ────────────────────────────────────

  /// Get pending queue count
  Future<int> getPendingCount() async {
    final count = (_db.selectOnly(_db.syncQueue)
          ..addColumns([_db.syncQueue.id.count()])
          ..where(_db.syncQueue.status.equals('pending')))
        .map((row) => row.read(_db.syncQueue.id.count()) ?? 0)
        .getSingle();
    return count;
  }

  /// Get failed queue count
  Future<int> getFailedCount() async {
    final count = (_db.selectOnly(_db.syncQueue)
          ..addColumns([_db.syncQueue.id.count()])
          ..where(_db.syncQueue.status.equals('failed')))
        .map((row) => row.read(_db.syncQueue.id.count()) ?? 0)
        .getSingle();
    return count;
  }

  /// Retry failed operations
  Future<void> retryFailed() async {
    await (_db.update(_db.syncQueue)..where((t) => t.status.equals('failed'))).write(
      SyncQueueCompanion(
        status: const Value('pending'),
        lastError: const Value(null),
      ),
    );
  }

  /// Clear all delivered and old failed operations
  Future<void> cleanupQueue({int olderThanDays = 30}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .millisecondsSinceEpoch ~/ 1000;

    await (_db.delete(_db.syncQueue)
          ..where((t) =>
              t.status.equals('delivered') |
              (t.status.equals('failed') & t.clientTs.isSmallerThanValue(cutoff))))
        .go();
  }

  // ─── Helpers ─────────────────────────────────────────────

  /// Find entity name by looking at the record structure
  String? _findEntityForRecord(Map<String, dynamic> record) {
    // Check if the record has an 'entity' field (added by pull endpoint)
    if (record.containsKey('_entity')) {
      return record['_entity'] as String?;
    }

    // Heuristic: check for entity-specific fields
    if (record.containsKey('room_number') && record.containsKey('price')) {
      return 'rooms';
    }
    if (record.containsKey('guest_name') && record.containsKey('checkin_date')) {
      return 'bookings';
    }
    if (record.containsKey('amount') && record.containsKey('payment_method')) {
      return 'payments';
    }
    if (record.containsKey('expense_type') && record.containsKey('description')) {
      return 'expenses';
    }
    if (record.containsKey('basic_salary') && record.containsKey('position')) {
      return 'employees';
    }

    return null;
  }

  /// Close the database
  Future<void> close() async {
    await _db.close();
  }
}
