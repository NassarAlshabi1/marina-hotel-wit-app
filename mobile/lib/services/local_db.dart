import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'local_db.g.dart';

class Kv extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get op => text()(); // create|update|delete
  TextColumn get localUuid => text()();
  IntColumn get serverId => integer().nullable()();
  TextColumn get dataJson => text()();
  IntColumn get clientTs => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

// Sync fields mixin
mixin SyncFields {
  TextColumn get localUuid => text()();
  IntColumn get serverId => integer().nullable()();
  IntColumn get lastModified => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get origin => text().withDefault(const Constant('local'))();
}

class Rooms extends Table with SyncFields {
  TextColumn get roomNumber => text()();
  TextColumn get type => text()();
  RealColumn get price => real()();
  TextColumn get status => text()();
  @override
  Set<Column> get primaryKey => {localUuid};
}

class Bookings extends Table with SyncFields {
  IntColumn get bookingId => integer().nullable()();
  TextColumn get guestName => text()();
  TextColumn get guestPhone => text().nullable()();
  TextColumn get guestIdType => text().nullable()();
  TextColumn get guestIdNumber => text().nullable()();
  TextColumn get roomNumber => text()();
  TextColumn get checkinDate => text()();
  TextColumn get checkoutDate => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('محجوزة'))();
  TextColumn get notes => text().nullable()();
  IntColumn get expectedNights => integer().nullable()();
  IntColumn get calculatedNights => integer().nullable()();
  @override
  Set<Column> get primaryKey => {localUuid};
}

class BookingNotes extends Table with SyncFields {
  IntColumn get noteId => integer().nullable()();
  IntColumn get bookingId => integer()();
  TextColumn get noteText => text()();
  TextColumn get alertType => text().nullable()();
  TextColumn get alertUntil => text().nullable()();
  IntColumn get isActive => integer().withDefault(const Constant(1))();
  @override
  Set<Column> get primaryKey => {localUuid};
}

class Employees extends Table with SyncFields {
  IntColumn get employeeId => integer().nullable()();
  TextColumn get name => text()();
  RealColumn get basicSalary => real().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  @override
  Set<Column> get primaryKey => {localUuid};
}

class Expenses extends Table with SyncFields {
  IntColumn get expenseId => integer().nullable()();
  TextColumn get expenseType => text()();
  IntColumn get relatedId => integer().nullable()();
  TextColumn get description => text()();
  RealColumn get amount => real()();
  TextColumn get date => text()();
  @override
  Set<Column> get primaryKey => {localUuid};
}

class CashTransactions extends Table with SyncFields {
  IntColumn get cashId => integer().nullable()();
  IntColumn get registerId => integer()();
  TextColumn get transactionType => text()();
  RealColumn get amount => real()();
  TextColumn get referenceType => text()();
  IntColumn get referenceId => integer()();
  TextColumn get description => text().nullable()();
  TextColumn get transactionTime => text()();
  @override
  Set<Column> get primaryKey => {localUuid};
}

class Suppliers extends Table with SyncFields {
  IntColumn get supplierId => integer().nullable()();
  TextColumn get name => text()();
  @override
  Set<Column> get primaryKey => {localUuid};
}

class Users extends Table with SyncFields {
  IntColumn get userId => integer().nullable()();
  TextColumn get username => text()();
  TextColumn get fullName => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get userType => text().nullable()();
  IntColumn get isActive => integer().withDefault(const Constant(1))();
  @override
  Set<Column> get primaryKey => {localUuid};
}

class RoomImages extends Table with SyncFields {
  IntColumn get imageId => integer().nullable()();
  TextColumn get roomNumber => text()();
  TextColumn get url => text()();
  @override
  Set<Column> get primaryKey => {localUuid};
}

@DriftDatabase(tables: [
  Kv, Outbox, Rooms, Bookings, BookingNotes, Employees, Expenses, CashTransactions, Suppliers, Users, RoomImages
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // Simple kv helpers
  Future<void> setKv(String key, String value) async => into(kv).insertOnConflictUpdate(KvCompanion(key: Value(key), value: Value(value)));
  Future<String?> getKv(String key) async => (select(kv)..where((t) => t.key.equals(key))).getSingleOrNull().then((r) => r?.value);
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'marina_hotel.db'));
    return NativeDatabase(file, logStatements: false);
  });
}
