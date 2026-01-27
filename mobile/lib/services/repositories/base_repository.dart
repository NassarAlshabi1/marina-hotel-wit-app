import 'package:drift/drift.dart';

import '../local_db.dart';
import '../adapters/entity_adapter.dart';
import '../adapters/source.dart';

class BaseRepository<D extends DataClass, C extends UpdateCompanion<D>> {
  BaseRepository(
      {required this.db, required this.table, required this.adapter});

  final AppDatabase db;
  final TableInfo<Table, D> table;
  final EntityAdapter<D, C> adapter;

  Future<int> upsertFromJson(Map<String, dynamic> json,
      {required Source src}) async {
    final refs = await adapter.resolveRefs(db, json, src: src);
    final comp = adapter.fromJson(json, src: src, refs: refs);
    return db.into(table).insertOnConflictUpdate(comp);
  }

  Map<String, dynamic> toJsonForSource(D row, {required Source src}) {
    return adapter.toJson(row, src: src);
  }
}
