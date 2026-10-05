import 'package:drift/drift.dart';

import '../../local_db.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/base_adapter.dart';

/// Adapter لجدول orphan_quarantine
class OrphanQuarantineAdapter extends BaseAdapter<OrphanQuarantine, OrphanQuarantineCompanion> {
  OrphanQuarantineAdapter(super.idResolver);

  @override
  String get collectionId => 'orphan_quarantine';

  @override
  String get drivePath => 'orphan_quarantine.json';

  @override
  String get tableName => 'orphan_quarantine';

  @override
  OrphanQuarantineCompanion fromJsonForSource(
    OrphanQuarantine row, {
    Source src = Source.appwrite,
  }) {
    return OrphanQuarantineCompanion(
      entity: Value(row.entity),
      localUuid: Value(row.localUuid),
      dataJson: Value(row.dataJson),
      reason: Value(row.reason),
      quarantinedAt: Value(row.quarantinedAt),
      missingParentUuid: row.missingParentUuid != null
          ? Value(row.missingParentUuid!)
          : const Value.absent(),
      localId: row.localId != null ? Value(row.localId!) : const Value.absent(),
    );
  }

  @override
  OrphanQuarantine fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    return OrphanQuarantine(
      id: _parseInt(json['id']),
      entity: _str(json['entity']),
      localUuid: _str(json['localUuid']),
      dataJson: _str(json['dataJson']),
      reason: _str(json['reason']),
      quarantinedAt: _parseInt(json['quarantinedAt']),
      missingParentUuid: json['missingParentUuid'] as String?,
      localId: _parseIntOrNull(json['localId']),
    );
  }

  @override
  Map<String, dynamic> toJsonForSource(
    OrphanQuarantine row, {
    Source src = Source.appwrite,
  }) {
    return {
      'id': row.id,
      'entity': row.entity,
      'localUuid': row.localUuid,
      'dataJson': row.dataJson,
      'reason': row.reason,
      'quarantinedAt': row.quarantinedAt,
      'missingParentUuid': row.missingParentUuid,
      'localId': row.localId,
    };
  }

  @override
  Future<void> upsertFromJson(
    Map<String, dynamic> json, {
    Source src = Source.appwrite,
  }) async {
    final row = fromJson(json);
    final comp = fromJsonForSource(row, src: src);
    await table.into(row.table).insertOnConflictUpdate(comp);
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  int? _parseIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _str(dynamic value) => value?.toString() ?? '';
}