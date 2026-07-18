import 'package:drift/drift.dart';

import '../adapters/adapter_registry.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'employees_dao.g.dart';

@DriftAccessor(tables: [Employees])
class EmployeesDao extends DatabaseAccessor<AppDatabase> with _$EmployeesDaoMixin {
  EmployeesDao(super.db, this.outboxDao, this.adapters);
  final OutboxDao outboxDao;
  final AdapterRegistry adapters;

  Future<List<Employee>> list() async {
    return (select(employees)..where((t) => t.deletedAt.isNull())..orderBy([(t) => OrderingTerm(expression: t.name, mode: OrderingMode.asc)])).get();
  }

  Stream<List<Employee>> watchAll() {
    return (select(employees)..where((t) => t.deletedAt.isNull())..orderBy([(t) => OrderingTerm(expression: t.name, mode: OrderingMode.asc)])).watch();
  }

  Future<Employee?> getById(int id) => (select(employees)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Employee?> getByLocalUuid(String localUuid) async {
    return (select(employees)..where((t) => t.localUuid.equals(localUuid))..limit(1)).getSingleOrNull();
  }

  Future<int> insertOne(EmployeesCompanion data, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final insertedId = await into(employees).insert(data);
      if (!originIsServer) {
        // Outbox merge handled by repository layer
      }
      return insertedId;
    });
  }

  Future<int> updateById(int id, EmployeesCompanion data, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final existing = await getById(id);
      if (existing == null) return 0;
      final comp = data.copyWith(
        updatedAt: Value(Time.nowEpoch()),
        lastModified: Value(Time.nowEpoch()),
        version: Value(existing.version + 1),
      );
      await update(employees).replace(comp);
      if (!originIsServer) {
        // Outbox merge handled by repository layer
      }
      return 1;
    });
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final existing = await getById(id);
      if (existing == null) return 0;
      await (update(employees)..where((t) => t.id.equals(id))).write(
        EmployeesCompanion(
          deletedAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
          version: Value(existing.version + 1),
        ),
      );
      if (!originIsServer) {
        // Outbox merge handled by repository layer
      }
      return 1;
    });
  }

  Future<int> getRecordCount() async {
    final query = selectOnly(employees)..addColumns([employees.id.count()]);
    final result = await query.getSingle();
    return result.read(employees.id.count()) ?? 0;
  }

  Future<void> clearAllData() async {
    await delete(employees).go();
  }

  Future<void> importFromJson(List<Map<String, dynamic>> data, {bool clearExisting = false}) async {
    await transaction(() async {
      if (clearExisting) {
        await delete(employees).go();
      }
      for (final empJson in data) {
        final emp = Employee.fromJson(empJson);
        await into(employees).insertOnConflictUpdate(
          EmployeesCompanion(
            id: Value(emp.id),
            localUuid: Value(emp.localUuid),
            serverId: Value(emp.serverId),
            name: Value(emp.name),
            phone: Value(emp.phone),
            role: Value(emp.role),
            basicSalary: Value(emp.basicSalary),
            hireDate: Value(emp.hireDate),
            status: Value(emp.status),
            createdAt: Value(emp.createdAt),
            updatedAt: Value(emp.updatedAt),
            deletedAt: Value(emp.deletedAt),
            lastModified: Value(emp.lastModified),
            version: Value(emp.version),
            origin: Value(emp.origin),
            createdAtIso: Value(emp.createdAtIso),
            updatedAtIso: Value(emp.updatedAtIso),
            deletedAtIso: Value(emp.deletedAtIso),
            createdAtEpoch: Value(emp.createdAtEpoch),
            lastModifiedEpoch: Value(emp.lastModifiedEpoch),
            vectorClock: Value(emp.vectorClock),
          ),
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> exportToJson() async {
    final list = await this.list();
    return list.map((e) => e.toJson()).toList();
  }
}
