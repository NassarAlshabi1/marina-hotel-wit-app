import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../utils/time.dart';
import 'local_db.dart';

class DeltaSyncChange {
  DeltaSyncChange({
    required this.entity,
    required this.operation,
    required this.data,
    required this.rowHash,
    required this.localUuid,
    required this.clientTimestamp,
  });

  final String entity;
  final String operation;
  final Map<String, dynamic> data;
  final String rowHash;
  final String localUuid;
  final int clientTimestamp;

  Map<String, dynamic> toMap() {
    return {
      'entity': entity,
      'op': operation,
      'data': data,
      'row_hash': rowHash,
      'local_uuid': localUuid,
      'client_ts': clientTimestamp,
    };
  }
}

class DeltaSyncComputation {
  DeltaSyncComputation({
    required this.changes,
    required this.mirrorSnapshot,
    required this.fallbackTables,
  });

  final List<DeltaSyncChange> changes;
  final Map<String, Map<String, _MirrorRow>> mirrorSnapshot;
  final Set<String> fallbackTables;

  List<Map<String, dynamic>> toPayload() {
    return changes.map((c) => c.toMap()).toList();
  }
}

class DeltaSyncService {
  DeltaSyncService(this.db);

  final AppDatabase db;
  bool _mirrorTableReady = false;

  Future<DeltaSyncComputation> compute({int? since}) async {
    final state = await (db.select(db.syncState)..where((t) => t.id.equals(1))).getSingleOrNull();
    final baseSince = since ?? state?.lastPushTs ?? 0;
    final normalizedSince = _normalizeTimestamp(baseSince);
    final previousMirror = await _loadMirror();
    final configs = _entityConfigs();
    final nowTs = _normalizeTimestamp(Time.nowEpoch());
    final changes = <DeltaSyncChange>[];
    final snapshot = <String, Map<String, _MirrorRow>>{};
    final fallbackTables = <String>{};

    for (final config in configs) {
      final rows = await config.fetchAll();
      final existingMirror = previousMirror[config.entity] ?? {};
      final hasMirror = previousMirror.containsKey(config.entity);
      if (!hasMirror) {
        fallbackTables.add(config.entity);
        debugPrint('⚠️ تعذر إعادة بناء مرآة جدول ${config.entity}، سيتم الاعتماد على createdAt فقط');
      }
      final tableSnapshot = <String, _MirrorRow>{};
      final seen = <String>{};

      for (final row in rows) {
        final localUuid = config.localUuid(row);
        if (localUuid.isEmpty) {
          continue;
        }
        final sanitized = _preparePayload(config.toJson(row));
        sanitized['local_uuid'] = localUuid;
        final rowHash = _hashPayload(sanitized);
        final payload = Map<String, dynamic>.from(sanitized);
        payload['row_hash'] = rowHash;
        final createdAt = _asInt(sanitized['created_at']);
        final lastModified = _asInt(sanitized['last_modified']);
        final deletedAt = _asInt(sanitized['deleted_at']);
        final previous = existingMirror[localUuid];
        final clientTs = nowTs;
        bool emitted = false;

        if (deletedAt != null && deletedAt > normalizedSince) {
          payload['deleted_at'] = deletedAt;
          changes.add(DeltaSyncChange(
            entity: config.entity,
            operation: 'delete',
            data: payload,
            rowHash: rowHash,
            localUuid: localUuid,
            clientTimestamp: clientTs,
          ));
          debugPrint('إرسال كـ DELETE: ${config.entity}/$localUuid');
          emitted = true;
        } else {
          final shouldInsert = (createdAt != null && createdAt > normalizedSince) || (hasMirror && previous == null);
          if (shouldInsert || (!hasMirror && createdAt != null && createdAt > normalizedSince)) {
            changes.add(DeltaSyncChange(
              entity: config.entity,
              operation: 'insert',
              data: payload,
              rowHash: rowHash,
              localUuid: localUuid,
              clientTimestamp: clientTs,
            ));
            debugPrint('إرسال كـ INSERT: ${config.entity}/$localUuid');
            emitted = true;
          } else if (previous != null && lastModified != null && lastModified > normalizedSince) {
            changes.add(DeltaSyncChange(
              entity: config.entity,
              operation: 'update',
              data: payload,
              rowHash: rowHash,
              localUuid: localUuid,
              clientTimestamp: clientTs,
            ));
            debugPrint('إرسال كـ UPDATE: ${config.entity}/$localUuid');
            emitted = true;
          }
        }

        tableSnapshot[localUuid] = _MirrorRow(
          localUuid: localUuid,
          rowHash: rowHash,
          payload: Map<String, dynamic>.from(sanitized),
          lastSeenAt: nowTs,
        );
        seen.add(localUuid);

        if (!emitted && !hasMirror && createdAt != null && createdAt > normalizedSince) {
          changes.add(DeltaSyncChange(
            entity: config.entity,
            operation: 'insert',
            data: payload,
            rowHash: rowHash,
            localUuid: localUuid,
            clientTimestamp: clientTs,
          ));
          debugPrint('إرسال كـ INSERT: ${config.entity}/$localUuid');
        }
      }

      final missing = existingMirror.keys.where((uuid) => !seen.contains(uuid)).toList();
      for (final uuid in missing) {
        final previous = existingMirror[uuid];
        if (previous == null) {
          continue;
        }
        final payload = Map<String, dynamic>.from(previous.payload);
        final previousDeletedAt = _asInt(payload['deleted_at']);
        final deleteStamp = previousDeletedAt != null ? previousDeletedAt : nowTs;
        payload['deleted_at'] = deleteStamp;
        payload['row_hash'] = previous.rowHash;
        changes.add(DeltaSyncChange(
          entity: config.entity,
          operation: 'delete',
          data: payload,
          rowHash: previous.rowHash,
          localUuid: uuid,
          clientTimestamp: deleteStamp,
        ));
        debugPrint('إرسال كـ DELETE: ${config.entity}/$uuid');
      }

      snapshot[config.entity] = tableSnapshot;
    }

    final computation = DeltaSyncComputation(
      changes: changes,
      mirrorSnapshot: snapshot,
      fallbackTables: fallbackTables,
    );

    if (computation.changes.isEmpty && computation.mirrorSnapshot.isNotEmpty) {
      await persistMirror(computation);
    }

    return computation;
  }

  Future<void> persistMirror(DeltaSyncComputation computation) async {
    final snapshot = computation.mirrorSnapshot;
    await _ensureMirrorTable();
    await db.transaction(() async {
      for (final entry in snapshot.entries) {
        final table = entry.key;
        await db.customStatement('DELETE FROM sync_mirror WHERE table_name = ?', [table]);
        for (final row in entry.value.values) {
          await db.customStatement(
            'REPLACE INTO sync_mirror (table_name, local_uuid, row_hash, payload, last_seen_at) VALUES (?, ?, ?, ?, ?)',
            [
              table,
              row.localUuid,
              row.rowHash,
              jsonEncode(row.payload),
              row.lastSeenAt,
            ],
          );
        }
      }
    });
  }

  Future<void> _ensureMirrorTable() async {
    if (_mirrorTableReady) {
      return;
    }
    await db.customStatement('CREATE TABLE IF NOT EXISTS sync_mirror (table_name TEXT NOT NULL, local_uuid TEXT NOT NULL, row_hash TEXT NOT NULL, payload TEXT NOT NULL, last_seen_at INTEGER NOT NULL, PRIMARY KEY(table_name, local_uuid))');
    _mirrorTableReady = true;
  }

  Future<Map<String, Map<String, _MirrorRow>>> _loadMirror() async {
    await _ensureMirrorTable();
    final rows = await db.customSelect('SELECT table_name, local_uuid, row_hash, payload, last_seen_at FROM sync_mirror').get();
    final result = <String, Map<String, _MirrorRow>>{};
    for (final row in rows) {
      final table = row.read<String>('table_name');
      final uuid = row.read<String>('local_uuid');
      final payload = jsonDecode(row.read<String>('payload')) as Map<String, dynamic>;
      result
          .putIfAbsent(table, () => {})
          [uuid] = _MirrorRow(localUuid: uuid, rowHash: row.read<String>('row_hash'), payload: payload, lastSeenAt: row.read<int>('last_seen_at'));
    }
    return result;
  }

  List<_EntityConfig<dynamic>> _entityConfigs() {
    return [
      _EntityConfig<Room>(
        entity: 'rooms',
        fetchAll: () => db.select(db.rooms).get(),
        localUuid: (row) => row.localUuid,
        createdAt: (row) => row.createdAt,
        lastModified: (row) => row.lastModified,
        deletedAt: (row) => row.deletedAt,
        toJson: (row) => row.toJson(),
      ),
      _EntityConfig<Booking>(
        entity: 'bookings',
        fetchAll: () => db.select(db.bookings).get(),
        localUuid: (row) => row.localUuid,
        createdAt: (row) => row.createdAt,
        lastModified: (row) => row.lastModified,
        deletedAt: (row) => row.deletedAt,
        toJson: (row) => row.toJson(),
      ),
      _EntityConfig<BookingNote>(
        entity: 'booking_notes',
        fetchAll: () => db.select(db.bookingNotes).get(),
        localUuid: (row) => row.localUuid,
        createdAt: (row) => row.createdAt,
        lastModified: (row) => row.lastModified,
        deletedAt: (row) => row.deletedAt,
        toJson: (row) => row.toJson(),
      ),
      _EntityConfig<Employee>(
        entity: 'employees',
        fetchAll: () => db.select(db.employees).get(),
        localUuid: (row) => row.localUuid,
        createdAt: (row) => row.createdAt,
        lastModified: (row) => row.lastModified,
        deletedAt: (row) => row.deletedAt,
        toJson: (row) => row.toJson(),
      ),
      _EntityConfig<Expense>(
        entity: 'expenses',
        fetchAll: () => db.select(db.expenses).get(),
        localUuid: (row) => row.localUuid,
        createdAt: (row) => row.createdAt,
        lastModified: (row) => row.lastModified,
        deletedAt: (row) => row.deletedAt,
        toJson: (row) => row.toJson(),
      ),
      _EntityConfig<CashTransaction>(
        entity: 'cash_transactions',
        fetchAll: () => db.select(db.cashTransactions).get(),
        localUuid: (row) => row.localUuid,
        createdAt: (row) => row.createdAt,
        lastModified: (row) => row.lastModified,
        deletedAt: (row) => row.deletedAt,
        toJson: (row) => row.toJson(),
      ),
      _EntityConfig<Payment>(
        entity: 'payments',
        fetchAll: () => db.select(db.payments).get(),
        localUuid: (row) => row.localUuid,
        createdAt: (row) => row.createdAt,
        lastModified: (row) => row.lastModified,
        deletedAt: (row) => row.deletedAt,
        toJson: (row) => row.toJson(),
      ),
      _EntityConfig<Debt>(
        entity: 'debts',
        fetchAll: () => db.select(db.debts).get(),
        localUuid: (row) => row.localUuid,
        createdAt: (row) => row.createdAt,
        lastModified: (row) => row.lastModified,
        deletedAt: (row) => row.deletedAt,
        toJson: (row) => row.toJson(),
      ),
    ];
  }
}

class _MirrorRow {
  _MirrorRow({
    required this.localUuid,
    required this.rowHash,
    required this.payload,
    required this.lastSeenAt,
  });

  final String localUuid;
  final String rowHash;
  final Map<String, dynamic> payload;
  final int lastSeenAt;
}

class _EntityConfig<T> {
  const _EntityConfig({
    required this.entity,
    required this.fetchAll,
    required this.localUuid,
    required this.createdAt,
    required this.lastModified,
    required this.deletedAt,
    required this.toJson,
  });

  final String entity;
  final Future<List<T>> Function() fetchAll;
  final String Function(T row) localUuid;
  final int? Function(T row) createdAt;
  final int? Function(T row) lastModified;
  final int? Function(T row) deletedAt;
  final Map<String, dynamic> Function(T row) toJson;
}

int _normalizeTimestamp(int value) {
  if (value <= 0) {
    return value;
  }
  return value < 1000000000000 ? value * 1000 : value;
}

Map<String, dynamic> _preparePayload(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  source.forEach((key, value) {
    final newKey = _toSnakeCase(key);
    result[newKey] = _normalizeValue(value);
  });
  return result;
}

dynamic _normalizeValue(dynamic value) {
  if (value is int) {
    return _normalizeTimestamp(value);
  } else if (value is num) {
    return value;
  } else if (value is Map<String, dynamic>) {
    return _preparePayload(value);
  } else if (value is List) {
    return value.map((item) {
      if (item is Map<String, dynamic>) {
        return _preparePayload(item);
      }
      if (item is int) {
        return _normalizeTimestamp(item);
      }
      return item;
    }).toList();
  }
  return value;
}

String _hashPayload(Map<String, dynamic> payload) {
  final sorted = _sortedMap(payload);
  return sha1.convert(utf8.encode(jsonEncode(sorted))).toString();
}

Map<String, dynamic> _sortedMap(Map<String, dynamic> source) {
  final entries = source.entries.map((entry) {
    final value = entry.value;
    dynamic normalized;
    if (value is Map<String, dynamic>) {
      normalized = _sortedMap(value);
    } else if (value is List) {
      normalized = value.map((item) {
        if (item is Map<String, dynamic>) {
          return _sortedMap(item);
        }
        return item;
      }).toList();
    } else {
      normalized = value;
    }
    return MapEntry(entry.key, normalized);
  }).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return Map<String, dynamic>.fromEntries(entries);
}

String _toSnakeCase(String input) {
  final snake = input.replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (match) => '${match.group(1)}_${match.group(2)}');
  return snake.replaceAll('-', '_').toLowerCase();
}

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}
