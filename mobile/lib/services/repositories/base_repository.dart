import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';

import '../local_db.dart';
import '../adapters/entity_adapter.dart';
import '../adapters/source.dart';
import '../../sync/vector_clock.dart';
import '../../sync/models/sync_models.dart';

class BaseRepository<D extends DataClass, C extends UpdateCompanion<D>> {
  BaseRepository({
    required this.db,
    required this.table,
    required this.adapter,
  });

  static final Map<String, List<List<Column>>> _conflictTargetCache = {};

  final AppDatabase db;
  final TableInfo<Table, D> table;
  final EntityAdapter<D, C> adapter;

  Future<int> upsertFromJson(
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    final refs = await adapter.resolveRefs(db, json, src: src);
    final comp = adapter.fromJson(json, src: src, refs: refs);

    // التحقق من التعارض قبل الإدراج/التحديث
    final localUuid = _extractUuid(json);
    if (localUuid != null) {
      final existing = await _getLocalRecordByUuid(localUuid);
      if (existing != null) {
        final shouldUpdate = _shouldUpdateLocal(existing, json);
        if (!shouldUpdate) {
          developer.log(
            'Skipping upsert for ${table.actualTableName}/$localUuid: Local record is newer or concurrent',
            name: 'BaseRepository',
          );
          return 0; // تخطي التحديث لأن المحلي أحدث أو متعارض
        }
      }
    }

    final targets = await _resolveConflictTargets();
    Object? lastError;
    StackTrace? lastStack;

    for (final target in targets) {
      try {
        return await db
            .into(table)
            .insert(comp, onConflict: DoUpdate((_) => comp, target: target));
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        if (_isUniqueConstraintError(e)) {
          developer.log(
            'Upsert conflict on ${table.actualTableName} with target ${_targetLabel(target)}',
            error: e,
            stackTrace: st,
            name: 'BaseRepository',
          );
          continue;
        }
        developer.log(
          'Upsert failed for ${table.actualTableName}',
          error: e,
          stackTrace: st,
          name: 'BaseRepository',
        );
        rethrow;
      }
    }

    if (lastError != null && lastStack != null) {
      developer.log(
        'Upsert exhausted conflict targets for ${table.actualTableName}',
        error: lastError,
        stackTrace: lastStack,
        name: 'BaseRepository',
      );
      Error.throwWithStackTrace(lastError, lastStack);
    }

    return db.into(table).insertOnConflictUpdate(comp);
  }

  /// استخراج UUID من البيانات
  String? _extractUuid(Map<String, dynamic> json) {
    return json['local_uuid']?.toString() ??
        json['localUuid']?.toString() ??
        json['booking_uuid']?.toString() ??
        json['uuid']?.toString();
  }

  /// جلب السجل المحلي باستخدام UUID
  Future<Map<String, dynamic>?> _getLocalRecordByUuid(String uuid) async {
    try {
      final query = db.select(table)
        ..where((t) {
          final columns = table.$columns;
          final uuidColumn = columns.firstWhere(
            (c) => c.$name == 'local_uuid' || c.$name == 'localUuid',
            orElse: () => throw Exception('No UUID column found'),
          );
          return (uuidColumn as TextColumn).equals(uuid);
        });

      final result = await query.getSingleOrNull();
      if (result == null) return null;

      // تحويل الكائن إلى Map
      return (result as dynamic).toJson();
    } catch (e) {
      return null;
    }
  }

  /// جلب السجل المحلي بصيغة JSON باستخدام UUID (طريقة عامة)
  Future<Map<String, dynamic>?> getJsonByUuid(String uuid) async {
    return _getLocalRecordByUuid(uuid);
  }

  /// تحديد ما إذا كان يجب تحديث السجل المحلي بناءً على البيانات القادمة
  bool _shouldUpdateLocal(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    // 1. محاولة استخدام Vector Clock
    final remoteClockStr = remote['vector_clock']?.toString() ??
        remote['vectorClock']?.toString();
    final localClockStr =
        local['vector_clock']?.toString() ?? local['vectorClock']?.toString();

    if (remoteClockStr != null && localClockStr != null) {
      try {
        final remoteClock = VectorClock.fromJson(remoteClockStr);
        final localClock = VectorClock.fromJson(localClockStr);
        final comparison = remoteClock.compare(localClock);

        if (comparison == VectorClockComparison.remoteNewer) return true;
        if (comparison == VectorClockComparison.localNewer) return false;
        // في حالة التساوي أو التعارض (concurrent)، ننتقل للمقارنة بالوقت
      } catch (e) {
        // فشل تحليل الساعة، ننتقل للوقت
      }
    }

    // 2. محاولة استخدام updatedAt أو lastModified
    final remoteTs = _extractTimestamp(remote);
    final localTs = _extractTimestamp(local);

    if (remoteTs != null && localTs != null) {
      return remoteTs > localTs;
    }

    // 3. افتراضياً، التحديث القادم من السيرفر يفوز إذا لم تتوفر معلومات
    return true;
  }

  /// استخراج الطابع الزمني من البيانات
  int? _extractTimestamp(Map<String, dynamic> data) {
    final ts = data['updated_at'] ??
        data['updatedAt'] ??
        data['last_modified'] ??
        data['lastModified'] ??
        data['last_modified_epoch'] ??
        data['lastModifiedEpoch'];

    if (ts is int) return ts;
    if (ts is String) {
      final parsed = DateTime.tryParse(ts);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return null;
  }

  Map<String, dynamic> toJsonForSource(D row, {required Source src}) {
    return adapter.toJson(row, src: src);
  }

  Future<List<List<Column>>> _resolveConflictTargets() async {
    final tableName = table.actualTableName;
    final cached = _conflictTargetCache[tableName];
    if (cached != null) {
      return cached;
    }

    final columnsByName = <String, Column>{
      for (final column in table.$columns) column.$name: column,
    };
    final targets = <List<Column>>[];
    final sanitizedName = tableName.replaceAll("'", "''");

    final indexRows =
        await db.customSelect("PRAGMA index_list('$sanitizedName')").get();
    for (final row in indexRows) {
      final isUnique = row.data['unique'] == 1 || row.data['unique'] == true;
      if (!isUnique) {
        continue;
      }
      final indexName = row.data['name']?.toString();
      if (indexName == null || indexName.isEmpty) {
        continue;
      }
      final sanitizedIndex = indexName.replaceAll("'", "''");
      final infoRows =
          await db.customSelect("PRAGMA index_info('$sanitizedIndex')").get();
      final cols = <Column>[];
      for (final info in infoRows) {
        final name = info.data['name']?.toString();
        final column = name != null ? columnsByName[name] : null;
        if (column != null) {
          cols.add(column);
        }
      }
      if (cols.isNotEmpty) {
        targets.add(cols);
      }
    }

    final deduped = _dedupeTargets(targets);
    if (deduped.isEmpty) {
      final pk = table.$primaryKey.toList();
      if (pk.isNotEmpty) {
        deduped.add(pk);
      }
    }

    _conflictTargetCache[tableName] = deduped;
    return deduped;
  }

  List<List<Column>> _dedupeTargets(List<List<Column>> targets) {
    final seen = <String>{};
    final deduped = <List<Column>>[];
    for (final target in targets) {
      final label = _targetLabel(target);
      if (seen.add(label)) {
        deduped.add(target);
      }
    }
    return deduped;
  }

  String _targetLabel(List<Column> target) {
    return target.map((column) => column.name).join(',');
  }

  bool _isUniqueConstraintError(Object error) {
    return error.toString().contains('UNIQUE constraint failed');
  }
}
