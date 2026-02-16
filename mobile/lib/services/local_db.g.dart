// GENERATED CODE - DO NOT MODIFY BY HAND
// PLACEHOLDER - Will be replaced by build_runner

part of 'local_db.dart';

// ignore_for_file: type=lint

// Placeholder classes - build_runner will regenerate
class $SyncLogTable extends SyncLog with TableInfo<$SyncLogTable, SyncLogData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncLogTable(this.attachedDatabase, [this._alias]);
  @override
  List<GeneratedColumn> get $columns => [];
  @override
  String get aliasedName => _alias ?? 'sync_log';
  @override
  String get actualTableName => 'sync_log';
  @override
  VerificationContext validateIntegrity(Insertable<SyncLogData> instance, {bool isInserting = false}) => VerificationContext();
  @override
  Set<GeneratedColumn> get $primaryKey => {};
  @override
  SyncLogData map(Map<String, dynamic> data, {String? tablePrefix}) => throw UnimplementedError();
  @override
  $SyncLogTable createAlias(String alias) => $SyncLogTable(attachedDatabase, alias);
}

class SyncLogData extends DataClass implements Insertable<SyncLogData> {
  final int id;
  final String syncId;
  final String direction;
  final String deviceId;
  final String metadata;
  final String? operations;
  final int checksumMatched;
  final String status;
  final String createdAt;
  final String? completedAt;
  const SyncLogData({required this.id, required this.syncId, required this.direction, required this.deviceId, required this.metadata, this.operations, required this.checksumMatched, required this.status, required this.createdAt, this.completedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) => {};
  factory SyncLogData.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) => throw UnimplementedError();
  @override
  String toString() => 'SyncLogData(id: $id)';
  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) => other is SyncLogData && other.id == id;
  SyncLogData copyWith({int? id, String? syncId, String? direction, String? deviceId, String? metadata, String? operations, int? checksumMatched, String? status, String? createdAt, String? completedAt}) => throw UnimplementedError();
  SyncLogCompanion toCompanion(bool nullToAbsent) => throw UnimplementedError();
}

class SyncLogCompanion extends UpdateCompanion<SyncLogData> {
  final Value<int> id;
  final Value<String> syncId;
  final Value<String> direction;
  final Value<String> deviceId;
  final Value<String> metadata;
  final Value<String?> operations;
  final Value<int> checksumMatched;
  final Value<String> status;
  final Value<String> createdAt;
  final Value<String?> completedAt;
  const SyncLogCompanion({this.id = const Value.absent(), this.syncId = const Value.absent(), this.direction = const Value.absent(), this.deviceId = const Value.absent(), this.metadata = const Value.absent(), this.operations = const Value.absent(), this.checksumMatched = const Value.absent(), this.status = const Value.absent(), this.createdAt = const Value.absent(), this.completedAt = const Value.absent()});
  SyncLogCompanion.insert({this.id = const Value.absent(), required String syncId, required String direction, required String deviceId, required String metadata, this.operations = const Value.absent(), this.checksumMatched = const Value.absent(), this.status = const Value.absent(), required String createdAt, this.completedAt = const Value.absent()}) : syncId = Value(syncId), direction = Value(direction), deviceId = Value(deviceId), metadata = Value(metadata), createdAt = Value(createdAt);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) => {};
}

class $SyncConflictsTable extends SyncConflicts with TableInfo<$SyncConflictsTable, SyncConflictRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncConflictsTable(this.attachedDatabase, [this._alias]);
  @override
  List<GeneratedColumn> get $columns => [];
  @override
  String get aliasedName => _alias ?? 'sync_conflicts';
  @override
  String get actualTableName => 'sync_conflicts';
  @override
  VerificationContext validateIntegrity(Insertable<SyncConflictRow> instance, {bool isInserting = false}) => VerificationContext();
  @override
  Set<GeneratedColumn> get $primaryKey => {};
  @override
  SyncConflictRow map(Map<String, dynamic> data, {String? tablePrefix}) => throw UnimplementedError();
  @override
  $SyncConflictsTable createAlias(String alias) => $SyncConflictsTable(attachedDatabase, alias);
}

class SyncConflictRow extends DataClass implements Insertable<SyncConflictRow> {
  final int id;
  final int logId;
  final String uuid;
  final String targetTable;
  final String resolution;
  final String localPayload;
  final String remotePayload;
  final String createdAt;
  const SyncConflictRow({required this.id, required this.logId, required this.uuid, required this.targetTable, required this.resolution, required this.localPayload, required this.remotePayload, required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) => {};
  factory SyncConflictRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) => throw UnimplementedError();
  @override
  String toString() => 'SyncConflictRow(id: $id)';
  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) => other is SyncConflictRow && other.id == id;
  SyncConflictRow copyWith({int? id, int? logId, String? uuid, String? targetTable, String? resolution, String? localPayload, String? remotePayload, String? createdAt}) => throw UnimplementedError();
  SyncConflictsCompanion toCompanion(bool nullToAbsent) => throw UnimplementedError();
}

class SyncConflictsCompanion extends UpdateCompanion<SyncConflictRow> {
  final Value<int> id;
  final Value<int> logId;
  final Value<String> uuid;
  final Value<String> targetTable;
  final Value<String> resolution;
  final Value<String> localPayload;
  final Value<String> remotePayload;
  final Value<String> createdAt;
  const SyncConflictsCompanion({this.id = const Value.absent(), this.logId = const Value.absent(), this.uuid = const Value.absent(), this.targetTable = const Value.absent(), this.resolution = const Value.absent(), this.localPayload = const Value.absent(), this.remotePayload = const Value.absent(), this.createdAt = const Value.absent()});
  SyncConflictsCompanion.insert({this.id = const Value.absent(), required int logId, required String uuid, required String targetTable, required String resolution, required String localPayload, required String remotePayload, required String createdAt}) : logId = Value(logId), uuid = Value(uuid), targetTable = Value(targetTable), resolution = Value(resolution), localPayload = Value(localPayload), remotePayload = Value(remotePayload), createdAt = Value(createdAt);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) => {};
}

// AppDatabase stub
abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $SyncLogTable get syncLog => throw UnimplementedError();
  $SyncConflictsTable get syncConflicts => throw UnimplementedError();
}
