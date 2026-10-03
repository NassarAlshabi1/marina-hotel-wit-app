import 'package:drift/drift.dart';

import '../../local_db.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/base_adapter.dart';

/// Adapter لجدول pending_links
class PendingLinksAdapter extends BaseAdapter<PendingLink, PendingLinksCompanion> {
  PendingLinksAdapter(super.idResolver);

  @override
  String get collectionId => 'pending_links';

  @override
  String get drivePath => 'pending_links.json';

  @override
  String get tableName => 'pending_links';

  @override
  PendingLinksCompanion fromJsonForSource(
    PendingLink row, {
    Source src = Source.appwrite,
  }) {
    return PendingLinksCompanion(
      childEntity: Value(row.childEntity),
      childLocalUuid: Value(row.childLocalUuid),
      parentEntity: Value(row.parentEntity),
      parentLocalUuid: row.parentLocalUuid != null
          ? Value(row.parentLocalUuid!)
          : const Value.absent(),
      parentServerId: row.parentServerId != null
          ? Value(row.parentServerId!)
          : const Value.absent(),
      linkType: Value(row.linkType),
      childField: Value(row.childField),
      parentField: Value(row.parentField),
      status: Value(row.status),
      resolveAttempts: Value(row.resolveAttempts),
      lastError: row.lastError != null ? Value(row.lastError!) : const Value.absent(),
      createdAt: Value(row.createdAt),
      lastAttemptAt: row.lastAttemptAt != null
          ? Value(row.lastAttemptAt!)
          : const Value.absent(),
      resolvedAt: row.resolvedAt != null
          ? Value(row.resolvedAt!)
          : const Value.absent(),
      metadataJson: row.metadataJson != null
          ? Value(row.metadataJson!)
          : const Value.absent(),
    );
  }

  @override
  PendingLink fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    return PendingLink(
      id: _parseInt(json['id']),
      childEntity: _str(json['childEntity']),
      childLocalUuid: _str(json['childLocalUuid']),
      parentEntity: _str(json['parentEntity']),
      parentLocalUuid: json['parentLocalUuid'] as String?,
      parentServerId: json['parentServerId'] as String?,
      linkType: _str(json['linkType']),
      childField: _str(json['childField']),
      parentField: _str(json['parentField']),
      status: _str(json['status']),
      resolveAttempts: _parseInt(json['resolveAttempts']),
      lastError: json['lastError'] as String?,
      createdAt: _parseInt(json['createdAt']),
      lastAttemptAt: _parseIntOrNull(json['lastAttemptAt']),
      resolvedAt: _parseIntOrNull(json['resolvedAt']),
      metadataJson: json['metadataJson'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJsonForSource(
    PendingLink row, {
    Source src = Source.appwrite,
  }) {
    return {
      'id': row.id,
      'childEntity': row.childEntity,
      'childLocalUuid': row.childLocalUuid,
      'parentEntity': row.parentEntity,
      'parentLocalUuid': row.parentLocalUuid,
      'parentServerId': row.parentServerId,
      'linkType': row.linkType,
      'childField': row.childField,
      'parentField': row.parentField,
      'status': row.status,
      'resolveAttempts': row.resolveAttempts,
      'lastError': row.lastError,
      'createdAt': row.createdAt,
      'lastAttemptAt': row.lastAttemptAt,
      'resolvedAt': row.resolvedAt,
      'metadataJson': row.metadataJson,
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