import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import 'resolve_result.dart';
import 'source.dart';

abstract class EntityAdapter<D extends d.DataClass, C extends d.UpdateCompanion<D>> {
  String get collectionId;
  String get drivePath;
  String get tableName;

  Future<ResolveResult> resolveRefs(AppDatabase db, Map<String, dynamic> json, {required Source src});

  C fromJson(Map<String, dynamic> json, {required Source src, required ResolveResult refs});

  Map<String, dynamic> toJson(D model, {required Source src});
}
