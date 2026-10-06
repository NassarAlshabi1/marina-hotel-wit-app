import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import 'resolve_result.dart';
import 'source.dart';

/// ✅ (G-3): نقطة التقاط السجل الذي يُتخطّى لأن مرجعه الخارجي (FK) غير
/// محلول. طبقة المجال تُثبّتها لتخزين الحمولة وإعادة ربطها لاحقاً عبر UUID
/// بدلاً من إهمالها (كان التخطي صامتاً = فقدان حركة مالية).
typedef SkippedRecordSink =
    Future<void> Function(
      Map<String, dynamic> json, {
      required String tableName,
      required String collectionId,
      required Source src,
      required String? skipReason,
    });

abstract class EntityAdapter<
  D extends d.DataClass,
  C extends d.UpdateCompanion<D>
> {
  String get collectionId;
  String get drivePath;
  String get tableName;

  Future<ResolveResult> resolveRefs(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  });

  C fromJson(
    Map<String, dynamic> json, {
    required Source src,
    required ResolveResult refs,
  });

  Map<String, dynamic> toJson(D model, {required Source src});
}
