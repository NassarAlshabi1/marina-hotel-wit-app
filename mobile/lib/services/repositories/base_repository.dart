import 'dart:developer' as developer;

import 'package:drift/drift.dart';

import '../local_db.dart';
import '../adapters/entity_adapter.dart';
import '../adapters/source.dart';

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
    final targets = await _resolveConflictTargets();
    Object? lastError;
    StackTrace? lastStack;

    for (final target in targets) {
      try {
        return await db.into(table).insert(
              comp,
              onConflict: DoUpdate((_) => comp, target: target),
            );
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

    final indexRows = await db.customSelect(
      "PRAGMA index_list('$sanitizedName')",
    ).get();
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
      final infoRows = await db.customSelect(
        "PRAGMA index_info('$sanitizedIndex')",
      ).get();
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
    return target.map((column) => column.$name).join(',');
  }

  bool _isUniqueConstraintError(Object error) {
    return error.toString().contains('UNIQUE constraint failed');
  }
}
