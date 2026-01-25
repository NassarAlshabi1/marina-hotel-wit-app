import 'package:appwrite/models.dart' as models;
import 'package:drift/drift.dart' as d;
import '../utils/time.dart';
import 'local_db.dart';
import 'appwrite_logger.dart';

typedef DocumentMapper<T extends d.Insertable> = T? Function(
  Map<String, dynamic> data,
  String localUuid,
  SyncFieldsHelper helper,
);

typedef DocumentValidator = bool Function(Map<String, dynamic> data);

class SyncFieldsHelper {
  final AppDatabase database;
  // ignore: unused_field
  final AppwriteLogger _logger;

  SyncFieldsHelper(this.database) : _logger = AppwriteLogger();

  d.Value<T?> nullableValue<T>(T? value) {
    return value == null ? const d.Value.absent() : d.Value(value);
  }

  int normalizeEpoch(dynamic value, {int? fallback}) {
    if (value == null) {
      return fallback ?? Time.nowEpoch();
    }
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is DateTime) return value.toUtc().millisecondsSinceEpoch ~/ 1000;
    if (value is num) return value.toInt();
    if (value is String && value.isNotEmpty) {
      final parsedInt = int.tryParse(value);
      if (parsedInt != null) return parsedInt;
      final parsedDouble = double.tryParse(value);
      if (parsedDouble != null) return parsedDouble.toInt();
      final parsedDate = DateTime.tryParse(value);
      if (parsedDate != null) {
        return parsedDate.toUtc().millisecondsSinceEpoch ~/ 1000;
      }
    }
    return fallback ?? Time.nowEpoch();
  }

  int? normalizeEpochNullable(dynamic value) {
    return value == null ? null : normalizeEpoch(value);
  }

  int asInt(dynamic value, {int fallback = 0}) {
    return asIntNullable(value) ?? fallback;
  }

  int? asIntNullable(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.isNotEmpty) {
      final parsedInt = int.tryParse(value);
      if (parsedInt != null) return parsedInt;
      final parsedDouble = double.tryParse(value);
      if (parsedDouble != null) return parsedDouble.toInt();
    }
    return null;
  }

  double asDouble(dynamic value, {double fallback = 0.0}) {
    return asDoubleNullable(value) ?? fallback;
  }

  double? asDoubleNullable(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String && value.isNotEmpty) {
      return double.tryParse(value);
    }
    return null;
  }

  String? asString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  String asStringRequired(dynamic value, {String fallback = ''}) {
    return asString(value) ?? fallback;
  }
}

class SyncResult {
  final int processed;
  final int skipped;
  final int failed;
  final List<String> errors;

  SyncResult({
    required this.processed,
    required this.skipped,
    required this.failed,
    required this.errors,
  });

  int get total => processed + skipped + failed;
  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() =>
      'SyncResult(processed: $processed, skipped: $skipped, failed: $failed)';
}

class GenericSyncProcessor<T extends d.Table, C extends d.Insertable<dynamic>> {
  final AppDatabase database;
  final SyncFieldsHelper helper;
  final AppwriteLogger _logger;
  final String tableName;
  final d.TableInfo<T, dynamic> table;

  GenericSyncProcessor({
    required this.database,
    required this.tableName,
    required this.table,
  })  : helper = SyncFieldsHelper(database),
        _logger = AppwriteLogger();

  Future<SyncResult> syncDocuments({
    required List<models.Document> documents,
    required DocumentMapper<C> mapper,
    DocumentValidator? validator,
    bool useBatch = true,
    String localUuidKey = 'localUuid',
  }) async {
    if (documents.isEmpty) {
      return SyncResult(processed: 0, skipped: 0, failed: 0, errors: []);
    }

    int processed = 0;
    int skipped = 0;
    int failed = 0;
    final errors = <String>[];

    if (useBatch) {
      final result = await _syncWithBatch(
        documents: documents,
        mapper: mapper,
        validator: validator,
        localUuidKey: localUuidKey,
      );
      return result;
    }

    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        final localUuid = helper.asString(data[localUuidKey]) ?? doc.$id;

        if (localUuid.isEmpty) {
          skipped++;
          continue;
        }

        if (validator != null && !validator(data)) {
          skipped++;
          continue;
        }

        final companion = mapper(data, localUuid, helper);
        if (companion == null) {
          skipped++;
          continue;
        }

        await database
            .into(table)
            .insert(companion, mode: d.InsertMode.insertOrReplace);
        processed++;
      } catch (e) {
        failed++;
        final errorMsg = 'Failed to sync $tableName ${doc.$id}: $e';
        errors.add(errorMsg);
        _logger.warning(errorMsg, tag: 'SYNC');
      }
    }

    return SyncResult(
      processed: processed,
      skipped: skipped,
      failed: failed,
      errors: errors,
    );
  }

  Future<SyncResult> _syncWithBatch({
    required List<models.Document> documents,
    required DocumentMapper<C> mapper,
    DocumentValidator? validator,
    String localUuidKey = 'localUuid',
  }) async {
    int processed = 0;
    int skipped = 0;
    int failed = 0;
    final errors = <String>[];

    await database.transaction(() async {
      await database.batch((batch) {
        for (final doc in documents) {
          try {
            final data = Map<String, dynamic>.from(doc.data);
            final localUuid = helper.asString(data[localUuidKey]) ?? doc.$id;

            if (localUuid.isEmpty) {
              skipped++;
              continue;
            }

            if (validator != null && !validator(data)) {
              skipped++;
              continue;
            }

            final companion = mapper(data, localUuid, helper);
            if (companion == null) {
              skipped++;
              continue;
            }

            batch.insert(table, companion, mode: d.InsertMode.insertOrReplace);
            processed++;
          } catch (e) {
            failed++;
            final errorMsg = 'Failed to sync $tableName ${doc.$id}: $e';
            errors.add(errorMsg);
          }
        }
      });
    });

    return SyncResult(
      processed: processed,
      skipped: skipped,
      failed: failed,
      errors: errors,
    );
  }
}

class SyncProcessorFactory {
  final AppDatabase database;

  SyncProcessorFactory(this.database);

  GenericSyncProcessor<Rooms, RoomsCompanion> rooms() {
    return GenericSyncProcessor<Rooms, RoomsCompanion>(
      database: database,
      tableName: 'rooms',
      table: database.rooms,
    );
  }

  GenericSyncProcessor<Employees, EmployeesCompanion> employees() {
    return GenericSyncProcessor<Employees, EmployeesCompanion>(
      database: database,
      tableName: 'employees',
      table: database.employees,
    );
  }

  GenericSyncProcessor<Expenses, ExpensesCompanion> expenses() {
    return GenericSyncProcessor<Expenses, ExpensesCompanion>(
      database: database,
      tableName: 'expenses',
      table: database.expenses,
    );
  }

  GenericSyncProcessor<Bookings, BookingsCompanion> bookings() {
    return GenericSyncProcessor<Bookings, BookingsCompanion>(
      database: database,
      tableName: 'bookings',
      table: database.bookings,
    );
  }

  GenericSyncProcessor<Payments, PaymentsCompanion> payments() {
    return GenericSyncProcessor<Payments, PaymentsCompanion>(
      database: database,
      tableName: 'payments',
      table: database.payments,
    );
  }

  GenericSyncProcessor<Debts, DebtsCompanion> debts() {
    return GenericSyncProcessor<Debts, DebtsCompanion>(
      database: database,
      tableName: 'debts',
      table: database.debts,
    );
  }
}

RoomsCompanion mapRoom(
  Map<String, dynamic> data,
  String localUuid,
  SyncFieldsHelper h,
) {
  final roomNumber = h.asString(data['roomNumber']);
  if (roomNumber == null || roomNumber.isEmpty) {
    throw ArgumentError('roomNumber is required');
  }

  return RoomsCompanion(
    roomNumber: d.Value(roomNumber),
    type: d.Value(h.asStringRequired(data['type'])),
    price: d.Value(h.asDouble(data['price'])),
    status: d.Value(h.asStringRequired(data['status'], fallback: 'available')),
    imageUrl: h.nullableValue(h.asString(data['imageUrl'])),
    localUuid: d.Value(localUuid),
    serverId: h.nullableValue(h.asIntNullable(data['serverId'])),
    createdAt: d.Value(h.normalizeEpoch(data['createdAt'])),
    updatedAt: d.Value(h.normalizeEpoch(data['updatedAt'])),
    deletedAt: h.nullableValue(h.normalizeEpochNullable(data['deletedAt'])),
    lastModified: d.Value(h.normalizeEpoch(data['lastModified'])),
    version: d.Value(h.asInt(data['version'], fallback: 1)),
    origin: d.Value(h.asStringRequired(data['origin'], fallback: 'server')),
  );
}

EmployeesCompanion mapEmployee(
  Map<String, dynamic> data,
  String localUuid,
  SyncFieldsHelper h,
) {
  final name = h.asString(data['name']);
  if (name == null || name.isEmpty) {
    throw ArgumentError('name is required');
  }

  return EmployeesCompanion(
    localUuid: d.Value(localUuid),
    serverId: h.nullableValue(h.asIntNullable(data['serverId'])),
    createdAt: d.Value(h.normalizeEpoch(data['createdAt'])),
    updatedAt: d.Value(h.normalizeEpoch(data['updatedAt'])),
    deletedAt: h.nullableValue(h.normalizeEpochNullable(data['deletedAt'])),
    lastModified: d.Value(h.normalizeEpoch(data['lastModified'])),
    version: d.Value(h.asInt(data['version'], fallback: 1)),
    origin: d.Value(h.asStringRequired(data['origin'], fallback: 'server')),
    name: d.Value(name),
    basicSalary: d.Value(h.asDouble(data['basicSalary'])),
    position: d.Value(h.asStringRequired(data['position'])),
    phone: d.Value(h.asStringRequired(data['phone'])),
    hireDate: d.Value(h.asStringRequired(data['hireDate'])),
    status: d.Value(h.asStringRequired(data['status'])),
  );
}

ExpensesCompanion mapExpense(
  Map<String, dynamic> data,
  String localUuid,
  SyncFieldsHelper h,
) {
  final expenseType = h.asString(data['expenseType']);
  if (expenseType == null || expenseType.isEmpty) {
    throw ArgumentError('expenseType is required');
  }

  return ExpensesCompanion(
    localUuid: d.Value(localUuid),
    serverId: h.nullableValue(h.asIntNullable(data['serverId'])),
    createdAt: d.Value(h.normalizeEpoch(data['createdAt'])),
    updatedAt: d.Value(h.normalizeEpoch(data['updatedAt'])),
    deletedAt: h.nullableValue(h.normalizeEpochNullable(data['deletedAt'])),
    lastModified: d.Value(h.normalizeEpoch(data['lastModified'])),
    version: d.Value(h.asInt(data['version'], fallback: 1)),
    origin: d.Value(h.asStringRequired(data['origin'], fallback: 'server')),
    expenseType: d.Value(expenseType),
    relatedId: h.nullableValue(h.asIntNullable(data['relatedId'])),
    description: d.Value(h.asStringRequired(data['description'])),
    amount: d.Value(h.asDouble(data['amount'])),
    date: d.Value(h.asStringRequired(data['date'])),
    cashTransactionId: h.nullableValue(
      h.asIntNullable(data['cashTransactionId']),
    ),
  );
}

bool validateRoom(Map<String, dynamic> data) {
  final roomNumber = data['roomNumber'];
  return roomNumber != null && roomNumber.toString().isNotEmpty;
}

bool validateEmployee(Map<String, dynamic> data) {
  final name = data['name'];
  return name != null && name.toString().isNotEmpty;
}

bool validateExpense(Map<String, dynamic> data) {
  final expenseType = data['expenseType'];
  return expenseType != null && expenseType.toString().isNotEmpty;
}
