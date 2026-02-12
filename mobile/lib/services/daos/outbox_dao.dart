import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../local_db.dart';
import '../unified_sync_orchestrator.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';

part 'outbox_dao.g.dart';

const _uuid = Uuid();

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db) : adapters = AdapterRegistry(db);

  final AdapterRegistry adapters;

  Stream<int> watchCount() => Stream.value(0);

  Future<int> count() async => 0;

  Future<void> resetErrors() async {}

  Future<int> clearStale({int attemptsThreshold = 3}) async => 0;

  Future<int> merge({
    required String entity,
    required String op,
    required String localUuid,
    int? serverId,
    required Map<String, dynamic> payload,
    required int clientTs,
  }) async {
    return 0;
  }

  Future<List<OutboxData>> takeBatch(int limit, {String? workerId}) async => [];

  Future<void> removeById(int id) async {}

  Future<void> removeByIds(List<int> ids) async {}

  Future<void> setError(int id, String message, int attempts) async {}

  Future<void> markCompleted(List<int> ids) async {}

  Future<void> markFailed(List<int> ids) async {}

  Future<void> retryFailed() async {}

  Future<int> cleanupStuckEntries({
    Duration timeout = const Duration(minutes: 5),
  }) async => 0;

  Future<int> cleanupCompleted({
    Duration olderThan = const Duration(days: 7),
  }) async => 0;
}
