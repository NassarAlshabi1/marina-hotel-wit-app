// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shift_notes_dao.dart';

// ignore_for_file: type=lint
mixin _$ShiftNotesDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShiftNotesTable get shiftNotes => attachedDatabase.shiftNotes;
  ShiftNotesDaoManager get managers => ShiftNotesDaoManager(this);
}

class ShiftNotesDaoManager {
  final _$ShiftNotesDaoMixin _db;
  ShiftNotesDaoManager(this._db);
  $$ShiftNotesTableTableManager get shiftNotes => $$ShiftNotesTableTableManager(_db.attachedDatabase, _db.shiftNotes);
}
