// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_log_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncLogDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncLogTable get syncLog => attachedDatabase.syncLog;
  $SyncConflictsTable get syncConflicts => attachedDatabase.syncConflicts;
  SyncLogDaoManager get managers => SyncLogDaoManager(this);
}

class SyncLogDaoManager {
  final _$SyncLogDaoMixin _db;
  SyncLogDaoManager(this._db);
  $$SyncLogTableTableManager get syncLog =>
      $$SyncLogTableTableManager(_db.attachedDatabase, _db.syncLog);
  $$SyncConflictsTableTableManager get syncConflicts =>
      $$SyncConflictsTableTableManager(_db.attachedDatabase, _db.syncConflicts);
}
