// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookings_dao.dart';

// ignore_for_file: type=lint
mixin _$BookingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $RoomsTable get rooms => attachedDatabase.rooms;
  $BookingsTable get bookings => attachedDatabase.bookings;
  BookingsDaoManager get managers => BookingsDaoManager(this);
}

class BookingsDaoManager {
  final _$BookingsDaoMixin _db;
  BookingsDaoManager(this._db);
  $$RoomsTableTableManager get rooms => $$RoomsTableTableManager(_db.attachedDatabase, _db.rooms);
  $$BookingsTableTableManager get bookings => $$BookingsTableTableManager(_db.attachedDatabase, _db.bookings);
}
