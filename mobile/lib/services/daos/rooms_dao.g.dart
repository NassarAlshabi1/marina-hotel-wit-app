// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rooms_dao.dart';

// ignore_for_file: type=lint
mixin _$RoomsDaoMixin on DatabaseAccessor<AppDatabase> {
  $RoomsTable get rooms => attachedDatabase.rooms;
  RoomsDaoManager get managers => RoomsDaoManager(this);
}

class RoomsDaoManager {
  final _$RoomsDaoMixin _db;
  RoomsDaoManager(this._db);
  $$RoomsTableTableManager get rooms => $$RoomsTableTableManager(_db.attachedDatabase, _db.rooms);
}
