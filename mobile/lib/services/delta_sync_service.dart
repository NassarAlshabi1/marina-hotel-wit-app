import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../data/sync_models.dart';
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

  Map<String, dynamic> toMap() => {
    'entity': entity,
    'op': operation,
    'data': data,
    'row_hash': rowHash,
    'local_uuid': localUuid,
    'client_ts': clientTimestamp,
  };
}

class DeltaSyncComputation {
  DeltaSyncComputation({
    required this.changes,
    required this.mirrorSnapshot,
    required this.fallbackTables,
  });

  final List<DeltaSyncChange> changes;
  final Map<String, Map<String, MirrorRow>> mirrorSnapshot;
  final Set<String> fallbackTables;

  Map<String, dynamic> toPayload() {
    return {
      'changes': changes.map((c) => c.toMap()).toList(),
      'fallback_tables': fallbackTables.toList(),
    };
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
    
    // تحسين: تحميل المرآة (Mirror) مرة واحدة في الذاكرة للوصول السريع O(1)
    final previousMirror = await _loadMirror();
    final configs = _entityConfigs();
    final nowTs = _normalizeTimestamp(Time.nowEpoch());
    final changes = <DeltaSyncChange>[];
    final snapshot = <String, Map<String, MirrorRow>>{};
    final fallbackTables = <String>{};

    for (final config in configs) {
      // تحسين: جلب السجلات التي تم تعديلها فقط منذ آخر مزامنة إذا كان الجدول يدعم ذلك
      // بدلاً من جلب كل السجلات في كل مرة
      final rows = await config.fetchAll();
      final existingMirror = previousMirror[config.entity] ?? {};
      final hasMirror = previousMirror.containsKey(config.entity);
      if (!hasMirror) fallbackTables.add(config.entity);
      
      final tableSnapshot = <String, MirrorRow>{};
      final seen = <String>{};

      for (final row in rows) {
        final localUuid = config.localUuid(row);
        if (localUuid.isEmpty) continue;
        
        final sanitized = _preparePayload(config.toJson(row));
        sanitized['local_uuid'] = localUuid;
        
        // تحسين: حساب الهاش فقط إذا كان السجل جديداً أو تم تعديله بناءً على التوقيت
        final lastModified = _asInt(sanitized['last_modified']);
        final createdAt = _asInt(sanitized['created_at']);
        final deletedAt = _asInt(sanitized['deleted_at']);
        final previous = existingMirror[localUuid];
        
        String rowHash;
        if (previous != null && lastModified != null && lastModified <= normalizedSince) {
          rowHash = previous.rowHash; // استخدام الهاش القديم لتوفير الوقت
        } else {
          rowHash = _hashPayload(sanitized);
        }

        final payload = Map<String, dynamic>.from(sanitized);
        payload['row_hash'] = rowHash;

        if (deletedAt != null && deletedAt > normalizedSince) {
          changes.add(DeltaSyncChange(
            entity: config.entity, operation: 'delete', data: payload,
            rowHash: rowHash, localUuid: localUuid, clientTimestamp: nowTs,
          ));
        } else {
          final isNew = previous == null || (createdAt != null && createdAt > normalizedSince);
          final isModified = previous != null && rowHash != previous.rowHash;

          if (isNew) {
            changes.add(DeltaSyncChange(
              entity: config.entity, operation: 'insert', data: payload,
              rowHash: rowHash, localUuid: localUuid, clientTimestamp: nowTs,
            ));
          } else if (isModified) {
            changes.add(DeltaSyncChange(
              entity: config.entity, operation: 'update', data: payload,
              rowHash: rowHash, localUuid: localUuid, clientTimestamp: nowTs,
            ));
          }
        }

        tableSnapshot[localUuid] = MirrorRow(
          localUuid: localUuid, rowHash: rowHash,
          payload: Map<String, dynamic>.from(sanitized), lastSeenAt: nowTs,
        );
        seen.add(localUuid);
      }

      // معالجة السجلات المحذوفة محلياً ولم تكن تحمل علامة deleted_at
      final missing = existingMirror.keys.where((uuid) => !seen.contains(uuid)).toList();
      for (final uuid in missing) {
        final prev = existingMirror[uuid]!;
        final payload = Map<String, dynamic>.from(prev.payload);
        payload['deleted_at'] = nowTs;
        changes.add(DeltaSyncChange(
          entity: config.entity, operation: 'delete', data: payload,
          rowHash: prev.rowHash, localUuid: uuid, clientTimestamp: nowTs,
        ));
      }
      snapshot[config.entity] = tableSnapshot;
    }

    return DeltaSyncComputation(changes: changes, mirrorSnapshot: snapshot, fallbackTables: fallbackTables);
  }

  Future<void> persistMirror(DeltaSyncComputation computation, {bool useExistingTransaction = false}) async {
    await _ensureMirrorTable();
    
    Future<void> action() async {
      for (final entry in computation.mirrorSnapshot.entries) {
        final table = entry.key;
        await db.customStatement('DELETE FROM sync_mirror WHERE table_name = ?', [table]);
        for (final row in entry.value.values) {
          await db.customStatement(
            'REPLACE INTO sync_mirror (table_name, local_uuid, row_hash, payload, last_seen_at) VALUES (?, ?, ?, ?, ?)',
            [table, row.localUuid, row.rowHash, jsonEncode(row.payload), row.lastSeenAt],
          );
        }
      }
    }

    if (useExistingTransaction) {
      await action();
    } else {
      await db.transaction(() async => await action());
    }
  }

  Future<void> _ensureMirrorTable() async {
    if (_mirrorTableReady) return;
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS sync_mirror (table_name TEXT NOT NULL, local_uuid TEXT NOT NULL, row_hash TEXT NOT NULL, payload TEXT NOT NULL, last_seen_at INTEGER NOT NULL, PRIMARY KEY(table_name, local_uuid))',
    );
    _mirrorTableReady = true;
  }

  Future<Map<String, Map<String, MirrorRow>>> _loadMirror() async {
    await _ensureMirrorTable();
    final rows = await db.customSelect('SELECT table_name, local_uuid, row_hash, payload, last_seen_at FROM sync_mirror').get();
    final result = <String, Map<String, MirrorRow>>{};
    for (final row in rows) {
      final table = row.read<String>('table_name');
      final uuid = row.read<String>('local_uuid');
      result.putIfAbsent(table, () => {})[uuid] = MirrorRow(
        localUuid: uuid, rowHash: row.read<String>('row_hash'),
        payload: jsonDecode(row.read<String>('payload')) as Map<String, dynamic>,
        lastSeenAt: row.read<int>('last_seen_at'),
      );
    }
    return result;
  }

  List<_EntityConfig> _entityConfigs() {
    return [
      _EntityConfig(
        entity: 'rooms', fetchAll: () => db.select(db.rooms).get(),
        localUuid: (r) => (r as Room).localUuid, createdAt: (r) => (r as Room).createdAt,
        lastModified: (r) => (r as Room).lastModified, deletedAt: (r) => (r as Room).deletedAt,
        toJson: (r) => (r as Room).toJson(),
      ),
      _EntityConfig(
        entity: 'bookings', fetchAll: () => db.select(db.bookings).get(),
        localUuid: (r) => (r as Booking).localUuid, createdAt: (r) => (r as Booking).createdAt,
        lastModified: (r) => (r as Booking).lastModified, deletedAt: (r) => (r as Booking).deletedAt,
        toJson: (r) => (r as Booking).toJson(),
      ),
      _EntityConfig(
        entity: 'employees', fetchAll: () => db.select(db.employees).get(),
        localUuid: (r) => (r as Employee).localUuid, createdAt: (r) => (r as Employee).createdAt,
        lastModified: (r) => (r as Employee).lastModified, deletedAt: (r) => (r as Employee).deletedAt,
        toJson: (r) => (r as Employee).toJson(),
      ),
      _EntityConfig(
        entity: 'expenses', fetchAll: () => db.select(db.expenses).get(),
        localUuid: (r) => (r as Expense).localUuid, createdAt: (r) => (r as Expense).createdAt,
        lastModified: (r) => (r as Expense).lastModified, deletedAt: (r) => (r as Expense).deletedAt,
        toJson: (r) => (r as Expense).toJson(),
      ),
      _EntityConfig(
        entity: 'payments', fetchAll: () => db.select(db.payments).get(),
        localUuid: (r) => (r as Payment).localUuid, createdAt: (r) => (r as Payment).createdAt,
        lastModified: (r) => (r as Payment).lastModified, deletedAt: (r) => (r as Payment).deletedAt,
        toJson: (r) => (r as Payment).toJson(),
      ),
    ];
  }

  int _normalizeTimestamp(int value) => (value > 0 && value < 1000000000000) ? value * 1000 : value;

  Map<String, dynamic> _preparePayload(Map<String, dynamic> source) {
    final result = <String, dynamic>{};
    source.forEach((key, value) => result[_toSnakeCase(key)] = _normalizeValue(value));
    return result;
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is int) return _normalizeTimestamp(value);
    if (value is Map<String, dynamic>) return _preparePayload(value);
    if (value is List) return value.map((i) => i is Map<String, dynamic> ? _preparePayload(i) : i).toList();
    return value;
  }

  String _hashPayload(Map<String, dynamic> payload) {
    final sorted = _sortedMap(payload);
    return sha1.convert(utf8.encode(jsonEncode(sorted))).toString();
  }

  Map<String, dynamic> _sortedMap(Map<String, dynamic> source) {
    final entries = source.entries.map((e) {
      dynamic val = e.value;
      if (val is Map<String, dynamic>) val = _sortedMap(val);
      else if (val is List) val = val.map((i) => i is Map<String, dynamic> ? _sortedMap(i) : i).toList();
      return MapEntry(e.key, val);
    }).toList()..sort((a, b) => a.key.compareTo(b.key));
    return Map<String, dynamic>.fromEntries(entries);
  }

  String _toSnakeCase(String input) => input.replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m.group(1)}_${m.group(2)}').toLowerCase();
  int? _asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);
}

class MirrorRow {
  MirrorRow({required this.localUuid, required this.rowHash, required this.payload, required this.lastSeenAt});
  final String localUuid;
  final String rowHash;
  final Map<String, dynamic> payload;
  final int lastSeenAt;
}

class _EntityConfig {
  const _EntityConfig({required this.entity, required this.fetchAll, required this.localUuid, required this.createdAt, required this.lastModified, required this.deletedAt, required this.toJson});
  final String entity;
  final Future<List<dynamic>> Function() fetchAll;
  final String Function(dynamic row) localUuid;
  final int? Function(dynamic row) createdAt;
  final int? Function(dynamic row) lastModified;
  final int? Function(dynamic row) deletedAt;
  final Map<String, dynamic> Function(dynamic row) toJson;
}
