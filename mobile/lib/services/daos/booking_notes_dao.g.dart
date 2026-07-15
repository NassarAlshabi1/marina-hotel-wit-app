// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_notes_dao.dart';

// ignore_for_file: type=lint
mixin _$BookingNotesDaoMixin on DatabaseAccessor<AppDatabase> {
  $RoomsTable get rooms => attachedDatabase.rooms;
  $BookingsTable get bookings => attachedDatabase.bookings;
  $BookingNotesTable get bookingNotes => attachedDatabase.bookingNotes;
  BookingNotesDaoManager get managers => BookingNotesDaoManager(this);
}

class BookingNotesDaoManager {
  final _$BookingNotesDaoMixin _db;
  BookingNotesDaoManager(this._db);
  $$RoomsTableTableManager get rooms => $$RoomsTableTableManager(_db.attachedDatabase, _db.rooms);
  $$BookingsTableTableManager get bookings => $$BookingsTableTableManager(_db.attachedDatabase, _db.bookings);
  $$BookingNotesTableTableManager get bookingNotes =>
      $$BookingNotesTableTableManager(_db.attachedDatabase, _db.bookingNotes);
}
