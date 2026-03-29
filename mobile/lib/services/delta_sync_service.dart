import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/sync_models.dart';
import '../utils/time.dart';
import '../utils/id.dart';
import 'local_db.dart';
import 'field_level_sync.dart';
import 'vector_clock.dart';

// ============================================================================
// Performance Utilities
// ============================================================================

/// Circuit Breaker لمنع تكرار الفشل
class SyncCircuitBreaker {
  int _failureCount = 0;
  DateTime? _lastFailure;
  static const _threshold = 5;
  static const _resetTimeout = Duration(minutes: 1);

  bool get isOpen {
    if (_failureCount < _threshold) return false;
    if (_lastFailure == null) return true;
    final shouldReset =
        DateTime.now().difference(_lastFailure!) > _resetTimeout;
    if (shouldReset) {
      _failureCount = 0;
      _lastFailure = null;
      return false;
    }
    return true;
  }

  void recordFailure() {
    _failureCount++;
    _lastFailure = DateTime.now();
  }

  void recordSuccess() {
    _failureCount = 0;
    _lastFailure = null;
  }

  void reset() {
    _failureCount = 0;
    _lastFailure = null;
  }
}

/// مراقب أداء المزامنة
class SyncPerformanceMonitor {
  final _timings = <String, List<int>>{};

  /// قياس زمن تنفيذ عملية
  Future<T> measure<T>(String label, Future<T> Function() operation) async {
    final sw = Stopwatch()..start();
    try {
      return await operation();
    } finally {
      sw.stop();
      _timings.putIfAbsent(label, () => []).add(sw.elapsedMilliseconds);
    }
  }

  /// الحصول على آخر زمن لعملية
  int? lastMs(String label) {
    final list = _timings[label];
    if (list == null || list.isEmpty) return null;
    return list.last;
  }

  /// الحصول على متوسط زمن لعملية
  double? avgMs(String label) {
    final list = _timings[label];
    if (list == null || list.isEmpty) return null;
    return list.reduce((a, b) => a + b) / list.length;
  }

  /// ملخص الأداء
  Map<String, int> summary() {
    final result = <String, int>{};
    for (final entry in _timings.entries) {
      if (entry.value.isNotEmpty) {
        result[entry.key] = entry.value.last;
      }
    }
    return result;
  }

  void reset() => _timings.clear();
}

/// LRU Cache بسيط لـ JSON
class _JsonCache {
  final _cache = <String, String>{};
  static const _maxSize = 500;

  String encode(String key, Map<String, dynamic> payload) {
    final cached = _cache[key];
    if (cached != null) return cached;

    final json = jsonEncode(payload);
    if (_cache.length >= _maxSize) {
      _cache.clear();
    }
    _cache[key] = json;
    return json;
  }

  int get size => _cache.length;
  void clear() => _cache.clear();
}

/// Semaphore بسيط للتحكم في التزامن
class _Semaphore {
  _Semaphore(this._maxConcurrent);
  final int _maxConcurrent;
  int _current = 0;
  final _waiting = <Completer<void>>[];

  Future<void> acquire() async {
    if (_current < _maxConcurrent) {
      _current++;
      return;
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    await completer.future;
  }

  void release() {
    if (_waiting.isNotEmpty) {
      final next = _waiting.removeAt(0);
      next.complete();
    } else {
      _current--;
    }
  }
}

// ============================================================================
// Delta Sync Core Classes
// ============================================================================

class DeltaSyncChange {
  DeltaSyncChange({
    required this.entity,
    required this.operation,
    required this.data,
    required this.rowHash,
    required this.localUuid,
    required this.clientTimestamp,
    this.fieldMetadata,
    this.fieldChanges,
  });

  final String entity;
  final String operation;
  final Map<String, dynamic> data;
  final String rowHash;
  final String localUuid;
  final int clientTimestamp;

  /// ✅ Field-Level: metadata للحقول المتغيرة
  final FieldMetadata? fieldMetadata;

  /// ✅ Field-Level: قائمة الحقول المتغيرة
  final List<FieldChange>? fieldChanges;

  Map<String, dynamic> toMap() {
    return {
      'entity': entity,
      'op': operation,
      'data': data,
      'rowHash': rowHash,
      'localUuid': localUuid,
      'clientTs': clientTimestamp,
      if (fieldMetadata != null)
        '_fieldMetadata': fieldMetadata!.toJson(),
      if (fieldChanges != null)
        '_fieldChanges': fieldChanges!.map((c) => c.toJson()).toList(),
    };
  }

  /// ✅ الحقول المتغيرة فقط (للإرسال)
  Map<String, dynamic> get changedFieldsPayload {
    if (fieldChanges == null || fieldChanges!.isEmpty) {
      return data;
    }

    final payload = <String, dynamic>{
      'localUuid': localUuid,
      'syncTimestamp': clientTimestamp,
    };

    for (final change in fieldChanges!) {
      payload[change.fieldName] = change.newValue;
      payload['_${change.fieldName}_version'] = change.version;
      payload['_${change.fieldName}_timestamp'] = change.timestamp;
      payload['_${change.fieldName}_device'] = change.deviceId;
    }

    return payload;
  }
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

  List<Map<String, dynamic>> toPayload() {
    return changes.map((c) => c.toMap()).toList();
  }
}

// ============================================================================
// DeltaSyncService - المحسّن
// ============================================================================

class DeltaSyncService {
  DeltaSyncService(this.db, {String? deviceId})
      : _deviceId = deviceId ?? IdGen.uuid();

  final AppDatabase db;
  final String _deviceId;
  bool _mirrorTableReady = false;

  // ✅ تحسين 1: Cache للـ Mirror في الذاكرة
  Map<String, Map<String, MirrorRow>>? _mirrorCache;
  DateTime? _mirrorCacheTime;
  static const _cacheValidity = Duration(seconds: 30);

  // ✅ تحسين 6: JSON Cache
  final _jsonCache = _JsonCache();

  // ✅ تحسين 8: Circuit Breaker
  final _circuitBreaker = SyncCircuitBreaker();

  // ✅ تحسين 9: Performance Monitor
  final perf = SyncPerformanceMonitor();

  /// ✅ Field-Level: الحصول على deviceId
  String get deviceId => _deviceId;

  // ✅ تحسين 1: Preload غير متزامن (Connection Warm-up)
  Future<void> warmUp() async {
    await perf.measure('warmup', () async {
      await Future.wait([
        _loadMirror().then((m) {
          _mirrorCache = m;
          _mirrorCacheTime = DateTime.now();
        }),
        _ensureMirrorTable(),
        _preloadEntityConfigs(),
      ]);
    });
    if (kDebugMode) {
      debugPrint('🚀 DeltaSync warmup completed (${perf.lastMs("warmup")}ms)');
    }
  }

  Future<void> _preloadEntityConfigs() async {
    // Force loading of entity configs to cache them in memory
    _entityConfigs();
  }

  // ✅ تحسين 1: استخدام الكاش مع fallback
  Future<Map<String, Map<String, MirrorRow>>> _getMirror() async {
    if (_mirrorCache != null &&
        _mirrorCacheTime != null &&
        DateTime.now().difference(_mirrorCacheTime!) < _cacheValidity) {
      return _mirrorCache!;
    }
    return _loadMirror();
  }

  // ✅ تحسين 8: فحص Circuit Breaker قبل التشغيل
  Future<DeltaSyncComputation> compute({int? since}) async {
    if (_circuitBreaker.isOpen) {
      debugPrint('⚠️ Sync circuit breaker is OPEN — skipping compute');
      final emptySnapshot = <String, Map<String, MirrorRow>>{};
      return DeltaSyncComputation(
        changes: [],
        mirrorSnapshot: emptySnapshot,
        fallbackTables: {},
      );
    }

    return await perf.measure('compute', () async {
      try {
        final result = await _computeInternal(since: since);
        _circuitBreaker.recordSuccess();
        return result;
      } catch (e) {
        _circuitBreaker.recordFailure();
        rethrow;
      }
    });
  }

  /// ✅ تحسين 5: المعالجة الداخلية المحسّنة
  Future<DeltaSyncComputation> _computeInternal({int? since}) async {
    // ✅ تحسين 1: جلب state + mirror بالتوازي
    final results = await Future.wait([
      (db.select(db.syncState)..where((t) => t.id.equals(1)))
          .getSingleOrNull(),
      _getMirror(),
    ]);

    final state = results[0] as dynamic;
    final previousMirror =
        results[1] as Map<String, Map<String, MirrorRow>>;

    final baseSince = since ?? (state?.lastPushTs as int?) ?? 0;
    final normalizedSince = _normalizeTimestamp(baseSince);
    final configs = _entityConfigs();
    final nowTs = _normalizeTimestamp(Time.nowEpoch());

    // ✅ تحسين 5: جلب كل الكيانات بشكل موازٍ
    final allRowsFutures =
        await perf.measure('fetchAll', () => Future.wait(configs.map((c) => c.fetchAll())));

    // ✅ تحسين 5: معالجة موازية مع Semaphore (4 كيانات في نفس الوقت)
    final semaphore = _Semaphore(4);
    final entityResults = await perf.measure('processEntities', () async {
      return await Future.wait(
        configs.asMap().entries.map((entry) async {
          await semaphore.acquire();
          try {
            return _processEntity(
              config: entry.value,
              rows: allRowsFutures[entry.key],
              existingMirror: previousMirror[entry.value.entity] ?? {},
              hasMirror: previousMirror.containsKey(entry.value.entity),
              normalizedSince: normalizedSince,
              nowTs: nowTs,
            );
          } finally {
            semaphore.release();
          }
        }),
      );
    });

    // ✅ تجميع النتائج
    final changes = <DeltaSyncChange>[];
    final snapshot = <String, Map<String, MirrorRow>>{};
    final fallbackTables = <String>{};

    for (int i = 0; i < entityResults.length; i++) {
      final result = entityResults[i];
      final config = configs[i];
      if (!previousMirror.containsKey(config.entity)) {
        fallbackTables.add(config.entity);
        debugPrint(
          '⚠️ تعذر إعادة بناء مرآة جدول ${config.entity}، سيتم الاعتماد على createdAt فقط',
        );
      }
      changes.addAll(result.changes);
      snapshot[config.entity] = result.snapshot;
    }

    final computation = DeltaSyncComputation(
      changes: changes,
      mirrorSnapshot: snapshot,
      fallbackTables: fallbackTables,
    );

    if (computation.changes.isEmpty && computation.mirrorSnapshot.isNotEmpty) {
      await persistMirror(computation);
    }

    // ✅ تحديث Mirror Cache
    _mirrorCache = snapshot;
    _mirrorCacheTime = DateTime.now();

    // ✅ Log الأداء
    if (kDebugMode && changes.isNotEmpty) {
      debugPrint(
        '📊 DeltaSync compute: ${changes.length} changes in '
        '${perf.lastMs("compute")}ms '
        '(fetch: ${perf.lastMs("fetchAll")}ms, '
        'process: ${perf.lastMs("processEntities")}ms)',
      );
    }

    return computation;
  }

  /// ✅ معالجة كيان واحد
  _EntityProcessResult _processEntity({
    required _EntityConfig config,
    required List<dynamic> rows,
    required Map<String, MirrorRow> existingMirror,
    required bool hasMirror,
    required int normalizedSince,
    required int nowTs,
  }) {
    final changes = <DeltaSyncChange>[];
    final tableSnapshot = <String, MirrorRow>{};
    final seen = <String>{};

    for (final row in rows) {
      final localUuid = config.localUuid(row);
      if (localUuid.isEmpty) continue;

      final sanitized = _preparePayload(config.toJson(row));
      sanitized['localUuid'] = localUuid;
      final rowHash = _hashPayload(sanitized);
      final payload = Map<String, dynamic>.from(sanitized);
      payload['rowHash'] = rowHash;

      final createdAt = _asInt(sanitized['createdAt']);
      final lastModified = _asInt(sanitized['lastModified']);
      final deletedAt = _asInt(sanitized['deletedAt']);
      final previous = existingMirror[localUuid];
      final clientTs = nowTs;

      if (deletedAt != null && deletedAt > normalizedSince) {
        payload['deletedAt'] = deletedAt;
        changes.add(DeltaSyncChange(
          entity: config.entity,
          operation: 'delete',
          data: payload,
          rowHash: rowHash,
          localUuid: localUuid,
          clientTimestamp: clientTs,
        ));
      } else {
        final isFirstSyncForTable = !hasMirror;
        final isNewRecordInMirror = previous == null;
        final createdAfterLastSync =
            createdAt != null && createdAt > normalizedSince;

        final shouldInsert = isFirstSyncForTable ||
            (hasMirror && isNewRecordInMirror) ||
            createdAfterLastSync;

        if (shouldInsert) {
          changes.add(DeltaSyncChange(
            entity: config.entity,
            operation: 'insert',
            data: payload,
            rowHash: rowHash,
            localUuid: localUuid,
            clientTimestamp: clientTs,
          ));
        } else if (previous != null &&
            lastModified != null &&
            lastModified > normalizedSince &&
            rowHash != previous.rowHash) {
          // ✅ تحسين 3: فحص hash سريع قبل diff مفصل
          final fieldLevelDiff = _computeFieldLevelDiffOptimized(
            config.entity,
            previous.payload,
            payload,
            previous.fieldVersions ?? {},
            previous.fieldTimestamps ?? {},
            previous.fieldVectorClocks ?? {},
            previous.fieldDevices ?? {},
            _deviceId,
          );

          if (fieldLevelDiff.isNotEmpty) {
            final diff = Map<String, dynamic>.from(fieldLevelDiff.changedFields);
            diff['localUuid'] = localUuid;
            diff['lastModified'] = lastModified;
            if (payload.containsKey('version')) diff['version'] = payload['version'];
            if (payload.containsKey('vectorClock')) diff['vectorClock'] = payload['vectorClock'];

            changes.add(DeltaSyncChange(
              entity: config.entity,
              operation: 'update',
              data: diff,
              rowHash: rowHash,
              localUuid: localUuid,
              clientTimestamp: clientTs,
              fieldMetadata: FieldMetadata(
                versions: fieldLevelDiff.fieldVersions,
                timestamps: fieldLevelDiff.fieldTimestamps,
                vectorClocks: fieldLevelDiff.fieldVectorClocks,
                devices: fieldLevelDiff.fieldDevices,
              ),
              fieldChanges:
                  fieldLevelDiff.toFieldChanges(_deviceId, _deviceId),
            ));
          }
        }
      }

      tableSnapshot[localUuid] = MirrorRow(
        localUuid: localUuid,
        rowHash: rowHash,
        payload: Map<String, dynamic>.from(sanitized),
        lastSeenAt: nowTs,
        // ✅ تحسين 3: تخزين fieldsHash في الـ Mirror
        fieldsHash: _hashFieldsOnly(sanitized),
      );
      seen.add(localUuid);
    }

    // ✅ اكتشاف السجلات المحذوفة
    final missing = existingMirror.keys
        .where((uuid) => !seen.contains(uuid))
        .toList();
    for (final uuid in missing) {
      final previous = existingMirror[uuid];
      if (previous == null) continue;

      final payload = Map<String, dynamic>.from(previous.payload);
      final previousDeletedAt =
          _asInt(payload['deletedAt'] ?? payload['deleted_at']);
      final deleteStamp = previousDeletedAt ?? nowTs;
      payload['deletedAt'] = deleteStamp;
      payload['rowHash'] = previous.rowHash;

      changes.add(DeltaSyncChange(
        entity: config.entity,
        operation: 'delete',
        data: payload,
        rowHash: previous.rowHash,
        localUuid: uuid,
        clientTimestamp: deleteStamp,
      ));
    }

    return _EntityProcessResult(changes: changes, snapshot: tableSnapshot);
  }

  // ✅ تحسين 7: Stream API للمعالجة الكبيرة
  Stream<DeltaSyncChange> computeStream({int? since}) async* {
    final state = await (db.select(db.syncState)
            ..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    final baseSince = since ?? state?.lastPushTs ?? 0;
    final normalizedSince = _normalizeTimestamp(baseSince);
    final previousMirror = await _loadMirror();
    final configs = _entityConfigs();
    final nowTs = _normalizeTimestamp(Time.nowEpoch());

    for (final config in configs) {
      final rows = await config.fetchAll();
      final existingMirror = previousMirror[config.entity] ?? {};
      final hasMirror = previousMirror.containsKey(config.entity);

      for (final row in rows) {
        final localUuid = config.localUuid(row);
        if (localUuid.isEmpty) continue;

        final sanitized = _preparePayload(config.toJson(row));
        sanitized['localUuid'] = localUuid;
        final rowHash = _hashPayload(sanitized);

        final createdAt = _asInt(sanitized['createdAt']);
        final lastModified = _asInt(sanitized['lastModified']);
        final deletedAt = _asInt(sanitized['deletedAt']);
        final previous = existingMirror[localUuid];

        if (deletedAt != null && deletedAt > normalizedSince) {
          final payload = Map<String, dynamic>.from(sanitized)
            ..['rowHash'] = rowHash
            ..['deletedAt'] = deletedAt;
          yield DeltaSyncChange(
            entity: config.entity,
            operation: 'delete',
            data: payload,
            rowHash: rowHash,
            localUuid: localUuid,
            clientTimestamp: nowTs,
          );
        } else if (previous == null ||
            (createdAt != null && createdAt > normalizedSince)) {
          final payload = Map<String, dynamic>.from(sanitized)
            ..['rowHash'] = rowHash;
          yield DeltaSyncChange(
            entity: config.entity,
            operation: 'insert',
            data: payload,
            rowHash: rowHash,
            localUuid: localUuid,
            clientTimestamp: nowTs,
          );
        } else if (previous != null &&
            lastModified != null &&
            lastModified > normalizedSince &&
            rowHash != previous.rowHash) {
          final diff = _computeFieldLevelDiffOptimized(
            config.entity,
            previous.payload,
            sanitized,
            previous.fieldVersions ?? {},
            previous.fieldTimestamps ?? {},
            previous.fieldVectorClocks ?? {},
            previous.fieldDevices ?? {},
            _deviceId,
          );
          if (diff.isNotEmpty) {
            yield DeltaSyncChange(
              entity: config.entity,
              operation: 'update',
              data: diff.changedFields,
              rowHash: rowHash,
              localUuid: localUuid,
              clientTimestamp: nowTs,
            );
          }
        }

        // ✅ Yield control back to event loop
        await Future.delayed(Duration.zero);
      }
    }
  }

  Future<void> persistMirror(
    DeltaSyncComputation computation, {
    bool useExistingTransaction = false,
  }) async {
    final snapshot = computation.mirrorSnapshot;
    await _ensureMirrorTable();
    if (useExistingTransaction) {
      await _persistMirrorSnapshotBatch(snapshot);
    } else {
      await db.transaction(() async {
        await _persistMirrorSnapshotBatch(snapshot);
      });
    }

    // ✅ تحديث Cache
    _mirrorCache = snapshot;
    _mirrorCacheTime = DateTime.now();
  }

  // ✅ تحسين 2: دفعة واحدة بدلاً من loop
  Future<void> _persistMirrorSnapshotBatch(
    Map<String, Map<String, MirrorRow>> snapshot,
  ) async {
    for (final entry in snapshot.entries) {
      final table = entry.key;
      final rows = entry.value;

      if (rows.isEmpty) continue;

      // ✅ حذف ذكي: فقط الصفوف غير الموجودة في الـ snapshot الجديد
      if (rows.length > 0) {
        final uuids =
            rows.keys.map((u) => "'${u.replaceAll("'", "''")}'").join(',');
        await db.customStatement(
          'DELETE FROM sync_mirror WHERE sync_entity_name = ? AND local_uuid NOT IN ($uuids)',
          [table],
        );
      }

      // ✅ Batch INSERT بدلاً من loop
      final batch = <List<dynamic>>[];
      for (final row in rows.values) {
        final json = _jsonCache.encode(
          '${table}_${row.localUuid}',
          row.payload,
        );
        batch.add([table, row.localUuid, row.rowHash, json, row.lastSeenAt]);
      }

      if (batch.isNotEmpty) {
        final placeholders =
            batch.map((_) => '(?, ?, ?, ?, ?)').join(',');
        final flat = batch.expand((x) => x).toList();
        await db.customStatement(
          'INSERT OR REPLACE INTO sync_mirror (sync_entity_name, local_uuid, row_hash, payload, last_seen_at) VALUES $placeholders',
          flat,
        );
      }
    }
  }

  /// ✅ دعم legacy: المزامنة القديمة صف-by-صف (للتوافق)
  Future<void> _persistMirrorSnapshot(
    Map<String, Map<String, MirrorRow>> snapshot,
  ) async {
    await _persistMirrorSnapshotBatch(snapshot);
  }

  // ✅ تحسين 2: إضافة فهارس للأداء
  Future<void> _ensureMirrorTable() async {
    if (_mirrorTableReady) return;

    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS sync_mirror (
        sync_entity_name TEXT NOT NULL,
        local_uuid TEXT NOT NULL,
        row_hash TEXT NOT NULL,
        payload TEXT NOT NULL,
        last_seen_at INTEGER NOT NULL,
        PRIMARY KEY(sync_entity_name, local_uuid)
      )
    ''');

    // ✅ فهارس للبحث السريع
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_mirror_entity ON sync_mirror(sync_entity_name)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_mirror_seen ON sync_mirror(last_seen_at)',
    );

    _mirrorTableReady = true;
  }

  Future<Map<String, Map<String, MirrorRow>>> _loadMirror() async {
    await _ensureMirrorTable();
    final rows = await db
        .customSelect(
          'SELECT sync_entity_name, local_uuid, row_hash, payload, last_seen_at FROM sync_mirror',
        )
        .get();
    final result = <String, Map<String, MirrorRow>>{};
    for (final row in rows) {
      final table = row.read<String>('sync_entity_name');
      final uuid = row.read<String>('local_uuid');
      final payload =
          jsonDecode(row.read<String>('payload')) as Map<String, dynamic>;
      result.putIfAbsent(table, () => {})[uuid] = MirrorRow(
        localUuid: uuid,
        rowHash: row.read<String>('row_hash'),
        payload: payload,
        lastSeenAt: row.read<int>('last_seen_at'),
      );
    }
    return result;
  }

  /// التحقق من صحة Mirror ومقارنته مع قاعدة البيانات الفعلية
  Future<MirrorValidationResult> validateMirror() async {
    final issues = <String>[];
    final configs = _entityConfigs();
    final mirrorRows = await _loadMirror();

    for (final config in configs) {
      try {
        final currentRows = await config.fetchAll();
        final tableMirror = mirrorRows[config.entity] ?? {};

        if (currentRows.length != tableMirror.length) {
          issues.add(
            '${config.entity}: row count mismatch (current: ${currentRows.length}, mirror: ${tableMirror.length})',
          );
        }

        final int sampleSize =
            (currentRows.length * 0.1).ceil().clamp(1, 50);
        final sample = (currentRows..shuffle()).take(sampleSize);

        for (final row in sample) {
          final uuid = config.localUuid(row);
          if (uuid.isEmpty) continue;

          final mirrorRow = tableMirror[uuid];
          if (mirrorRow == null) {
            issues.add('${config.entity}: missing mirror for $uuid');
            continue;
          }

          final sanitized = _preparePayload(config.toJson(row));
          sanitized['localUuid'] = uuid;
          final currentHash = _hashPayload(sanitized);

          if (currentHash != mirrorRow.rowHash) {
            issues.add('${config.entity}: hash mismatch for $uuid');
          }
        }
      } catch (e) {
        issues.add('${config.entity}: validation error - $e');
      }
    }

    return MirrorValidationResult(
      isValid: issues.isEmpty,
      issues: issues,
      validatedAt: DateTime.now(),
    );
  }

  /// إصلاح Mirror تلقائياً إذا كان غير متسق
  Future<void> repairMirrorIfNeeded() async {
    final validation = await validateMirror();
    if (!validation.isValid) {
      debugPrint('⚠️ Mirror inconsistency detected, repairing...');
      debugPrint('Issues: ${validation.issues.join(', ')}');
      await rebuildMirror();
    }
  }

  /// ✅ تحسين 2: إعادة بناء محسّنة مع batch INSERT
  Future<void> rebuildMirror() async {
    await _ensureMirrorTable();
    await db.customStatement('DELETE FROM sync_mirror');

    final configs = _entityConfigs();
    final nowTs = _normalizeTimestamp(Time.nowEpoch());

    for (final config in configs) {
      try {
        final rows = await config.fetchAll();
        if (rows.isEmpty) continue;

        final batch = <List<dynamic>>[];
        for (final row in rows) {
          final uuid = config.localUuid(row);
          if (uuid.isEmpty) continue;

          final sanitized = _preparePayload(config.toJson(row));
          sanitized['localUuid'] = uuid;
          final rowHash = _hashPayload(sanitized);

          batch.add([
            config.entity,
            uuid,
            rowHash,
            _jsonCache.encode('${config.entity}_$uuid', sanitized),
            nowTs,
          ]);
        }

        if (batch.isNotEmpty) {
          final placeholders =
              batch.map((_) => '(?, ?, ?, ?, ?)').join(',');
          final flat = batch.expand((x) => x).toList();
          await db.customStatement(
            'INSERT OR REPLACE INTO sync_mirror (sync_entity_name, local_uuid, row_hash, payload, last_seen_at) VALUES $placeholders',
            flat,
          );
        }

        debugPrint(
          '✅ Rebuilt mirror for ${config.entity} (${rows.length} rows)',
        );
      } catch (e) {
        debugPrint('❌ Failed to rebuild mirror for ${config.entity}: $e');
      }
    }

    // ✅ تحديث Cache
    _mirrorCache = null;
    _mirrorCacheTime = null;

    debugPrint('✅ Mirror rebuild completed');
  }

  // ✅ تحسين 4: تقليل التكرار باستخدام factory method
  List<_EntityConfig> _entityConfigs() => [
        _makeConfig<Room>(
          'rooms',
          () => db.select(db.rooms).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<Booking>(
          'bookings',
          () => db.select(db.bookings).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<BookingNote>(
          'booking_notes',
          () => db.select(db.bookingNotes).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<Employee>(
          'employees',
          () => db.select(db.employees).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<Expense>(
          'expenses',
          () => db.select(db.expenses).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<CashTransaction>(
          'cash_transactions',
          () => db.select(db.cashTransactions).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<Payment>(
          'payments',
          () => db.select(db.payments).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<Debt>(
          'debts',
          () => db.select(db.debts).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<BookingNight>(
          'booking_nights',
          () => db.select(db.bookingNights).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<BookingPriceAdjustment>(
          'booking_price_adjustments',
          () => db.select(db.bookingPriceAdjustments).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        // ❌ hotel_day_ledger - محلي فقط، لا يتم مزامنته
        _makeConfig<ShiftNote>(
          'shift_notes',
          () => db.select(db.shiftNotes).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<SalaryCycle>(
          'salary_cycles',
          () => db.select(db.salaryCycles).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<SalaryPayment>(
          'salary_payments',
          () => db.select(db.salaryPayments).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<PriceAdjustment>(
          'price_adjustments',
          () => db.select(db.priceAdjustments).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        _makeConfig<AuditLog>(
          'audit_logs',
          () => db.select(db.auditLogs).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.createdAt,
          (row) => null,
          (row) => row.toJson(),
        ),
        _makeConfig<PaymentVoid>(
          'payment_voids',
          () => db.select(db.paymentVoids).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
        // ✅ كيانات جديدة
        _makeConfig<SalaryWithdrawal>(
          'salary_withdrawals',
          () => db.select(db.salaryWithdrawals).get(),
          (row) => row.localUuid,
          (row) => row.createdAt,
          (row) => row.lastModified,
          (row) => row.deletedAt,
          (row) => row.toJson(),
        ),
      ];

  /// ✅ تحسين 4: Factory method لتقليل تكرار كود Entity Configs
  _EntityConfig _makeConfig<T>(
    String entity,
    Future<List<dynamic>> Function() fetchAll,
    String Function(T row) localUuid,
    int? Function(T row) createdAt,
    int? Function(T row) lastModified,
    int? Function(T row) deletedAt,
    Map<String, dynamic> Function(T row) toJson,
  ) {
    return _EntityConfig(
      entity: entity,
      fetchAll: fetchAll,
      localUuid: (dynamic row) => localUuid(row as T),
      createdAt: (dynamic row) => createdAt(row as T),
      lastModified: (dynamic row) => lastModified(row as T),
      deletedAt: (dynamic row) {
        final r = row as T;
        return deletedAt(r);
      },
      toJson: (dynamic row) => toJson(row as T),
    );
  }
}

// ============================================================================
// Supporting Classes
// ============================================================================

/// نتيجة معالجة كيان واحد
class _EntityProcessResult {
  const _EntityProcessResult({
    required this.changes,
    required this.snapshot,
  });

  final List<DeltaSyncChange> changes;
  final Map<String, MirrorRow> snapshot;
}

class MirrorRow {
  MirrorRow({
    required this.localUuid,
    required this.rowHash,
    required this.payload,
    required this.lastSeenAt,
    this.fieldVersions = const {},
    this.fieldTimestamps = const {},
    this.fieldVectorClocks = const {},
    this.fieldDevices = const {},
    this.fieldsHash,
  });

  final String localUuid;
  final String rowHash;
  final Map<String, dynamic> payload;
  final int lastSeenAt;

  /// ✅ Field-Level: نسخ الحقول
  final Map<String, int> fieldVersions;

  /// ✅ Field-Level: طوابع زمنية للحقول
  final Map<String, int> fieldTimestamps;

  /// ✅ Field-Level: Vector Clocks للحقول
  final Map<String, String> fieldVectorClocks;

  /// ✅ Field-Level: أجهزة الحقول
  final Map<String, String> fieldDevices;

  /// ✅ تحسين 3: Hash سريع للحقول (بدون حقول النظام)
  final String? fieldsHash;
}

class _EntityConfig {
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
  final Future<List<dynamic>> Function() fetchAll;
  final String Function(dynamic row) localUuid;
  final int? Function(dynamic row) createdAt;
  final int? Function(dynamic row) lastModified;
  final int? Function(dynamic row) deletedAt;
  final Map<String, dynamic> Function(dynamic row) toJson;
}

// ============================================================================
// Utility Functions
// ============================================================================

int _normalizeTimestamp(int value) {
  if (value <= 0) return value;
  return value < 1000000000000 ? value * 1000 : value;
}

/// تحضير البيانات للحفظ في sync_mirror
Map<String, dynamic> _preparePayload(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  source.forEach((key, value) {
    final normalizedKey = _toCamelCase(key);
    if (normalizedKey == 'vectorClock' && value is Map) {
      result[normalizedKey] = jsonEncode(value);
    } else {
      result[normalizedKey] = _normalizeValue(value, key: normalizedKey);
    }
  });
  return result;
}

/// ✅ تحسين 3: Hash للحقول فقط (بدون حقول النظام)
String _hashFieldsOnly(Map<String, dynamic> data) {
  final fields = Map<String, dynamic>.fromEntries(
    data.entries.where(
      (e) => !FieldSyncConfig.systemFields.contains(e.key),
    ),
  );
  return _hashPayload(fields);
}

/// حساب الفروقات بين الحالة السابقة والحالية
Map<String, dynamic> _computeDiff(
    Map<String, dynamic> oldData, Map<String, dynamic> newData) {
  final diff = <String, dynamic>{};
  newData.forEach((key, value) {
    if (!oldData.containsKey(key) || oldData[key] != value) {
      diff[key] = value;
    }
  });
  return diff;
}

const _timestampFields = {
  'createdAt', 'updatedAt', 'deletedAt', 'lastModified',
  'lastNightEpoch', 'syncTimestamp', 'createdAtEpoch', 'lastModifiedEpoch',
  'lastActive', 'lastSeen', 'timestamp', 'voidedAt', 'reversedAt',
  'cancelledAt', 'financialFrozenAt',
};

dynamic _normalizeValue(dynamic value, {String? key}) {
  if (value is int) {
    if (key != null && _timestampFields.contains(key)) {
      return _normalizeTimestamp(value);
    }
    return value;
  } else if (value is num) {
    return value;
  } else if (value is Map<String, dynamic>) {
    return _preparePayload(value);
  } else if (value is List) {
    return value.map((item) {
      if (item is Map<String, dynamic>) {
        return _preparePayload(item);
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

String _toCamelCase(String input) {
  if (!input.contains('_')) return input;
  return input.replaceAllMapped(
    RegExp('_([a-z])'),
    (match) => match.group(1)!.toUpperCase(),
  );
}

@Deprecated('استخدم _toCamelCase بدلاً من ذلك')
String _toSnakeCase(String input) {
  final snake = input.replaceAllMapped(
    RegExp('([a-z0-9])([A-Z])'),
    (match) => '${match.group(1)}_${match.group(2)}',
  );
  return snake.replaceAll('-', '_').toLowerCase();
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

// ============================================================================
// Field-Level Sync Support Classes
// ============================================================================

/// ✅ تحسين 3: فحص hash سريع قبل diff مفصل
_FieldLevelDiffResult _computeFieldLevelDiffOptimized(
  String entityName,
  Map<String, dynamic> oldData,
  Map<String, dynamic> newData,
  Map<String, int> oldFieldVersions,
  Map<String, int> oldFieldTimestamps,
  Map<String, String> oldFieldVectorClocks,
  Map<String, String> oldFieldDevices,
  String deviceId,
) {
  // ✅ فحص hash سريع: إذا متطابق، لا يوجد تغيير
  // نستخدم rowHash على مستوى الصف كاملاً — إذا لم يتغير فلا حاجة لـ field diff
  final newFieldsHash = _hashFieldsOnly(newData);
  // لا نستخدم old fieldsHash هنا لأن rowHash != previous.rowHash
  // تم التحقق بالفعل قبل استدعاء هذه الدالة

  final config = FieldSyncConfig.forEntity(entityName);
  final changedFields = <String, dynamic>{};
  final fieldVersions = <String, int>{};
  final fieldTimestamps = <String, int>{};
  final fieldVectorClocks = <String, String>{};
  final fieldDevices = <String, String>{};
  final now = Time.nowEpoch();

  // ✅ فحص فقط الحقول القابلة للتتبع (استثناء حقول النظام)
  final trackableKeys = newData.keys.where((k) {
    if (FieldSyncConfig.systemFields.contains(k)) return false;
    if (config.trackableFields.isNotEmpty &&
        !config.trackableFields.contains(k)) return false;
    return true;
  });

  for (final key in trackableKeys) {
    final oldValue = oldData[key];
    final newValue = newData[key];

    // ✅ Skip إذا القيمة لم تتغير
    if (_valuesEqual(oldValue, newValue)) continue;

    changedFields[key] = newValue;

    // تحديث النسخة
    final oldVersion = oldFieldVersions[key] ?? 0;
    fieldVersions[key] = oldVersion + 1;

    // تحديث الطابع الزمني
    fieldTimestamps[key] = now;

    // تحديث Vector Clock
    final oldVcJson = oldFieldVectorClocks[key] ?? '{}';
    final oldVc = VectorClock.fromJson(oldVcJson);
    final newVc = oldVc.increment(deviceId);
    fieldVectorClocks[key] = newVc.toJson();

    // تحديث الجهاز
    fieldDevices[key] = deviceId;
  }

  return _FieldLevelDiffResult(
    changedFields: changedFields,
    fieldVersions: fieldVersions,
    fieldTimestamps: fieldTimestamps,
    fieldVectorClocks: fieldVectorClocks,
    fieldDevices: fieldDevices,
  );
}

/// نتيجة حساب الفروقات على مستوى الحقل
class _FieldLevelDiffResult {
  _FieldLevelDiffResult({
    required this.changedFields,
    required this.fieldVersions,
    required this.fieldTimestamps,
    required this.fieldVectorClocks,
    required this.fieldDevices,
  });

  final Map<String, dynamic> changedFields;
  final Map<String, int> fieldVersions;
  final Map<String, int> fieldTimestamps;
  final Map<String, String> fieldVectorClocks;
  final Map<String, String> fieldDevices;

  bool get isNotEmpty => changedFields.isNotEmpty;

  /// ✅ Factory للنتيجة الفارغة (تحسين الأداء)
  static _FieldLevelDiffResult empty() => _FieldLevelDiffResult(
        changedFields: {},
        fieldVersions: {},
        fieldTimestamps: {},
        fieldVectorClocks: {},
        fieldDevices: {},
      );

  List<FieldChange> toFieldChanges(String deviceId, String localDeviceId) {
    return changedFields.entries.map((e) => FieldChange(
      fieldName: e.key,
      oldValue: null,
      newValue: e.value,
      version: fieldVersions[e.key] ?? 1,
      timestamp: fieldTimestamps[e.key] ?? 0,
      deviceId: fieldDevices[e.key] ?? localDeviceId,
      vectorClock: fieldVectorClocks[e.key] ?? '{}',
    )).toList();
  }
}

/// ✅ kept for backward compatibility (used by legacy code paths)
_FieldLevelDiffResult _computeFieldLevelDiff(
  String entityName,
  Map<String, dynamic> oldData,
  Map<String, dynamic> newData,
  Map<String, int> oldFieldVersions,
  Map<String, int> oldFieldTimestamps,
  Map<String, String> oldFieldVectorClocks,
  Map<String, String> oldFieldDevices,
  String deviceId,
) {
  return _computeFieldLevelDiffOptimized(
    entityName,
    oldData,
    newData,
    oldFieldVersions,
    oldFieldTimestamps,
    oldFieldVectorClocks,
    oldFieldDevices,
    deviceId,
  );
}

bool _valuesEqual(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  return a.toString() == b.toString();
}

// FieldMetadata مستورد من field_level_sync.dart
