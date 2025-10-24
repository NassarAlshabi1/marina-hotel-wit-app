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

// ... (all table definitions remain the same)

extension RoomJson on Room {
  Map<String, dynamic> toJson() => {
    'id': id,
    'roomNumber': roomNumber,
    'type': type,
    'price': price,
    'status': status,
    'imageUrl': imageUrl,
    'localUuid': localUuid,
    'serverId': serverId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'lastModified': lastModified,
    'version': version,
    'origin': origin,
  };

  static Room fromJson(Map<String, dynamic> json) => Room(
    id: Value(json['id']),
    roomNumber: json['roomNumber'],
    type: json['type'],
    price: json['price'],
    status: json['status'],
    imageUrl: Value(json['imageUrl']),
    localUuid: json['localUuid'],
    serverId: Value(json['serverId']),
    createdAt: json['createdAt'],
    updatedAt: json['updatedAt'],
    deletedAt: Value(json['deletedAt']),
    lastModified: json['lastModified'],
    version: json['version'],
    origin: json['origin'],
  );
}

// Add similar extensions for Booking, BookingNote, Employee, Expense, CashTransaction, Payment, OutboxRow, SyncState...

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
  // ... (rest remains the same)
}