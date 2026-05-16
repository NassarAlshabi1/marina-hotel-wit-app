// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_info_dao.dart';

// ignore_for_file: type=lint
mixin _$GuestInfoDaoMixin on DatabaseAccessor<AppDatabase> {
  $GuestInfosTable get guestInfos => attachedDatabase.guestInfos;
  GuestInfoDaoManager get managers => GuestInfoDaoManager(this);
}

class GuestInfoDaoManager {
  final _$GuestInfoDaoMixin _db;
  GuestInfoDaoManager(this._db);
  $$GuestInfosTableTableManager get guestInfos =>
      $$GuestInfosTableTableManager(_db.attachedDatabase, _db.guestInfos);
}
