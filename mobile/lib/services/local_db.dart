import 'dart:async';
import 'package:drift/drift.dart';
import 'package:drift_sqflite/drift_sqflite.dart';

part 'local_db.g.dart';

mixin SyncFields on Table {
  TextColumn get localUuid => text().unique()();
  IntColumn get serverId => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get lastModified => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get origin => text().withDefault(const Constant('local'))();
}

class Rooms extends Table with SyncFields {
  TextColumn get roomNumber => text()();
  TextColumn get type => text()();
  RealColumn get price => real()();
  TextColumn get status => text()();
  TextColumn get imageUrl => text().nullable()();
  @override
  Set<Column> get primaryKey => {roomNumber};
}

class Bookings extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get serverBookingId => integer().nullable()();
  TextColumn get roomNumber => text().references(Rooms, #roomNumber)();
  TextColumn get guestName => text()();
  TextColumn get guestPhone => text()();
  TextColumn get guestIdType => text().withDefault(const Constant('بطاقة شخصية'))();
  TextColumn get guestIdNumber => text().withDefault(const Constant(''))();
  TextColumn get guestIdIssueDate => text().nullable()();
  TextColumn get guestIdIssuePlace => text().nullable()();
  TextColumn get guestNationality => text()();
  TextColumn get guestEmail => text().nullable()();
  TextColumn get guestAddress => text().nullable()();
  TextColumn get checkinDate => text()();
  TextColumn get checkoutDate => text().nullable()();
  TextColumn get actualCheckout => text().nullable()();
  TextColumn get status => text()();
  TextColumn get notes => text().nullable()();
  IntColumn get expectedNights => integer().withDefault(const Constant(1))();
  IntColumn get calculatedNights => integer().withDefault(const Constant(1))();

  @override
  List<Index> get indexes => [];
}

class BookingNotes extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookingId => integer().references(Bookings, #id)();
  TextColumn get noteText => text()();
  TextColumn get alertType => text()();
  TextColumn get alertUntil => text().nullable()();
  IntColumn get isActive => integer().withDefault(const Constant(1))();
}

class Employees extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  RealColumn get basicSalary => real()();
  TextColumn get position => text().withDefault(const Constant('موظف'))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get hireDate => text().withDefault(const Constant(''))();
  TextColumn get status => text()();
  
  // Getter for backward compatibility
  RealColumn get salary => basicSalary;
}

class Expenses extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get expenseType => text()();
  IntColumn get relatedId => integer().nullable()();
  TextColumn get description => text()();
  RealColumn get amount => real()();
  TextColumn get date => text()();
  IntColumn get cashTransactionId => integer().nullable()();
}

class CashTransactions extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get registerId => integer().nullable()();
  TextColumn get transactionType => text()();
  RealColumn get amount => real()();
  TextColumn get referenceType => text().nullable()();
  IntColumn get referenceId => integer().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get transactionTime => text()();
  IntColumn get createdBy => integer().nullable()();
}

class Payments extends Table with SyncFields {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get serverPaymentId => integer().nullable()();
  IntColumn get bookingLocalId => integer().nullable().references(Bookings, #id)();
  IntColumn get serverBookingId => integer().nullable()();
  TextColumn get roomNumber => text().nullable()();
  RealColumn get amount => real()();
  TextColumn get paymentDate => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get paymentMethod => text()();
  TextColumn get revenueType => text()();
  IntColumn get cashTransactionLocalId => integer().nullable().references(CashTransactions, #id)();
  IntColumn get cashTransactionServerId => integer().nullable()();

  @override
  List<Index> get indexes => [];
}

class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get op => text()();
  TextColumn get localUuid => text()();
  IntColumn get serverId => integer().nullable()();
  TextColumn get payload => text()();
  IntColumn get clientTs => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

class SyncState extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get lastServerTs => integer().withDefault(const Constant(0))();
  IntColumn get lastPullTs => integer().withDefault(const Constant(0))();
  IntColumn get lastPushTs => integer().withDefault(const Constant(0))();
  IntColumn get isSyncing => integer().withDefault(const Constant(0))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Rooms,
  Bookings,
  BookingNotes,
  Employees,
  Expenses,
  CashTransactions,
  Payments,
  Outbox,
  SyncState,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(bookings, bookings.guestIdType);
            await m.addColumn(bookings, bookings.guestIdNumber);
            await m.addColumn(bookings, bookings.guestIdIssueDate);
            await m.addColumn(bookings, bookings.guestIdIssuePlace);
            await m.addColumn(bookings, bookings.actualCheckout);
            await m.addColumn(bookings, bookings.expectedNights);
            await m.customStatement('UPDATE bookings SET expected_nights = calculated_nights');
          }
        },
      );
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final executor = SqfliteQueryExecutor.inDatabaseFolder(path: 'marina_hotel.db', logStatements: false);
    return executor;
  });
}
